#!/usr/bin/env python3
"""Derive the synthetic-*.json fixtures from the real image-only.json (SME-665).

    python3 -I smelt-deployer/tests/make_synthetic.py

Only for cases Terraform can't produce here: a replace of a prevent_destroy
object (Terraform refuses the plan before any JSON exists), a delete-only, a
forget, deferred changes and an unknown format version. Each is image-only.json
with one thing changed. Kept for the record; the tests never run it.
"""

import copy
import json
import os

FIX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


def load():
    with open(os.path.join(FIX, "image-only.json"), encoding="utf-8") as f:
        return json.load(f)


def entry(plan, address):
    for rc in plan["resource_changes"]:
        if rc["address"] == address:
            return rc
    raise SystemExit("no %s in image-only.json" % address)


def save(name, plan):
    with open(os.path.join(FIX, name), "w", encoding="utf-8") as f:
        f.write(json.dumps(plan, indent=1, sort_keys=True) + "\n")
    print("wrote", name)


def main():
    p = load()
    rc = entry(p, "module.smelt.random_password.database[0]")
    rc["change"]["actions"] = ["delete", "create"]
    rc["action_reason"] = "replace_because_cannot_update"
    rc["change"]["replace_paths"] = [["length"]]
    rc["change"]["after"] = dict(rc["change"]["before"], length=32)
    save("synthetic-guarded-replace.json", p)

    p = load()
    rc = entry(p, "module.smelt.kubernetes_ingress_v1.smelt")
    rc["change"]["actions"] = ["delete"]
    rc["action_reason"] = "delete_because_no_resource_config"
    rc["change"]["after"] = None
    rc["change"]["after_unknown"] = {}
    save("synthetic-delete.json", p)

    p = load()
    rc = entry(p, "module.smelt.kubernetes_service_v1.smelt")
    rc["change"]["actions"] = ["forget"]
    rc["change"]["after"] = None
    save("synthetic-forget.json", p)

    p = load()
    rc = copy.deepcopy(entry(p, "module.smelt.kubernetes_ingress_v1.smelt"))
    rc["change"]["actions"] = ["update"]
    p["deferred_changes"] = [{"reason": "resource_config_unknown", "resource_change": rc}]
    save("synthetic-deferred.json", p)

    p = load()
    p["format_version"] = "2.0"
    save("synthetic-format-2.json", p)


if __name__ == "__main__":
    main()
