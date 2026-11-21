"""Tests for smelt_tf.py: the three-line edit and the after-rebase diff check.

    python3 -I -m unittest discover -s smelt-deployer/tests -v
"""

import difflib
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import smelt_tf  # noqa: E402

FIX = os.path.join(HERE, "fixtures")
SCRIPT = os.path.join(os.path.dirname(HERE), "smelt_tf.py")
NEW = "0123456789ab"
OLD = "59360208c47e"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def changed_lines(before, after):
    """(removed, added) lines between two texts."""
    rem, add = [], []
    for line in difflib.ndiff(before.splitlines(), after.splitlines()):
        if line.startswith("- "):
            rem.append(line[2:])
        elif line.startswith("+ "):
            add.append(line[2:])
    return rem, add


class SetTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)

    def copy(self, name, text=None):
        path = os.path.join(self.tmp, "smelt.tf")
        if text is None:
            shutil.copy(os.path.join(FIX, name), path)
        else:
            with open(path, "w", encoding="utf-8") as f:
                f.write(text)
        return path

    def assert_three_lines_set(self, fixture, old_ref):
        path = self.copy(fixture)
        before = read(path)
        smelt_tf.set_sha(path, NEW)
        after = read(path)
        rem, add = changed_lines(before, after)
        self.assertEqual(len(rem), 3, rem)
        self.assertEqual(add, [
            '  source = "git::https://github.com/cconstantine/smelt.git//terraform/smelt?ref=%s"' % NEW,
            '  image         = "ghcr.io/cconstantine/smelt:%s"' % NEW,
            '  sandbox_image = "ghcr.io/cconstantine/smelt-sandbox:%s"' % NEW,
        ])
        self.assertIn("?ref=%s\"" % old_ref, rem[0])
        self.assertEqual(len(before.splitlines()), len(after.splitlines()))

    def test_set_rewrites_exactly_three_lines_of_todays_ref_main_shape(self):
        self.assert_three_lines_set("smelt.tf.ref-main", "main")

    def test_set_rewrites_exactly_three_lines_of_sme663s_ref_sha_shape(self):
        self.assert_three_lines_set("smelt.tf.ref-sha", OLD)

    def test_set_twice_says_already_at_and_leaves_the_file_alone(self):
        path = self.copy("smelt.tf.ref-sha")
        smelt_tf.set_sha(path, NEW)
        once = read(path)
        with self.assertRaises(smelt_tf.AlreadyAt):
            smelt_tf.set_sha(path, NEW)
        self.assertEqual(read(path), once)

    def test_a_missing_line_fails_and_leaves_the_file_unchanged(self):
        text = read(os.path.join(FIX, "smelt.tf.ref-sha"))
        text = "\n".join(l for l in text.splitlines() if "sandbox_image" not in l) + "\n"
        path = self.copy(None, text)
        with self.assertRaisesRegex(smelt_tf.EditError, "sandbox_image.*0"):
            smelt_tf.set_sha(path, NEW)
        self.assertEqual(read(path), text)

    def test_a_doubled_line_fails_and_leaves_the_file_unchanged(self):
        text = read(os.path.join(FIX, "smelt.tf.ref-main"))
        line = [l for l in text.splitlines() if l.strip().startswith("image ")][0]
        text = text.replace(line, line + "\n" + line)
        path = self.copy(None, text)
        with self.assertRaisesRegex(smelt_tf.EditError, "image.*2"):
            smelt_tf.set_sha(path, NEW)
        self.assertEqual(read(path), text)

    def test_a_sha_that_isnt_12_hex_characters_is_refused(self):
        path = self.copy("smelt.tf.ref-sha")
        before = read(path)
        for bad in ("0123456789a", "0123456789abc", "0123456789AB", "main"):
            with self.assertRaises(smelt_tf.EditError):
                smelt_tf.set_sha(path, bad)
        self.assertEqual(read(path), before)

    def test_the_cli_exit_codes(self):
        path = self.copy("smelt.tf.ref-main")
        run = lambda: subprocess.run([sys.executable, "-I", SCRIPT, "set", NEW, "--file", path],
                                     capture_output=True, text=True)
        first = run()
        self.assertEqual(first.returncode, 0, first.stderr)
        second = run()
        self.assertEqual(second.returncode, 3)
        self.assertIn("already at %s" % NEW, second.stdout + second.stderr)


GOOD_DIFF = """\
diff --git a/smelt.tf b/smelt.tf
index 1111111..2222222 100644
--- a/smelt.tf
+++ b/smelt.tf
@@ -17 +17 @@
-  source = "git::https://github.com/cconstantine/smelt.git//terraform/smelt?ref=59360208c47e"
+  source = "git::https://github.com/cconstantine/smelt.git//terraform/smelt?ref=0123456789ab"
@@ -19,2 +19,2 @@ module "smelt" {
-  image         = "ghcr.io/cconstantine/smelt:59360208c47e"
-  sandbox_image = "ghcr.io/cconstantine/smelt-sandbox:59360208c47e"
+  image         = "ghcr.io/cconstantine/smelt:0123456789ab"
+  sandbox_image = "ghcr.io/cconstantine/smelt-sandbox:0123456789ab"
"""


class CheckCommitTest(unittest.TestCase):
    def test_accepts_the_three_line_diff(self):
        smelt_tf.check_diff(GOOD_DIFF, NEW)

    def test_accepts_the_saved_real_diff(self):
        smelt_tf.check_diff(read(os.path.join(FIX, "commit-three-lines.diff")), NEW)

    def test_refuses_a_diff_touching_another_line(self):
        bad = GOOD_DIFF + "@@ -26 +26 @@\n-  storage_reader_enabled = true\n+  storage_reader_enabled = false\n"
        with self.assertRaisesRegex(smelt_tf.EditError, "storage_reader_enabled"):
            smelt_tf.check_diff(bad, NEW)

    def test_refuses_the_saved_real_diff_touching_another_line(self):
        with self.assertRaises(smelt_tf.EditError):
            smelt_tf.check_diff(read(os.path.join(FIX, "commit-extra-line.diff")), NEW)

    def test_refuses_a_diff_touching_another_file(self):
        bad = GOOD_DIFF + (
            "diff --git a/monitoring.tf b/monitoring.tf\n--- a/monitoring.tf\n+++ b/monitoring.tf\n"
            "@@ -1 +1 @@\n-a\n+b\n")
        with self.assertRaisesRegex(smelt_tf.EditError, "monitoring.tf"):
            smelt_tf.check_diff(bad, NEW)

    def test_refuses_a_line_set_to_another_sha(self):
        bad = GOOD_DIFF.replace("smelt-sandbox:0123456789ab", "smelt-sandbox:fedcba987654")
        with self.assertRaisesRegex(smelt_tf.EditError, "fedcba987654"):
            smelt_tf.check_diff(bad, NEW)

    def test_refuses_a_line_added_without_its_old_one(self):
        bad = GOOD_DIFF.replace(
            '-  source = "git::https://github.com/cconstantine/smelt.git//terraform/smelt?ref=59360208c47e"\n', "")
        with self.assertRaises(smelt_tf.EditError):
            smelt_tf.check_diff(bad, NEW)

    def test_refuses_an_empty_diff(self):
        with self.assertRaises(smelt_tf.EditError):
            smelt_tf.check_diff("", NEW)


if __name__ == "__main__":
    unittest.main()
