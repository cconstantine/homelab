#!/usr/bin/env python3
"""Sanitise a `terraform show -json` plan into a test fixture (SME-665).

    python3 -I sanitize_plan.py <raw plan.json> <fixture.json>

`terraform show -json` prints sensitive values in clear, with only a
`*_sensitive` mask beside them. This keeps what plan_summary.py reads
(format_version, terraform_version, applyable, complete, errored,
resource_changes, resource_drift, output_changes, deferred_changes, and each
module call's source), drops prior_state, planned_values and variables, and
replaces every value a `*_sensitive` mask marks with "SENSITIVE-MARKER-<n>".
It then refuses to write the fixture if the database password (read from the
raw plan's prior state) or any other sensitive value appears anywhere in it.
Used by make_fixtures.sh; the tests never run it.
"""

import json
import sys

KEEP = ("format_version", "terraform_version", "applyable", "complete",
        "errored", "resource_changes", "resource_drift", "output_changes",
        "deferred_changes")
PASSWORD_ADDR = "module.smelt.random_password.database[0]"


class Sanitiser:
    def __init__(self):
        self.n = 0
        self.markers = {}
        self.secrets = set()

    def mask(self, value, sens):
        """value with every part `sens` marks true replaced by a marker."""
        if sens is True:
            self.collect(value)
            if value is None:
                return None
            # Equal values get one marker, so an unchanged sensitive value
            # still compares equal between before and after.
            key = json.dumps(value, sort_keys=True)
            if key not in self.markers:
                self.n += 1
                self.markers[key] = "SENSITIVE-MARKER-%d" % self.n
            return self.markers[key]
        if isinstance(sens, dict) and isinstance(value, dict):
            return {k: self.mask(v, sens.get(k)) for k, v in value.items()}
        if isinstance(sens, list) and isinstance(value, list):
            return [self.mask(v, sens[i] if i < len(sens) else None)
                    for i, v in enumerate(value)]
        return value

    def collect(self, value):
        if isinstance(value, dict):
            for v in value.values():
                self.collect(v)
        elif isinstance(value, list):
            for v in value:
                self.collect(v)
        elif isinstance(value, str) and len(value) >= 6:
            self.secrets.add(value)

    def change(self, ch):
        ch = dict(ch)
        for side in ("before", "after"):
            if side in ch:
                ch[side] = self.mask(ch[side], ch.get(side + "_sensitive"))
        return ch

    def entries(self, items):
        out = []
        for rc in items or []:
            rc = dict(rc)
            if "change" in rc:
                rc["change"] = self.change(rc["change"])
            out.append(rc)
        return out


def module_sources(mod):
    calls = {}
    for name, call in (mod or {}).get("module_calls", {}).items():
        c = {"source": call.get("source")}
        inner = module_sources(call.get("module"))
        if inner:
            c["module"] = {"module_calls": inner}
        calls[name] = c
    return calls


def find_password(raw):
    def walk(mod):
        for r in (mod or {}).get("resources", []):
            if r.get("address") == PASSWORD_ADDR:
                return r.get("values", {}).get("result")
        for child in (mod or {}).get("child_modules", []):
            found = walk(child)
            if found:
                return found
        return None
    return walk(raw.get("prior_state", {}).get("values", {}).get("root_module"))


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8") as f:
        raw = json.load(f)
    s = Sanitiser()
    out = {k: raw[k] for k in KEEP if k in raw}
    out["resource_changes"] = s.entries(raw.get("resource_changes"))
    if "resource_drift" in raw:
        out["resource_drift"] = s.entries(raw["resource_drift"])
    if "output_changes" in raw:
        out["output_changes"] = {k: s.change(v) for k, v in raw["output_changes"].items()}
    out["configuration"] = {"root_module": {"module_calls": module_sources(
        raw.get("configuration", {}).get("root_module"))}}
    text = json.dumps(out, indent=1, sort_keys=True) + "\n"

    password = find_password(raw)
    if not password:
        sys.exit("sanitize_plan: no %s result in the raw plan's prior state: "
                 "can't check the fixture for it" % PASSWORD_ADDR)
    if password in text:
        sys.exit("sanitize_plan: the database password is still in the output")
    leaked = [x for x in s.secrets if x in text]
    if leaked:
        sys.exit("sanitize_plan: %d sensitive value(s) still in the output" % len(leaked))
    with open(dst, "w", encoding="utf-8") as f:
        f.write(text)
    print("sanitize_plan: wrote %s (%d marker(s); database password absent: "
          "checked, length %d)" % (dst, s.n, len(password)))


if __name__ == "__main__":
    main()
