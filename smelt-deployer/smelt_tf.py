#!/usr/bin/env python3
"""The three-line smelt.tf edit, and the check of a rebased deploy commit (SME-665).

    python3 -I smelt-deployer/smelt_tf.py set <SHA> [--file smelt.tf]
    python3 -I smelt-deployer/smelt_tf.py check-commit <SHA> [--diff FILE]

`set` rewrites exactly three lines of smelt.tf to <SHA> (SME-663): the module
source's `?ref=` (an https or, after SME-677, an ssh git source; the form is
kept), `image` and `sandbox_image`. Each is found by an anchored
pattern that must match exactly one line; a missing or doubled line fails
without writing anything. Whitespace is kept. If all three already name <SHA>
it says "already at <SHA>" and exits 3 (nothing to deploy).

`check-commit` reads HEAD's diff (`git show -U0 --format= HEAD`, or --diff)
and accepts it only if it touches smelt.tf alone, and only those lines (one or
more of the three), each set to <SHA> with the rest of the line unchanged.
Exit 0 accepted, 1 refused.
"""

import argparse
import re
import subprocess
import sys

SHA_RE = re.compile(r"^[0-9a-f]{12}$")

# (name, pattern): group 1 is everything before the value, 2 the value, 3 the rest.
LINES = (
    ("source", re.compile(
        r'^(\s*source\s*=\s*"git::(?:https://|ssh://git@)github\.com/cconstantine/smelt\.git'
        r'//terraform/smelt\?ref=)([^"\s]+)("\s*)$')),
    ("image", re.compile(
        r'^(\s*image\s*=\s*"ghcr\.io/cconstantine/smelt:)([^"\s]+)("\s*)$')),
    ("sandbox_image", re.compile(
        r'^(\s*sandbox_image\s*=\s*"ghcr\.io/cconstantine/smelt-sandbox:)([^"\s]+)("\s*)$')),
)


class EditError(Exception):
    pass


class AlreadyAt(Exception):
    pass


def check_sha(sha):
    if not SHA_RE.match(sha):
        raise EditError("%r is not a 12-character lowercase hex SHA" % sha)


def set_sha(path, sha):
    """Rewrite the three lines of `path` to `sha`; returns [(old, new)] lines."""
    check_sha(sha)
    with open(path, encoding="utf-8", newline="") as f:
        lines = f.read().splitlines(keepends=True)
    hits = {}
    for name, pat in LINES:
        found = [i for i, l in enumerate(lines) if pat.match(l.rstrip("\r\n"))]
        if len(found) != 1:
            raise EditError("%s: the %s line matched %d times, expected exactly 1 "
                            "(nothing written)" % (path, name, len(found)))
        hits[name] = found[0]
    values = {n: LINES_BY_NAME[n].match(lines[i].rstrip("\r\n")).group(2)
              for n, i in hits.items()}
    if all(v == sha for v in values.values()):
        raise AlreadyAt("already at %s" % sha)
    changed = []
    for name, i in hits.items():
        body = lines[i].rstrip("\r\n")
        eol = lines[i][len(body):]
        new = LINES_BY_NAME[name].sub(lambda m: m.group(1) + sha + m.group(3), body) + eol
        if new != lines[i]:
            changed.append((lines[i].rstrip("\r\n"), new.rstrip("\r\n")))
            lines[i] = new
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write("".join(lines))
    return changed


LINES_BY_NAME = dict(LINES)


def which(line):
    """(name, value, the line without its value) for one of the three lines."""
    for name, pat in LINES:
        m = pat.match(line)
        if m:
            return name, m.group(2), (m.group(1), m.group(3))
    return None, None, None


def check_diff(text, sha):
    """Raise EditError unless `text` (a -U0 diff) only moves the three lines to `sha`."""
    check_sha(sha)
    files = re.findall(r"^diff --git a/(\S+) b/(\S+)$", text, re.M)
    if not files:
        raise EditError("the commit changes nothing")
    others = sorted({b for _, b in files if b != "smelt.tf"} | {a for a, _ in files if a != "smelt.tf"})
    if others:
        raise EditError("the commit touches another file: %s" % ", ".join(others))
    removed, added = {}, {}
    for line in text.splitlines():
        if line.startswith(("---", "+++")) or not line[:1] in ("-", "+"):
            continue
        body = line[1:]
        name, value, rest = which(body)
        if name is None:
            raise EditError("the commit changes a line that isn't one of the three: %s" % body.strip())
        side = removed if line[0] == "-" else added
        if name in side:
            raise EditError("the commit changes the %s line twice" % name)
        side[name] = (value, rest)
    if set(removed) != set(added) or not added:
        raise EditError("the commit's removed lines (%s) and added lines (%s) don't pair up"
                        % (", ".join(sorted(removed)) or "none", ", ".join(sorted(added)) or "none"))
    moved = sorted(n for n in added if added[n][1] != removed[n][1])
    if moved:
        raise EditError("the commit changes more than the value of the %s line(s)" % ", ".join(moved))
    added = {n: v for n, (v, _) in added.items()}
    wrong = ["%s=%s" % (n, v) for n, v in sorted(added.items()) if v != sha]
    if wrong:
        raise EditError("the commit sets a line to something other than %s: %s" % (sha, ", ".join(wrong)))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("set")
    s.add_argument("sha")
    s.add_argument("--file", default="smelt.tf")
    c = sub.add_parser("check-commit")
    c.add_argument("sha")
    c.add_argument("--diff")
    args = ap.parse_args(argv)
    try:
        if args.cmd == "set":
            for old, new in set_sha(args.file, args.sha):
                print("- %s\n+ %s" % (old.strip(), new.strip()))
            print("smelt_tf: %s set to %s" % (args.file, args.sha))
        else:
            if args.diff:
                with open(args.diff, encoding="utf-8") as f:
                    text = f.read()
            else:
                text = subprocess.run(["git", "show", "-U0", "--format=", "HEAD"], check=True,
                                      capture_output=True, text=True).stdout
            check_diff(text, args.sha)
            print("smelt_tf: HEAD changes only the three lines, all to %s" % args.sha)
    except AlreadyAt as e:
        print("smelt_tf: %s" % e)
        return 3
    except (EditError, OSError, subprocess.CalledProcessError) as e:
        print("smelt_tf: FAIL: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
