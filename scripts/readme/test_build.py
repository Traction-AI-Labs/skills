"""Tests for scripts/readme/build.py: each way --check must go red, and green again after the documented fix.

Run from the repository root:  python3 -I -m unittest scripts/readme/test_build.py
Standard library only. Each test works on a throwaway copy of the repository and never touches the real one.
"""
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def tree_digest(root):
    h = hashlib.sha256()
    for p in sorted(root.rglob("*")):
        if p.is_file():
            h.update(p.relative_to(root).as_posix().encode() + b"\0" + p.read_bytes())
    return h.hexdigest()


class BuildCheck(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.root = self.tmp / "repo"
        shutil.copytree(REPO, self.root, ignore=shutil.ignore_patterns(".git", ".worktrees", "__pycache__", "dist"))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def run_build(self, *args):
        r = subprocess.run([sys.executable, "-I", str(self.root / "scripts/readme/build.py"), *args],
                           capture_output=True, text=True, cwd=self.root)
        return r.returncode, r.stdout + r.stderr

    def check(self):
        return self.run_build("--check")

    def assertRed(self, *needles):
        rc, out = self.check()
        self.assertEqual(rc, 1, out)
        for n in needles:
            self.assertIn(n, out)
        return out

    def assertGreen(self):
        rc, out = self.check()
        self.assertEqual(rc, 0, out)

    def edit(self, rel, old, new, count=1):
        p = self.root / rel
        t = p.read_text()
        self.assertIn(old, t, f"{rel}: test setup could not find {old!r}")
        p.write_text(t.replace(old, new, count))

    def bump(self, plugin, old, new, entry=True):
        self.edit(f"plugins/{plugin}/.claude-plugin/plugin.json", f'"version": "{old}"', f'"version": "{new}"')
        if entry:
            self.edit("CHANGELOG.md", "# Changelog\n\n", f"# Changelog\n\n- **{plugin} {new}** (1 January 2030). Test entry.\n")

    # the baseline, and that --check writes nothing

    def test_clean_tree_is_green_and_check_writes_nothing(self):
        before = tree_digest(self.root)
        self.assertGreen()
        self.assertEqual(before, tree_digest(self.root))

    def test_red_check_writes_nothing(self):
        p = self.root / "scripts/readme/cards/reading-page.toml"
        p.write_text(re.sub(r'^tagline = .*$', 'tagline = "Changed for a test."', p.read_text(), count=1, flags=re.M))
        before = tree_digest(self.root)
        self.check()
        self.assertEqual(before, tree_digest(self.root))

    # rule 1: generated regions

    def test_tagline_change_makes_regions_stale_until_built(self):
        p = self.root / "scripts/readme/cards/reading-page.toml"
        p.write_text(re.sub(r'^tagline = .*$', 'tagline = "Builds one page, for a test."', p.read_text(), count=1, flags=re.M))
        self.assertRed("cards:pages", "plugins:list")
        self.assertEqual(self.run_build()[0], 0)
        self.assertGreen()

    def test_version_bump_without_build_is_red(self):
        self.bump("go-deeper", "0.1.0", "0.1.1")
        self.assertRed("plugins:list is stale", "cards:writing is stale", "changes:latest is stale", "marketplace.json differs")
        self.run_build()
        self.assertGreen()

    def test_duplicate_region_is_red_and_its_body_is_leak_scanned(self):
        self.edit("README.md", "## Install\n", "<!-- install:others:start -->\n/home/someone/private\n<!-- install:others:end -->\n\n## Install\n")
        self.assertRed("install:others must appear exactly once", "holds a home-directory path")

    def test_missing_region_is_red(self):
        self.edit("README.md", "<!-- changes:latest:start -->", "")
        self.assertRed("changes:latest")

    # rule 2: marketplace.json

    def test_hand_edited_marketplace_description_is_red(self):
        m = json.loads((self.root / ".claude-plugin/marketplace.json").read_text())
        self.edit(".claude-plugin/marketplace.json", m["plugins"][0]["description"], "Hand-edited.")
        self.assertRed("marketplace.json")
        self.run_build()
        self.assertGreen()

    def test_marketplace_shape_is_pinned(self):
        p = self.root / ".claude-plugin/marketplace.json"
        m = json.loads(p.read_text())
        m["plugins"][0]["extra"] = 1
        m["plugins"][1]["source"] = "./elsewhere"
        m["name"] = "other"
        p.write_text(json.dumps(m, indent=2) + "\n")
        self.assertRed("exactly name, source, description, version", "source must be ./plugins/doc-gauntlet",
                       'name must stay "traction"')

    def test_duplicate_marketplace_entry_is_red_and_build_removes_it(self):
        p = self.root / ".claude-plugin/marketplace.json"
        m = json.loads(p.read_text())
        m["plugins"].append(dict(m["plugins"][0]))
        p.write_text(json.dumps(m, indent=2) + "\n")
        self.assertRed("is listed 2 times")
        self.assertEqual(self.run_build()[0], 0)
        self.assertGreen()

    def test_malformed_marketplace_is_a_diagnostic(self):
        p = self.root / ".claude-plugin/marketplace.json"
        m = json.loads(p.read_text())
        m["plugins"] = None
        p.write_text(json.dumps(m))
        out = self.assertRed("plugins must be a list of objects")
        self.assertNotIn("Traceback", out)
        p.write_text("{not json")
        out = self.assertRed("marketplace.json: not valid JSON")
        self.assertNotIn("Traceback", out)

    # rule 3: version against the picture

    def test_version_bump_needs_a_picture_check_then_accept_clears_it(self):
        self.bump("ruling-page", "0.3.1", "0.3.2")
        self.run_build()
        self.assertRed("ruling-page picture checked at 0.3.1, plugin at 0.3.2")
        rc, out = self.run_build("--accept", "ruling-page", "--reason", "The bump changed no pixel.")
        self.assertEqual(rc, 0, out)
        self.assertGreen()
        e = json.loads((self.root / "docs/media/manifest.json").read_text())["ruling-page"]
        self.assertEqual((e["checked_at_version"], e["reason"]), ("0.3.2", "The bump changed no pixel."))

    def test_accept_needs_a_reason(self):
        rc, out = self.run_build("--accept", "ruling-page")
        self.assertNotEqual(rc, 0)
        self.assertIn("--reason", out)

    # rule 4: fingerprints

    def test_template_change_is_red_until_accepted(self):
        self.edit("plugins/ruling-page/skills/ruling-page/references/template.html", "<style>", "<style>\n.test{color:red}")
        self.assertRed("input plugins/ruling-page/skills/ruling-page/references/template.html changed")
        self.run_build("--accept", "ruling-page", "--reason", "A rule the cards do not use.")
        self.assertGreen()

    def test_banner_page_change_is_red_until_accepted(self):
        self.edit("docs/media/banner/banner.html", "<title>", "<title>Test ")
        self.assertRed("banner: input docs/media/banner/banner.html changed")
        self.run_build("--accept", "banner", "--reason", "The title is not drawn.")
        self.assertGreen()

    def test_changed_picture_byte_is_red_and_accept_does_not_clear_it(self):
        p = self.root / "docs/media/ruling-page/light.webp"
        b = bytearray(p.read_bytes())
        b[-1] ^= 1
        p.write_bytes(bytes(b))
        self.assertRed("picture docs/media/ruling-page/light.webp no longer matches its fingerprint")
        self.run_build("--accept", "ruling-page", "--reason", "Trying to accept a changed picture.")
        self.assertRed("no longer matches its fingerprint")

    def test_missing_picture_is_red(self):
        (self.root / "docs/media/ruling-page/light.webp").unlink()
        self.assertRed("docs/media/ruling-page/light.webp")
        (self.root / "docs/media/banner.webp").unlink()
        self.assertRed("picture docs/media/banner.webp is missing")

    def test_malformed_manifest_is_a_diagnostic(self):
        p = self.root / "docs/media/manifest.json"
        m = json.loads(p.read_text())
        m["ruling-page"]["inputs"] = None
        p.write_text(json.dumps(m))
        out = self.assertRed("docs/media/manifest.json: each entry needs inputs and outputs")
        self.assertNotIn("Traceback", out)

    def test_wrong_field_types_are_diagnostics(self):
        cases = [
            ("scripts/readme/cards/gauntlet.toml", r'^alt = .*$', "alt = 42", "[visual] alt must be text"),
            ("scripts/readme/cards/call-prep.toml", r'^tagline = .*$', "tagline = 7", "tagline must be text"),
        ]
        for rel, rx, new, needle in cases:
            with self.subTest(rel=rel):
                p = self.root / rel
                old = p.read_text()
                p.write_text(re.sub(rx, new, old, count=1, flags=re.M))
                try:
                    out = self.assertRed(needle)
                    self.assertNotIn("Traceback", out)
                finally:
                    p.write_text(old)
        p = self.root / ".claude-plugin/marketplace.json"
        m = json.loads(p.read_text())
        m["plugins"][0]["name"] = []
        p.write_text(json.dumps(m, indent=2))
        out = self.assertRed("needs string name, source, description and version")
        self.assertNotIn("Traceback", out)
        p = self.root / "docs/media/manifest.json"
        m = json.loads(p.read_text())
        m["ruling-page"]["checked_at_version"] = 42
        p.write_text(json.dumps(m))
        out = self.assertRed("docs/media/manifest.json: each entry needs")
        self.assertNotIn("Traceback", out)

    # recording: never loses history

    def test_record_against_a_malformed_manifest_changes_nothing(self):
        p = self.root / "docs/media/manifest.json"
        m = json.loads(p.read_text())
        m["ruling-page"]["inputs"] = None
        p.write_text(json.dumps(m))
        before = p.read_bytes()
        rc, out = self.run_build("--accept", "banner", "--reason", "Should not be recorded.")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("Nothing was recorded", out)
        self.assertEqual(before, p.read_bytes())

    def test_a_second_writer_is_refused_while_the_manifest_is_locked(self):
        import fcntl
        p = self.root / "docs/media/manifest.json"
        before = p.read_bytes()
        with open(p.with_name(".manifest.lock"), "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)  # another writer holds the manifest
            rc, out = self.run_build("--accept", "banner", "--reason", "Second writer.")
        self.assertNotEqual(rc, 0, out)
        self.assertIn("another render or accept is recording", out)
        self.assertEqual(before, p.read_bytes())
        rc, out = self.run_build("--accept", "banner", "--reason", "Second writer, after the first.")
        self.assertEqual(rc, 0, out)

    def test_invalid_recorded_version_names_the_file_and_the_fix(self):
        p = self.root / "docs/media/manifest.json"
        m = json.loads(p.read_text())
        m["ruling-page"]["checked_at_version"] = "bad"
        p.write_text(json.dumps(m))
        out = self.assertRed("docs/media/manifest.json", "checked_at_version of the form x.y.z", "Fix: git checkout")
        self.assertNotIn("Traceback", out)

    # rule 5: cards

    def test_plugin_without_a_card_is_red(self):
        d = self.root / "plugins/new-thing/.claude-plugin"
        d.mkdir(parents=True)
        (d / "plugin.json").write_text('{"name": "new-thing", "version": "0.1.0", "description": "x"}\n')
        self.assertRed("plugins/new-thing: no card (scripts/readme/cards/new-thing.toml)")

    def test_card_missing_a_field_is_red(self):
        p = self.root / "scripts/readme/cards/call-prep.toml"
        p.write_text(re.sub(r"^gets = .*\n", "", p.read_text(), flags=re.M))
        self.assertRed("scripts/readme/cards/call-prep.toml: the card lacks 'gets'")

    def test_text_example_must_be_labelled_made_up(self):
        self.edit("scripts/readme/cards/go-deeper.toml", 'label = "Made-up example. ', 'label = "')
        self.assertRed("label must start")

    def test_picture_alt_must_say_what_it_shows(self):
        p = self.root / "scripts/readme/cards/gauntlet.toml"
        p.write_text(re.sub(r'^alt = .*$', 'alt = "round.gif"', p.read_text(), flags=re.M))
        self.assertRed("[visual] alt must say what the picture shows")

    # rule 6: changelog

    def test_version_with_no_changelog_entry_is_red(self):
        self.bump("go-deeper", "0.1.0", "0.1.1", entry=False)
        self.run_build()
        self.assertRed("no entry head names go-deeper 0.1.1")

    # rule 7: leaks

    def test_home_path_in_an_example_is_red(self):
        with open(self.root / "docs/examples/gauntlet/session.txt", "a") as f:
            f.write("see /Users/someone/notes\n")
        self.assertRed("docs/examples/gauntlet/session.txt: holds a home-directory path")

    def test_token_shape_in_a_card_is_red(self):
        self.edit("scripts/readme/cards/gauntlet.toml", 'try = "Run a gauntlet on this branch."',
                  'try = "Run a gauntlet with sk-abcdefghijklmnopqrstu."')
        self.assertRed("scripts/readme/cards/gauntlet.toml: holds an API key shape")


if __name__ == "__main__":
    unittest.main()
