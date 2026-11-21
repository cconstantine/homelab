"""Tests for plan_summary.py against real, sanitised `terraform show -json` plans.

    python3 -I -m unittest discover -s smelt-deployer/tests -v

The fixtures come from make_fixtures.sh (a k3d run of a homelab-shaped root,
planned with -target=module.smelt: module-changed after an apply at A, the
rest after one at C); synthetic-*.json from make_synthetic.py, only for what
Terraform can't produce.
"""

import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
SCRIPT = os.path.join(os.path.dirname(HERE), "plan_summary.py")

A = "bad6724593f4"    # applied first; module-changed's base
C = "8494afbafc47"    # module changed from A (SME-335's LimitRange defaults); applied second
D = "934ba4dbb2b4"    # image-only from C: its module changes alter nothing in the root
DEPLOY = "module.smelt.kubernetes_deployment_v1.smelt"
IMAGE_PATHS = (
    "spec[0].template[0].spec[0].container[name=smelt].image",
    "spec[0].template[0].spec[0].container[name=smelt].env[name=SANDBOX_IMAGE].value",
)
SHA_OF = {
    "image-only.json": D, "module-changed.json": C, "replace-in-module.json": C,
    "out-of-module.json": C, "no-changes.json": C,
}


def fixture(name):
    return os.path.join(FIX, name)


def run(path, sha, *extra):
    return subprocess.run([sys.executable, "-I", SCRIPT, path, "--sha", sha, *extra],
                          capture_output=True, text=True)


def summary(name, sha=None):
    """(json summary, text output) for a fixture; both runs must exit 0."""
    sha = sha or SHA_OF.get(name, D)
    j = run(fixture(name), sha, "--json")
    t = run(fixture(name), sha)
    assert j.returncode == 0, j.stderr
    assert t.returncode == 0, t.stderr
    return json.loads(j.stdout), t.stdout


def changed_addresses(name):
    with open(fixture(name), encoding="utf-8") as f:
        plan = json.load(f)
    return sorted(rc["address"] for rc in plan["resource_changes"]
                  if rc["change"]["actions"] != ["no-op"])


def stop_flags(s, *kinds):
    return [f for f in s["flags"] if f.split()[0] in kinds]


class RealPlansTest(unittest.TestCase):
    def test_image_only_is_image_only_with_no_flags_and_both_new_images_shown(self):
        s, text = summary("image-only.json")
        self.assertEqual(s["kind"], "image-only")
        self.assertEqual(s["flags"], [])
        self.assertIn("ghcr.io/cconstantine/smelt:%s" % D, text)
        self.assertIn("ghcr.io/cconstantine/smelt-sandbox:%s" % D, text)
        self.assertIn("KIND: image-only", text)
        [ch] = s["changes"]
        self.assertEqual(ch["address"], DEPLOY)
        self.assertEqual(ch["actions"], "update")
        self.assertEqual(sorted(ch["paths"]), sorted(IMAGE_PATHS))

    def test_image_only_has_no_known_after_apply_paths(self):
        # The plan's prediction for a kubernetes deployment update: none, so no
        # allowlist is needed (SME-665, the real image-only fixture).
        s, _ = summary("image-only.json")
        self.assertEqual(s["changes"][0]["unknown_paths"], [])

    def edited_image_only(self, edit):
        """(json summary, text) for image-only.json with the deployment's
        change passed through edit(change)."""
        with open(fixture("image-only.json"), encoding="utf-8") as f:
            plan = json.load(f)
        for rc in plan["resource_changes"]:
            if rc["address"] == DEPLOY:
                edit(rc["change"])
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        path = os.path.join(tmp, "p.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump(plan, f)
        j, t = run(path, D, "--json"), run(path, D)
        self.assertEqual((j.returncode, t.returncode), (0, 0), j.stderr + t.stderr)
        return json.loads(j.stdout), t.stdout

    def test_an_unknown_path_on_the_deployment_makes_it_wider(self):
        def edit(ch):
            ch["after_unknown"] = {"metadata": [{"resource_version": True}]}
        s, _ = self.edited_image_only(edit)
        self.assertEqual(s["kind"], "wider")
        self.assertIn("metadata[0].resource_version", s["changes"][0]["unknown_paths"])

    def test_another_changed_path_on_the_deployment_makes_it_wider(self):
        def edit(ch):
            ch["after"]["spec"][0]["replicas"] = "2"
        s, text = self.edited_image_only(edit)
        self.assertEqual(s["kind"], "wider")
        self.assertIn("spec[0].replicas", s["changes"][0]["paths"])
        self.assertIn("KIND: wider", text)

    def test_an_image_path_marked_sensitive_shows_no_value(self):
        def edit(ch):
            spec = ch["after"]["spec"][0]["template"][0]["spec"][0]
            n = len(spec["container"])
            marks = [{} for _ in range(n)]
            marks[[c["name"] for c in spec["container"]].index("smelt")] = {"image": True}
            ch["after_sensitive"] = {"spec": [{"template": [{"spec": [{"container": marks}]}]}]}
        s, text = self.edited_image_only(edit)
        self.assertNotIn(IMAGE_PATHS[0], s["changes"][0]["values"])
        self.assertNotIn("ghcr.io/cconstantine/smelt:%s" % D, text)
        self.assertIn("REF_MISMATCH", " ".join(s["flags"]))

    def test_module_changed_is_wider_lists_every_change_and_no_delete_or_replace(self):
        s, text = summary("module-changed.json")
        self.assertEqual(s["kind"], "wider")
        want = changed_addresses("module-changed.json")
        self.assertGreater(len(want), 0)
        self.assertEqual(sorted(c["address"] for c in s["changes"]), want)
        for addr in want:
            self.assertIn(addr, text)
        self.assertEqual(stop_flags(s, "DELETE", "REPLACE", "OUTSIDE_MODULE", "GUARDED"), [])
        self.assertIn("KIND: wider", text)

    def test_replace_in_module_flags_the_replace(self):
        s, text = summary("replace-in-module.json")
        self.assertIn("REPLACE module.smelt.kubernetes_service_v1.smelt", s["flags"])
        self.assertIn("FLAG: REPLACE module.smelt.kubernetes_service_v1.smelt", text)
        self.assertEqual(s["kind"], "wider")

    def test_a_path_under_a_known_after_apply_path_is_not_listed_twice(self):
        s, _ = summary("replace-in-module.json")
        [svc] = [c for c in s["changes"] if c["address"] == "module.smelt.kubernetes_service_v1.smelt"]
        self.assertIn("spec[0].cluster_ips", svc["unknown_paths"])
        for p in svc["paths"]:
            for u in svc["unknown_paths"]:
                self.assertFalse(p == u or p.startswith(u + ".") or p.startswith(u + "["), (p, u))

    def test_out_of_module_flags_the_monitoring_change(self):
        s, text = summary("out-of-module.json")
        self.assertIn("OUTSIDE_MODULE module.monitoring.kubernetes_config_map_v1.tempo", s["flags"])
        self.assertIn("FLAG: OUTSIDE_MODULE module.monitoring.kubernetes_config_map_v1.tempo", text)
        self.assertEqual(s["kind"], "wider")

    def test_no_changes(self):
        s, text = summary("no-changes.json")
        self.assertEqual(s["kind"], "no-changes")
        self.assertEqual(s["flags"], [])
        self.assertIn("KIND: no-changes", text)

    def test_a_different_sha_is_a_ref_mismatch(self):
        s, text = summary("image-only.json", sha=C)
        self.assertEqual([f.split()[0] for f in s["flags"]], ["REF_MISMATCH"])
        self.assertIn(C, s["flags"][0])
        self.assertIn("FLAG: REF_MISMATCH", text)

    def test_the_header_names_the_module_source(self):
        s, text = summary("image-only.json")
        self.assertIn("?ref=%s" % D, s["header"]["module_source"])
        self.assertIn("?ref=%s" % D, text)

    def test_a_targeted_plans_incompleteness_and_the_drift_are_notes_not_flags(self):
        # Every -target plan says complete=false; the refresh after the first
        # apply shows the provider's null -> {} normalisation as drift (10
        # entries in module-changed.json, none once applied twice).
        s, text = summary("image-only.json")
        self.assertTrue(any(n.startswith("INCOMPLETE") for n in s["notes"]))
        self.assertNotIn("FLAG: INCOMPLETE", text)
        self.assertEqual(s["flags"], [])
        s, text = summary("module-changed.json")
        self.assertTrue(any(n.startswith("DRIFT 10 ") for n in s["notes"]), s["notes"])
        self.assertNotIn("FLAG: DRIFT", text)
        self.assertIn("NOTE: DRIFT", text)


class SyntheticPlansTest(unittest.TestCase):
    def test_a_guarded_object_replaced_is_flagged_guarded_and_replace(self):
        s, text = summary("synthetic-guarded-replace.json")
        self.assertIn("GUARDED module.smelt.random_password.database[0]", s["flags"])
        self.assertIn("REPLACE module.smelt.random_password.database[0]", s["flags"])
        self.assertEqual(s["flags"][0].split()[0], "GUARDED")  # loudest first
        self.assertEqual(s["kind"], "wider")

    def test_delete(self):
        s, _ = summary("synthetic-delete.json")
        self.assertIn("DELETE module.smelt.kubernetes_ingress_v1.smelt", s["flags"])

    def test_forget(self):
        s, _ = summary("synthetic-forget.json")
        self.assertIn("FORGET module.smelt.kubernetes_service_v1.smelt", s["flags"])

    def test_deferred(self):
        s, _ = summary("synthetic-deferred.json")
        self.assertIn("DEFERRED", [f.split()[0] for f in s["flags"]])


class EveryFixtureTest(unittest.TestCase):
    def plans(self):
        names = [os.path.basename(p) for p in sorted(glob.glob(os.path.join(FIX, "*.json")))]
        return [n for n in names if n != "synthetic-format-2.json"]

    def test_every_fixture_exits_0_and_never_prints_a_sensitive_marker(self):
        names = self.plans()
        self.assertGreaterEqual(len(names), 9)
        for name in names:
            with self.subTest(name):
                s, text = summary(name)
                self.assertNotIn("SENSITIVE-MARKER-", text)
                self.assertNotIn("SENSITIVE-MARKER-", json.dumps(s))

    def test_values_are_shown_only_for_the_two_image_paths(self):
        for name in self.plans():
            with self.subTest(name):
                s, text = summary(name)
                for ch in s["changes"]:
                    self.assertLessEqual(set(ch["values"]), set(IMAGE_PATHS), ch["address"])
                for line in text.splitlines():
                    if " -> " in line:
                        self.assertTrue(any(p in line for p in IMAGE_PATHS), line)

    def test_the_fixtures_hold_markers_so_the_marker_check_can_bite(self):
        with open(fixture("module-changed.json"), encoding="utf-8") as f:
            self.assertIn("SENSITIVE-MARKER-", f.read())


class UnreadableTest(unittest.TestCase):
    def assert_one_line_failure(self, out):
        self.assertNotEqual(out.returncode, 0)
        self.assertEqual(out.stdout, "")
        self.assertEqual(len(out.stderr.strip().splitlines()), 1, out.stderr)

    def test_format_2_is_refused_with_a_reason(self):
        out = run(fixture("synthetic-format-2.json"), D)
        self.assert_one_line_failure(out)
        self.assertIn("format", out.stderr)

    def test_truncated_json(self):
        tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, tmp)
        path = os.path.join(tmp, "t.json")
        with open(fixture("image-only.json"), encoding="utf-8") as f:
            text = f.read()
        with open(path, "w", encoding="utf-8") as f:
            f.write(text[: len(text) // 2])
        self.assert_one_line_failure(run(path, D))

    def test_a_missing_file(self):
        self.assert_one_line_failure(run(os.path.join(FIX, "no-such.json"), D))


if __name__ == "__main__":
    unittest.main()
