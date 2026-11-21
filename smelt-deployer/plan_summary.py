#!/usr/bin/env python3
"""Summarise a `terraform show -json` plan for a smelt deploy (SME-665).

    python3 -I smelt-deployer/plan_summary.py <plan.json> --sha <SHA> [--json]

Reports only: it exits 0 for every plan it can read, and the model decides
(DEPLOY.md). It lists every change by address and changed attribute *path*;
values are shown only for the two image paths, and never where a
`*_sensitive` marks them. Exit 2, with one line on stderr, for a plan it can't
read (a missing file, bad JSON, a format_version whose major isn't 1).
"""

import argparse
import json
import re
import sys

DEPLOY = "module.smelt.kubernetes_deployment_v1.smelt"
IMAGE_PATHS = (
    "spec[0].template[0].spec[0].container[name=smelt].image",
    "spec[0].template[0].spec[0].container[name=smelt].env[name=SANDBOX_IMAGE].value",
)
IMAGE_REPO = {IMAGE_PATHS[0]: "ghcr.io/cconstantine/smelt", IMAGE_PATHS[1]: "ghcr.io/cconstantine/smelt-sandbox"}
# The objects SME-664 gave prevent_destroy (terraform/smelt/database.tf, rbac.tf).
GUARDED = (
    "module.smelt.random_password.database",
    "module.smelt.kubernetes_secret_v1.database",
    "module.smelt.kubernetes_stateful_set_v1.database",
    "module.smelt.kubernetes_namespace_v1.park",
)
# Nested blocks whose items are named: shown as container[name=smelt], not
# container[0], so a path reads the same whatever the order.
NAMED_LISTS = {"container", "init_container", "env", "port", "volume", "volume_mount"}


class Unreadable(Exception):
    pass


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            plan = json.load(f)
    except OSError as e:
        raise Unreadable("can't read %s: %s" % (path, e.strerror or e))
    except ValueError as e:
        raise Unreadable("%s isn't valid JSON: %s" % (path, e))
    if not isinstance(plan, dict):
        raise Unreadable("%s isn't a terraform plan" % path)
    fv = str(plan.get("format_version", ""))
    if fv.split(".")[0] != "1":
        raise Unreadable("can't summarise this format: format_version %r (only 1.x)" % fv)
    return plan


def step(key, item, idx):
    if key in NAMED_LISTS and isinstance(item, dict) and isinstance(item.get("name"), str):
        return "%s[name=%s]" % (key, item["name"])
    return "%s[%d]" % (key, idx)


def join(prefix, part):
    return part if not prefix else prefix + "." + part


def keyed(key, items):
    """{path step: item} for a list attribute."""
    if not isinstance(items, list):
        return {}
    return {step(key, it, i): it for i, it in enumerate(items)}


def diff(before, after, prefix=""):
    """Leaf paths whose value differs between before and after."""
    if isinstance(before, dict) and isinstance(after, dict):
        out = []
        for k in sorted(set(before) | set(after)):
            b, a = before.get(k), after.get(k)
            if isinstance(b, list) or isinstance(a, list):
                bk, ak = keyed(k, b), keyed(k, a)
                if (b is None) != (a is None) and not (bk or ak):
                    out.append(join(prefix, k))
                for s in sorted(set(bk) | set(ak), key=lambda s: (s.split("[")[0], s)):
                    out += diff(bk.get(s), ak.get(s), join(prefix, s))
            else:
                out += diff(b, a, join(prefix, k))
        return out
    if before == after:
        return []
    if isinstance(before, dict) or isinstance(after, dict):
        # A block added or removed: name the block and its leaves.
        return diff(before if isinstance(before, dict) else {},
                    after if isinstance(after, dict) else {}, prefix) or [prefix]
    return [prefix]


def marked(tree, ref, prefix=""):
    """Paths set to true in an after_unknown/*_sensitive tree; list items are
    named from `ref` (the matching before/after value) where it has a name."""
    if tree is True:
        return [prefix]
    out = []
    if isinstance(tree, dict):
        ref = ref if isinstance(ref, dict) else {}
        for k in sorted(tree):
            sub, r = tree[k], ref.get(k)
            if isinstance(sub, list):
                rl = r if isinstance(r, list) else []
                for i, it in enumerate(sub):
                    ri = rl[i] if i < len(rl) else None
                    out += marked(it, ri, join(prefix, step(k, ri, i)))
            else:
                out += marked(sub, r, join(prefix, k))
    return out


def lookup(value, path):
    for part in path.split("."):
        m = re.fullmatch(r"([^\[]+)\[(?:name=(.*)|(\d+))\]", part)
        if m:
            key, name, idx = m.groups()
            items = value.get(key) if isinstance(value, dict) else None
            if not isinstance(items, list):
                return None
            if name is not None:
                value = next((it for it in items if isinstance(it, dict) and it.get("name") == name), None)
            else:
                value = items[int(idx)] if int(idx) < len(items) else None
        else:
            value = value.get(part) if isinstance(value, dict) else None
        if value is None:
            return None
    return value


def under(path, top):
    """Whether path is top or lies inside it."""
    return path == top or path.startswith(top + ".") or path.startswith(top + "[")


def actions_label(actions):
    if sorted(actions) == ["create", "delete"]:
        return "replace (%s)" % "+".join(actions)
    return "+".join(actions)


def change_of(rc):
    ch = rc.get("change") or {}
    before, after = ch.get("before"), ch.get("after")
    unknown = marked(ch.get("after_unknown") or {}, after)
    sensitive = set(marked(ch.get("before_sensitive") or {}, before)) | \
        set(marked(ch.get("after_sensitive") or {}, after))
    paths = [p for p in diff(before, after) if not any(under(p, u) for u in unknown)]
    values = {}
    for p in IMAGE_PATHS:
        if p in paths and not any(under(p, s) for s in sensitive):
            values[p] = {"before": lookup(before, p), "after": lookup(after, p)}
    return {
        "address": rc.get("address", "?"),
        "actions": actions_label(ch.get("actions") or []),
        "action_reason": rc.get("action_reason"),
        "replace_paths": [".".join(str(x) for x in rp) for rp in ch.get("replace_paths") or []],
        "paths": paths,
        "unknown_paths": unknown,
        "values": values,
    }


def bare(address):
    return re.sub(r"\[[^\]]*\]$", "", address)


def ref_problems(header, rcs, sha):
    """Where the source ref or the deployment's planned images aren't <sha>."""
    out = []
    src = header["module_source"] or ""
    if not src.endswith("?ref=" + sha):
        out.append("module source %s isn't ?ref=%s" % (src or "(none)", sha))
    for rc in rcs:
        if rc.get("address") != DEPLOY:
            continue
        ch = rc.get("change") or {}
        after = ch.get("after")
        sensitive = marked(ch.get("after_sensitive") or {}, after)
        for p in IMAGE_PATHS:
            got = lookup(after, p) if after else None
            want = "%s:%s" % (IMAGE_REPO[p], sha)
            label = "SANDBOX_IMAGE" if "SANDBOX_IMAGE" in p else "image"
            if got is None or any(under(p, s) for s in sensitive):
                out.append("the planned %s can't be read" % label)
            elif got != want:
                out.append("the planned %s is %s, not %s" % (label, got, want))
    return out


def summarise(plan, sha):
    calls = ((plan.get("configuration") or {}).get("root_module") or {}).get("module_calls") or {}
    header = {k: plan.get(k) for k in ("terraform_version", "format_version", "applyable", "complete", "errored")}
    header["module_source"] = (calls.get("smelt") or {}).get("source")
    rcs = plan.get("resource_changes") or []
    live = [rc for rc in rcs if (rc.get("change") or {}).get("actions") != ["no-op"]]
    changes = [change_of(rc) for rc in live]
    noops = len(rcs) - len(live)

    flags = []
    for rc in live:
        acts = (rc.get("change") or {}).get("actions") or []
        if bare(rc["address"]) in GUARDED and acts not in (["update"], ["no-op"]):
            flags.append("GUARDED %s" % rc["address"])
    for rc in live:
        addr, acts = rc["address"], (rc.get("change") or {}).get("actions") or []
        if not addr.startswith("module.smelt."):
            flags.append("OUTSIDE_MODULE %s" % addr)
        if acts == ["delete"]:
            flags.append("DELETE %s" % addr)
        elif sorted(acts) == ["create", "delete"]:
            flags.append("REPLACE %s" % addr)
        elif acts == ["forget"]:
            flags.append("FORGET %s" % addr)
    refs = ref_problems(header, rcs, sha)
    if refs:
        flags.append("REF_MISMATCH want %s: %s" % (sha, "; ".join(refs)))
    if live and header["applyable"] is False:
        flags.append("NOT_APPLYABLE the plan says applyable=false")
    if header["errored"]:
        flags.append("ERRORED the plan says errored=true")
    deferred = plan.get("deferred_changes") or []
    if deferred:
        flags.append("DEFERRED %d change(s) Terraform couldn't plan yet" % len(deferred))

    notes = []
    if any(f.startswith("GUARDED ") for f in flags):
        notes.append("GUARDED objects carry prevent_destroy (SME-664): Terraform should have refused this plan")
    if header["complete"] is False:
        notes.append("INCOMPLETE complete=false: every -target plan says so; nothing outside the target is planned")
    drift = plan.get("resource_drift") or []
    if drift:
        notes.append("DRIFT %d object(s) differ from state; informational, refresh only" % len(drift))

    if not live:
        kind = "no-changes"
    elif (len(changes) == 1 and changes[0]["address"] == DEPLOY and changes[0]["actions"] == "update"
          and not changes[0]["unknown_paths"] and set(changes[0]["paths"]) <= set(IMAGE_PATHS)):
        kind = "image-only"
    else:
        kind = "wider"
    return {
        "header": header, "kind": kind, "flags": flags, "notes": notes, "changes": changes,
        "noops": noops,
        "drift": [{"address": d.get("address"), "actions": "+".join((d.get("change") or {}).get("actions") or [])} for d in drift],
        "outputs": sorted(k for k, v in (plan.get("output_changes") or {}).items() if (v or {}).get("actions") != ["no-op"]),
        "deferred": [((d.get("resource_change") or {}).get("address"), d.get("reason")) for d in deferred],
    }


def text(s):
    h = s["header"]
    out = ["terraform %s, plan format %s, applyable=%s complete=%s errored=%s" % (
        h["terraform_version"], h["format_version"], h["applyable"], h["complete"], h["errored"]),
        "module source: %s" % h["module_source"], "", "CHANGES (%d; %d no-op):" % (len(s["changes"]), s["noops"])]
    for ch in s["changes"]:
        extra = ""
        if ch["action_reason"]:
            extra += " reason=%s" % ch["action_reason"]
        if ch["replace_paths"]:
            extra += " replace_paths=%s" % ",".join(ch["replace_paths"])
        out.append("  %s  %s%s" % (ch["address"], ch["actions"].upper() if ch["actions"].startswith("replace") else ch["actions"], extra))
        for p in ch["paths"]:
            v = ch["values"].get(p)
            out.append("    %s: %s -> %s" % (p, v["before"], v["after"]) if v else "    %s" % p)
        for p in ch["unknown_paths"]:
            out.append("    %s (known after apply)" % p)
    for d in s["drift"]:
        out.append("drift (refresh): %s %s" % (d["address"], d["actions"]))
    for name in s["outputs"]:
        out.append("output changes: %s" % name)
    for addr, reason in s["deferred"]:
        out.append("deferred: %s (%s)" % (addr, reason))
    out.append("")
    out += ["NOTE: %s" % n for n in s["notes"]]
    out += ["FLAG: %s" % f for f in s["flags"]]
    out.append("KIND: %s" % s["kind"])
    if s["kind"] == "wider":
        out.append("The module or something else changed, not just the images: read every listed resource in plan.txt.")
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("plan")
    ap.add_argument("--sha", required=True)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    try:
        plan = load(a.plan)
        s = summarise(plan, a.sha)
    except Unreadable as e:
        print("plan_summary: %s" % e, file=sys.stderr)
        return 2
    except (AttributeError, KeyError, TypeError) as e:
        print("plan_summary: unexpected plan shape: %s" % e.__class__.__name__, file=sys.stderr)
        return 2
    sys.stdout.write(json.dumps(s, indent=1) + "\n" if a.json else text(s))
    return 0


if __name__ == "__main__":
    sys.exit(main())
