"""Tests for .github/workflows/readme-check.yml: its triggers and settings, and its label gate run as written.

Run from the repository root:  python3 -I -m unittest scripts/readme/test_workflow.py
Standard library only (no YAML parser): the workflow is read as text, and the gate step's shell is run with bash
under each label event, with a stub in place of the builder.
"""
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[2] / ".github" / "workflows" / "readme-check.yml"


def steps(text):
    body = text.split("\n    steps:\n", 1)[1]
    return re.split(r"\n      - ", "\n" + body)[1:]


def gate_env(text, event):
    """The first step's env, with each ${{ github.event.<path> }} evaluated against a webhook event fixture."""
    first = steps(text)[0]
    m = re.search(r"\n        env:\n((?:          .*\n)+)", "\n" + first)
    env = {}
    for line in m.group(1).rstrip("\n").split("\n"):
        name, value = line.strip().split(": ", 1)
        e = re.fullmatch(r"\$\{\{ github\.event\.([a-z_.]+) \}\}", value)
        if not e:
            raise AssertionError(f"the gate's env {name} uses an expression this test cannot evaluate: {value}")
        v = event
        for key in e.group(1).split("."):
            v = v.get(key, "") if isinstance(v, dict) else ""
        env[name] = v if isinstance(v, str) else ""
    return env


def labelled(added, labels):
    return {"action": "labeled", "label": {"name": added}, "pull_request": {"labels": [{"name": n} for n in labels]}}


def gate_script(text):
    first = steps(text)[0]
    m = re.search(r"run: \|\n((?:          .*\n?)+)", first)
    return "\n".join(line[10:] for line in m.group(1).rstrip("\n").split("\n"))


class Workflow(unittest.TestCase):
    def setUp(self):
        self.text = WORKFLOW.read_text()

    def test_triggers_only_on_labelled_pull_requests(self):
        on = self.text.split("\non:\n", 1)[1].split("\n\n", 1)[0]
        self.assertEqual(on.strip(), "pull_request:\n    types: [labeled]")
        for word in ("push:", "synchronize", "pull_request_target", "workflow_dispatch", "schedule:"):
            self.assertNotIn(word, self.text)

    def test_job_settings(self):
        self.assertIn("\npermissions:\n  contents: read\n", self.text)
        self.assertNotIn("write", self.text.split("\njobs:\n")[0])
        self.assertIn("cancel-in-progress: true", self.text)
        self.assertIn("    runs-on: ubuntu-latest\n    timeout-minutes: 5\n", self.text)
        job = self.text.split("\njobs:\n", 1)[1].split("\n    steps:\n", 1)[0]
        self.assertNotRegex(job, r"\n    if:", "a job-level if: makes a skipped required job count as passed")
        self.assertNotIn("secrets.", self.text)

    def test_no_step_can_be_skipped_or_fail_quietly(self):
        for s in steps(self.text):
            self.assertNotRegex(s, r"(^|\n)        if:|^if:", "a step-level if: could skip the gate")
            self.assertNotIn("continue-on-error", s)

    def test_steps_in_order(self):
        s = steps(self.text)
        self.assertEqual(len(s), 3)
        self.assertIn("ADDED: ${{ github.event.label.name }}", s[0])
        self.assertRegex(s[1], r"^uses: actions/checkout@[0-9a-f]{40} ")
        self.assertIn("persist-credentials: false", s[1])
        self.assertIn("run: python3 -I scripts/readme/build.py --check", s[2])

    def gate(self, event):
        with tempfile.TemporaryDirectory() as d:
            marker = Path(d) / "builder-ran"
            script = gate_script(self.text) + f"\ntouch {marker}\n"   # stands in for the steps after the gate
            r = subprocess.run(["bash", "-e", "-c", script], env={**os.environ, **gate_env(self.text, event)},
                               capture_output=True, text=True)
            return r.returncode, marker.exists(), r.stdout

    def test_gate_passes_only_when_ready_is_the_label_added(self):
        self.assertEqual(self.gate(labelled("ready", ["ready"]))[:2], (0, True))
        self.assertEqual(self.gate(labelled("ready", ["documentation", "ready"]))[:2], (0, True))
        refused = {
            "another label on a pull request already labelled ready": labelled("documentation", ["ready", "documentation"]),
            "another label alone": labelled("documentation", ["documentation"]),
            "no label name": labelled("", []),
            "a near miss": labelled("Ready", ["Ready"]),
            "trailing space": labelled("ready ", ["ready "]),
        }
        for why, event in refused.items():
            with self.subTest(why):
                rc, ran, out = self.gate(event)
                self.assertEqual((rc, ran), (1, False), out)
                self.assertIn("::error::", out)


if __name__ == "__main__":
    unittest.main()
