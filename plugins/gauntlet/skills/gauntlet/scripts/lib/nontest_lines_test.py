"""Unit tests for nontest_lines.py's moved-line discount (TRA-470): the colour
parser, the pairing rule, the numstat check and each fallback reason."""
import contextlib, io, os, shutil, stat, subprocess, sys, tempfile, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nontest_lines as nl  # noqa: E402

REAL_GIT = shutil.which("git")


def esc(slot):
    return f"\x1b[38;5;{nl.COLOUR[slot]}m"


def line(slot, sign, text):
    # git's form for a changed line under --ws-error-highlight=none: colour, sign, text, one reset.
    return f"{esc(slot)}{sign}{text}\x1b[m"


def header(path):
    return [f"{esc('meta')}diff --git a/{path} b/{path}\x1b[m", f"{esc('meta')}index 1..2 100644\x1b[m",
            f"{esc('meta')}--- a/{path}\x1b[m", f"{esc('meta')}+++ b/{path}\x1b[m", f"{esc('frag')}@@ -1,3 +1,3 @@\x1b[m"]


def git(repo, *args):
    subprocess.run([REAL_GIT, "-C", repo] + list(args), check=True, capture_output=True)


def block(name, n):
    return "".join(f"const {name}_{i} = compute({i}, \"{name} payload\");\n" for i in range(n))


class Repo:
    """A throwaway repo: a.ts holds a 30-line block at base; at head it is moved to b.ts plus 2 new lines."""

    def __init__(self, tmp):
        self.path = os.path.join(tmp, "repo")
        os.makedirs(self.path)
        git(self.path, "init", "-q", "-b", "main")
        git(self.path, "config", "user.name", "test")
        git(self.path, "config", "user.email", "test@example.invalid")
        self.write("a.ts", block("x", 30) + block("k", 3))
        self.write("b.ts", block("y", 3))
        git(self.path, "add", "-A")
        git(self.path, "commit", "-qm", "base")
        self.write("a.ts", block("k", 3))
        self.write("b.ts", block("y", 3) + block("x", 30) + block("new", 2))
        git(self.path, "add", "-A")
        git(self.path, "commit", "-qm", "move")

    def write(self, name, text):
        with open(os.path.join(self.path, name), "w") as f:
            f.write(text)

    def report(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = nl.main(["nontest_lines.py", self.path, "HEAD~1", "HEAD", "--report", "--base (on main)", "600"])
        return rc, out.getvalue()


class ParserTest(unittest.TestCase):
    def test_moved_is_read_from_the_escape_before_the_sign(self):
        text = "\n".join(header("a.ts") + [
            line("oldMoved", "-", "moved away"),
            line("old", "-", "-- plain removed that looks like a header"),
            line("context", " ", "context"),
            line("new", "+", "plain added"),
            line("newMoved", "+", "moved here"),
            # An escape inside the text stays text: a moved escape there never marks the line moved.
            line("new", "+", f"{esc('newMoved')}inside"),
        ]) + "\n"
        sections = nl.parse(text)
        self.assertEqual([s[0] for s in sections], ["diff --git a/a.ts b/a.ts"])
        self.assertEqual(sections[0][1], [("-", True, "moved away"), ("-", False, "-- plain removed that looks like a header"),
                                          ("+", False, "plain added"), ("+", True, "moved here"),
                                          ("+", False, f"{esc('newMoved')}inside")])

    def test_header_lines_before_the_first_hunk_are_not_counted(self):
        sections = nl.parse("\n".join(header("a.ts")) + "\n")
        self.assertEqual(sections[0][1], [])

    def test_every_moved_slot_counts_as_moved_and_only_moved_slots(self):
        for slot in nl.SLOTS:
            for sign in "+-":
                got = nl.parse("\n".join(header("a.ts") + [line(slot, sign, "t")]))[0][1]
                want = slot.startswith("oldMoved" if sign == "-" else "newMoved")
                self.assertEqual(got, [(sign, want, "t")], (slot, sign))

    def test_header_matching(self):
        self.assertTrue(nl.header_matches("diff --git a/src/x.ts b/src/x.ts", "src/x.ts"))
        self.assertTrue(nl.header_matches("diff --git src/x.ts src/x.ts", "src/x.ts"))
        self.assertTrue(nl.header_matches("diff --git c/x.ts w/x.ts", "x.ts"))
        self.assertFalse(nl.header_matches("diff --git a/x.ts b/y.ts", "x.ts"))
        self.assertFalse(nl.header_matches('diff --git "a/x\\ty" "b/x\\ty"', "x\ty"))


class PairingTest(unittest.TestCase):
    def test_one_removal_per_addition_in_path_order(self):
        sections = [("a", [("-", True, "t"), ("-", True, "u")]),
                    ("b", [("+", True, "t"), ("+", True, "u")]),
                    ("c", [("+", True, "t"), ("+", False, "u")])]
        self.assertEqual(nl.discounts(sections), [2, 2, 0])

    def test_unmarked_copies_earn_nothing(self):
        sections = [("a", [("-", False, "}"), ("-", True, "t")]), ("b", [("+", True, "}"), ("+", False, "t")])]
        self.assertEqual(nl.discounts(sections), [0, 0])

    def test_moves_within_one_file(self):
        self.assertEqual(nl.discounts([("a", [("-", True, "t"), ("+", True, "t"), ("+", True, "t")])]), [2])


class NumstatCheckTest(unittest.TestCase):
    files = [(1, 1, "a.ts"), (2, 0, "b.ts")]

    def sec(self, path, signs):
        return (f"diff --git a/{path} b/{path}", [(s, False, "x") for s in signs])

    def test_agreement(self):
        self.assertIsNone(nl.disagreement(self.files, [self.sec("a.ts", "+-"), self.sec("b.ts", "++")]))

    def test_count_mismatch(self):
        self.assertEqual(nl.disagreement(self.files, [self.sec("a.ts", "+-"), self.sec("b.ts", "+")]), "b.ts")

    def test_missing_and_unmatched_sections(self):
        self.assertEqual(nl.disagreement(self.files, [self.sec("a.ts", "+-")]), "b.ts")
        self.assertEqual(nl.disagreement(self.files, [self.sec("b.ts", "++"), self.sec("a.ts", "+-")]), "a.ts")
        self.assertEqual(nl.disagreement(self.files, [self.sec("a.ts", "+-"), self.sec("b.ts", "++"), self.sec("c.ts", "+")]), "a/c.ts b/c.ts")


class EndToEndTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.repo = Repo(self.tmp)
        self.path_before, self.timeout_before = os.environ["PATH"], nl.MOVED_TIMEOUT

    def tearDown(self):
        os.environ["PATH"], nl.MOVED_TIMEOUT = self.path_before, self.timeout_before
        shutil.rmtree(self.tmp)

    def fake_git(self, body):
        """A git that runs `body` for the coloured diff and real git otherwise."""
        d = os.path.join(self.tmp, "fake")
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, "git")
        with open(p, "w") as f:
            f.write(f'#!/usr/bin/env bash\nif [[ " $* " == *" --color-moved=blocks "* ]]; then\n{body}\nfi\nexec {REAL_GIT} "$@"\n')
        os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC)
        os.environ["PATH"] = d + os.pathsep + self.path_before

    def test_discount(self):
        self.assertEqual(self.repo.report(), (0, "ROUND-1 SIZE: 2 changed non-test lines from --base (on main) (size note above 600; 60 lines moved unchanged not counted)\n"))

    def test_probe_passes_on_this_git(self):
        self.assertTrue(nl.probe(self.repo.path))

    def assert_reason(self, reason):
        self.assertEqual(self.repo.report(), (0, f"ROUND-1 SIZE: 62 changed non-test lines from --base (on main) (size note above 600; moved-line discount not applied: {reason})\n"))

    def test_coloured_diff_failed(self):
        self.fake_git("exit 3")
        self.assert_reason("coloured diff failed")

    def test_coloured_diff_timed_out(self):
        nl.MOVED_TIMEOUT = 1
        self.fake_git("exec sleep 5")
        self.assert_reason("coloured diff timed out")

    def test_line_counts_disagree(self):
        # The last line of the output (b.ts's last added line) goes missing.
        self.fake_git(f'[[ " $* " == *" --no-index "* ]] || {{ {REAL_GIT} "$@" | sed \'$d\'; exit "${{PIPESTATUS[0]}}"; }}')
        self.assert_reason("line counts disagree in b.ts")

    def test_git_move_check_failed(self):
        # The probe's run marks nothing moved.
        self.fake_git(f'[[ " $* " != *" --no-index "* ]] || {{ {REAL_GIT} "${{@/--color-moved=blocks/--color-moved=no}}"; exit $?; }}')
        self.assert_reason("git move check failed on this machine")

    def test_raw_count_without_report(self):
        out = subprocess.run([sys.executable, nl.__file__, self.repo.path, "HEAD~1", "HEAD"], capture_output=True, text=True, check=True).stdout
        self.assertEqual(out, "62\n")

    def test_numstat_ignores_configured_algorithm(self):
        self.repo.write("h.ts", "a\nb\n}\n}\nb\nc\nb\nb\n}\n")
        git(self.repo.path, "add", "-A")
        git(self.repo.path, "commit", "-qm", "h base")
        self.repo.write("h.ts", "a\n}\na\nb\nc\na\n")
        git(self.repo.path, "add", "-A")
        git(self.repo.path, "commit", "-qm", "h head")
        plain = nl.counted(self.repo.path, "HEAD~1", "HEAD")
        git(self.repo.path, "config", "diff.algorithm", "histogram")
        self.assertEqual(nl.counted(self.repo.path, "HEAD~1", "HEAD"), plain)
        self.assertEqual(plain, [(2, 5, "h.ts")])



class LiteralEscapeTest(unittest.TestCase):
    """Escapes in a file's own text are part of the line (pre-review finding, 24 Oct 2026)."""

    def test_parser_keeps_escapes_that_are_part_of_the_text(self):
        text = "\n".join(header("a.ts") + [line("newMoved", "+", "foo \x1b[31mbar\x1b[m baz"), line("oldMoved", "-", "\x1b[32mplain")])
        (_, lines), = nl.parse(text)
        self.assertEqual(lines, [("+", True, "foo \x1b[31mbar\x1b[m baz"), ("-", True, "\x1b[32mplain")])

    def _repo(self, tmp, payloads):
        path = os.path.join(tmp, "esc")
        os.makedirs(path)
        git(path, "init", "-q", "-b", "main")
        git(path, "config", "user.name", "test")
        git(path, "config", "user.email", "test@example.invalid")
        # Each payload's lines cross their own unchanged anchor, so git keeps the
        # anchors as context and marks all six payload lines moved; the red and
        # green copies differ only in a literal escape at the start of the text.
        anchor = lambda n: "".join(f"anchor {n} line {i} stays exactly where it is\n" for i in range(5))
        red = lambda p: f"\x1b[31m{p}\n"
        green = lambda p: f"\x1b[32m{p}\n"
        before = "".join(red(p) + red(p) + green(p) + anchor(n) for n, p in enumerate(payloads))
        after = "".join(anchor(n) + red(p) + green(p) + green(p) for n, p in enumerate(payloads))
        with open(os.path.join(path, "a.ts"), "w") as f:
            f.write(before)
        git(path, "add", "-A")
        git(path, "commit", "-qm", "base")
        with open(os.path.join(path, "a.ts"), "w") as f:
            f.write(after)
        git(path, "commit", "-qam", "move")
        return path

    def _report(self, path):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = nl.main(["nontest_lines.py", path, "HEAD~1", "HEAD", "--report", "--base (on main)", "600"])
        return rc, out.getvalue()

    def test_lines_differing_only_in_literal_escapes_pair_by_exact_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._repo(tmp, ["payload text long enough for git to call it a moved block"])
            files = nl.counted(path, "HEAD~1", "HEAD")
            out = subprocess.run(nl.moved_command(path) + ["HEAD~1", "HEAD", "--"] + [f for _, _, f in files], capture_output=True, check=True).stdout.decode()
            self.assertEqual(sum(nl.discounts(nl.parse(out))), 4)

    def test_escape_variants_cannot_hide_602_counted_lines(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = self._repo(tmp, [f"payload number {i} long enough for git to call it a moved block" for i in range(301)])
            rc, out = self._report(path)
            self.assertEqual(rc, 0, out)  # size is a note, never a refusal (12 Nov 2026)
            self.assertIn("ROUND-1 SIZE: 602 changed non-test lines", out)
            self.assertIn("SIZE NOTE: over 600", out)

class DocumentationTest(unittest.TestCase):
    """TRA-1033: Markdown never counts; code in a docs folder does; code moved into a document is not discounted."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "repo")
        os.makedirs(os.path.join(self.path, "docs"))
        git(self.path, "init", "-q", "-b", "main")
        git(self.path, "config", "user.name", "test")
        git(self.path, "config", "user.email", "test@example.invalid")
        self.write("a.ts", block("x", 30))
        self.commit("base")

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def write(self, name, text):
        with open(os.path.join(self.path, name), "w") as f:
            f.write(text)

    def commit(self, msg):
        git(self.path, "add", "-A")
        git(self.path, "commit", "-qm", msg)

    def total(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            nl.main(["nontest_lines.py", self.path, "HEAD~1", "HEAD"])
        return int(out.getvalue())

    def test_markdown_does_not_count_and_docs_code_does(self):
        self.write("a.ts", block("x", 30) + block("fix", 3))
        self.write("CHANGELOG.md", block("note", 200))
        self.write("docs/evidence.MARKDOWN", block("ev", 100))
        self.write("docs/util.ts", block("util", 40))
        self.commit("fix with docs")
        self.assertEqual(sorted(p for _, _, p in nl.counted(self.path, "HEAD~1", "HEAD")), ["a.ts", "docs/util.ts"])
        self.assertEqual(self.total(), 43)

    def test_agent_instruction_markdown_still_counts(self):
        names = ["CLAUDE.md", "AGENTS.md", "docs/Agents.md", "AGENT.md", "docs/Claude.md", "CLAUDE.local.md", "GEMINI.md",
                 "docs/SKILL.md", "docs/sub/CLAUDE.md", ".claude/commands/go.md", ".agents/rules.md", ".codex/x.md",
                 ".cursor/rules/r.md", ".grok/rules/r.md", ".github/copilot-instructions.md", "docs/.claude/x.md"]
        for name in names:
            os.makedirs(os.path.dirname(os.path.join(self.path, name)) or self.path, exist_ok=True)
            self.write(name, block("rule", 10))
        self.write("README.md", block("doc", 50))
        self.commit("agent instructions and a readme")
        self.assertEqual(sorted(p for _, _, p in nl.counted(self.path, "HEAD~1", "HEAD")), sorted(names))
        self.assertEqual(self.total(), 160)

    def test_code_moved_out_of_a_document_is_counted(self):
        self.write("docs/archive.md", block("y", 30))
        self.commit("document holds code")
        self.write("docs/archive.md", "")
        self.write("a.ts", block("x", 30) + block("y", 30))
        self.commit("move code out of the document")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            nl.main(["nontest_lines.py", self.path, "HEAD~1", "HEAD", "--report", "--base (on main)", "600"])
        self.assertTrue(out.getvalue().startswith("ROUND-1 SIZE: 30 changed non-test lines"), out.getvalue())

    def test_only_root_and_docs_folder_markdown_is_documentation(self):
        docs = ["README.md", "docs/a.md", "docs/changelog.d/x.md", "web/doc/b.markdown", "status/evidence/run/README.md",
                "pkg/changelog/2.md", "Documentation/c.md"]
        counted = ["claude/agents/worker.md", "claude/commands/go.md", "claude/skills/x/references/contract.md",
                   "server/prompts/p.md", "research/report.md"]
        for name in docs + counted:
            os.makedirs(os.path.dirname(os.path.join(self.path, name)) or self.path, exist_ok=True)
            self.write(name, block("t", 5))
        self.commit("markdown in many places")
        self.assertEqual(sorted(p for _, _, p in nl.counted(self.path, "HEAD~1", "HEAD")), sorted(counted))

    def test_code_moved_into_a_document_is_counted(self):
        self.write("a.ts", "")
        self.write("docs/archive.md", block("x", 30))
        self.commit("move code into a document")
        rc, out = None, io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = nl.main(["nontest_lines.py", self.path, "HEAD~1", "HEAD", "--report", "--base (on main)", "600"])
        self.assertEqual(rc, 0)
        self.assertTrue(out.getvalue().startswith("ROUND-1 SIZE: 30 changed non-test lines"), out.getvalue())


if __name__ == "__main__":
    unittest.main()
