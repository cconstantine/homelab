#!/usr/bin/env python3
"""Build a zh-verified Terraform provider mirror for GitHub-release-hosted providers.

SME-465: this repo's Terraform providers download from GitHub *release assets*
(gavinbunney/kubectl, ryanwholey/pihole, cloudflare/cloudflare today, detected
automatically), and GitHub's release-download path intermittently answers 504 for
hours, stalling `terraform init` in retries. This script mirrors exactly those
providers BEFORE init runs, so init never touches the flaky path:

  1. Read .terraform.lock.hcl (never written; its hashes are the trust root).
  2. Ask registry.terraform.io where each locked provider version is hosted.
  3. For the github.com-hosted ones: fetch the zip via api.github.com's
     octet-stream asset endpoint (live while the /releases/download/ redirector
     504s) and place it ONLY if sha256(zip) matches one of that provider's `zh:`
     hashes — zh: is the zip's sha256, so the lockfile itself authenticates the
     download; no extra trust, no published-SHA256SUMS dependency.
  4. Write the CLI config (default ~/deploy.tfrc) LAST, atomically: the strict
     pin — filesystem_mirror include + direct exclude for exactly the mirrored
     providers. The loose form was measured still reaching the flaky direct host.
  5. Refuse to shrink the pin set silently: if an existing config pins a provider
     the current lockfile no longer yields as github-hosted, exit non-zero —
     dropping a pin sends that provider back to the flaky path. Clearing old
     mirror/config state stays the operator's call; the script deletes nothing.

Run from the repo root; defaults --mirror ~/tf-mirror --config ~/deploy.tfrc
--target linux_amd64. Idempotent: a mirrored zip whose sha256 is still zh-valid is
kept without re-download (the cheap per-provider registry lookups still run). Any
failure exits non-zero loudly — stop-and-report per DEPLOY.md; never fall back to
bare init, never touch the lockfile, no -lock=false.
"""

import argparse
import hashlib
import http.client
import json
import os
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

REGISTRY = "https://registry.terraform.io"
API = "https://api.github.com"
UA = "smelt-deployer-tf-provider-mirror (SME-465)"
TIMEOUT = 30


def fail(msg):
    sys.stderr.write("tf_provider_mirror: ERROR: %s\n" % msg)
    sys.exit(1)


def get(url, accept=None, timeout=TIMEOUT):
    headers = {"User-Agent": UA}
    if accept:
        headers["Accept"] = accept
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers),
                                  timeout=timeout)


def get_json(url, what):
    try:
        with get(url, accept="application/json") as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        note = ""
        if e.code in (403, 429):
            note = (" — unauthenticated GitHub API limit is 60 req/h/IP (the asset "
                    "route uses ~6 per cold build); stop-and-report, do not "
                    "retry-until-green")
        fail("%s: GET %s -> HTTP %d%s" % (what, url, e.code, note))
    except (urllib.error.URLError, OSError) as e:
        fail("%s: GET %s -> %s" % (what, url, e))
    except (json.JSONDecodeError, http.client.HTTPException) as e:
        # a 200 with a non-JSON/truncated body, or a truncated read: a clean error,
        # never a traceback (SME-465 review L2).
        fail("%s: GET %s -> malformed response (%s: %s)"
             % (what, url, type(e).__name__, e))


def parse_lock(path):
    """[{source, version, zh:set(hex)}] from a terraform lockfile (read-only)."""
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError as e:
        fail("cannot read %s: %s (run from the repo root)" % (path, e))
    out = []
    for m in re.finditer(r'provider "([^"]+)" \{\n(.*?)\n\}', text, re.S):
        body = m.group(2)
        ver = re.search(r'^\s*version\s*=\s*"([^"]+)"', body, re.M)
        if not ver:
            fail("%s: block for %s has no version" % (path, m.group(1)))
        out.append({"source": m.group(1), "version": ver.group(1),
                    "zh": set(re.findall(r'"zh:([0-9a-f]{64})"', body))})
    if not out:
        fail("%s: no provider blocks found (is this a terraform lockfile?)" % path)
    return out


def registry_download(source, version, os_, arch):
    ns, name = source.split("/")[1], source.split("/")[2]
    url = "%s/v1/providers/%s/%s/%s/download/%s/%s" % (
        REGISTRY, ns, name, version, os_, arch)
    meta = get_json(url, "%s %s registry lookup" % (source, version))
    return meta.get("download_url", "")


def github_release(dl_url):
    """(owner, repo, tag, filename) if dl_url is a github.com release download."""
    u = urllib.parse.urlparse(dl_url)
    if u.netloc.lower() not in ("github.com", "www.github.com"):
        return None
    m = re.match(r"^/(.+)/releases/download/(.+)/([^/]+)$", u.path)
    if not m:
        fail("cannot parse GitHub release path %s" % u.path)
    owner, _, repo = m.group(1).partition("/")
    if not owner or "/" in repo:
        fail("unexpected owner/repo in %s" % u.path)
    return owner, repo, urllib.parse.unquote(m.group(2)), m.group(3)


def asset_url(source, owner, repo, tag, filename):
    rel = get_json("%s/repos/%s/%s/releases/tags/%s"
                   % (API, owner, repo, urllib.parse.quote(tag, safe="")),
                   "%s release lookup" % source)
    for a in rel.get("assets", []):
        if a.get("name") == filename:
            return "%s/repos/%s/%s/releases/assets/%s" % (API, owner, repo, a["id"])
    fail("%s: asset %s not in release %s/%s %s" % (source, filename, owner, repo, tag))


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_verified(url, zh, dest, label):
    """Stream url to dest via a temp file; rename only if sha256(zip) is in zh."""
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    tmp = None
    try:
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(dest), prefix=".tmp-")
        h = hashlib.sha256()
        with os.fdopen(fd, "wb") as t, get(url, accept="application/octet-stream") as r:
            while True:
                chunk = r.read(1 << 20)
                if not chunk:
                    break
                h.update(chunk)
                t.write(chunk)
        digest = h.hexdigest()
        if digest not in zh:
            fail("%s: sha256 %s is not one of the lockfile's zh: hashes — "
                 "refusing to place" % (label, digest))
        os.chmod(tmp, 0o644)
        os.replace(tmp, dest)
        tmp = None
    except urllib.error.HTTPError as e:
        note = " (HTTP %d; unauthenticated API limit is 60 req/h/IP — stop-and-report)" % e.code \
            if e.code in (403, 429) else ""
        fail("%s: asset download failed: HTTP %d%s" % (label, e.code, note))
    except (urllib.error.URLError, OSError) as e:
        fail("%s: asset download failed: %s" % (label, e))
    except (http.client.HTTPException, json.JSONDecodeError) as e:
        # truncated/garbled response mid-download: clean error, never a traceback.
        fail("%s: asset download failed (malformed response: %s: %s)"
             % (label, type(e).__name__, e))
    finally:
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def write_tfrc(config, mirror, sources):
    """Strict pin, written last and atomically: init uses the mirror for exactly
    `sources` and everything else stays direct. The loose form leaked to direct."""
    lines = ["# written by smelt-deployer/tf_provider_mirror.py (SME-465); re-run "
             "the script, do not edit\n", "provider_installation {\n"]
    if sources:
        inc = "".join('    "%s",\n' % s for s in sources)
        lines += ['  filesystem_mirror {\n', '    path    = "%s"\n' % mirror,
                  "    include = [\n", inc, "    ]\n", "  }\n",
                  "  direct {\n", "    exclude = [\n", inc, "    ]\n", "  }\n"]
    else:
        lines.append("  direct {}\n")
    lines.append("}\n")
    d = os.path.dirname(config) or "."
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".deploy.tfrc-")
    try:
        with os.fdopen(fd, "w") as f:
            f.writelines(lines)
        os.chmod(tmp, 0o644)
        os.replace(tmp, config)
        tmp = None
    finally:
        if tmp is not None:
            try:
                os.unlink(tmp)
            except OSError:
                pass


def guard_no_pin_shrink(config, new_pins):
    """The pin set must never shrink silently: dropping a provider from
    filesystem_mirror include sends it back to the flaky direct host — the exact
    bypass this mechanism exists to stop. If an existing tfrc pins a provider the
    current lockfile no longer yields as github-hosted, that is either an
    unallowed lockfile edit or a real provider removal/re-host, and either way it
    is stop-and-report, not a side effect of a re-run. The script never deletes
    anything: clearing the old mirror slots + config is the operator's call, so a
    legitimate change (recorded in a homelab PR) re-runs clean once made."""
    try:
        with open(config, encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        return
    except OSError as e:
        fail("cannot read %s to check for a pin shrink: %s" % (config, e))
    m = re.search(r"include\s*=\s*\[(.*?)\]", text, re.S)
    old_pins = set(re.findall(r'"([^"]+)"', m.group(1))) if m else set()
    dropped = sorted(old_pins - set(new_pins))
    if dropped:
        fail("%s pins %s, but %s not github-hosted in the current "
             ".terraform.lock.hcl — refusing to shrink the pin set (a silent drop "
             "sends the provider back to the flaky direct path). If the lockfile "
             "just changed, stop-and-report and review that edit; if a provider "
             "removal/re-host is legitimate (recorded in a homelab PR), clearing "
             "the old mirror slots and %s is the operator's call — this script "
             "never deletes them." % (config, ", ".join(dropped),
                                      "was" if len(dropped) == 1 else "were",
                                      config))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--mirror", default="~/tf-mirror")
    ap.add_argument("--config", default="~/deploy.tfrc")
    ap.add_argument("--target", default="linux_amd64")
    args = ap.parse_args()
    if "_" not in args.target:
        fail("--target must look like linux_amd64")
    os_, arch = args.target.split("_", 1)
    mirror = os.path.abspath(os.path.expanduser(args.mirror))
    config = os.path.abspath(os.path.expanduser(args.config))

    providers = parse_lock(".terraform.lock.hcl")
    os.makedirs(mirror, exist_ok=True)
    mirrored = []
    for p in providers:
        label = "%s %s" % (p["source"], p["version"])
        parts = p["source"].split("/")
        if len(parts) != 3 or parts[0] != "registry.terraform.io":
            print("%s: left to direct (non-registry source)" % label)
            continue
        dl = registry_download(p["source"], p["version"], os_, arch)
        gh = github_release(dl) if dl else None
        if gh is None:
            print("%s: direct (not github-hosted)" % label)
            continue
        owner, repo, tag, filename = gh
        dest = os.path.join(mirror, *parts, filename)
        if os.path.isfile(dest) and sha256_file(dest) in p["zh"]:
            print("%s: cached (zh-verified) %s" % (label, filename))
        else:
            fetch_verified(asset_url(p["source"], owner, repo, tag, filename),
                           p["zh"], dest, label)
            print("%s: mirrored (zh-verified) %s" % (label, filename))
        mirrored.append(p["source"])

    guard_no_pin_shrink(config, sorted(mirrored))
    write_tfrc(config, mirror, sorted(mirrored))
    print("wrote %s (mirror %s; %d provider(s) pinned to the mirror)"
          % (config, mirror, len(mirrored)))


if __name__ == "__main__":
    main()
