"""Changed non-test lines (added plus removed) between two commits, the O6 measure.

Tests, snapshots, lockfiles, generated files (including linguist-generated) and
documentation (TRA-1033, 12 Nov 2026) do not count. Documentation is a Markdown
file (*.md, *.markdown) at the repository root or under a docs, doc,
documentation, changelog, changelog.d or evidence folder at any depth. Everything
else counts: code or configuration in those folders, Markdown elsewhere (skill
references, agent and command definitions, prompts), and Markdown that instructs
agents anywhere (AGENTS.md, CLAUDE.md and the runner's other instruction names,
GEMINI.md, SKILL.md, and anything under .claude/, .agents/, .codex/, .cursor/,
.grok/ or .github/). A caller that applies its own rule sets DOC to a pattern that
never matches (a repository's own merge lock does). Documentation leaves
before moved-line pairing, so code moved into or out of a document is counted. Usage: nontest_lines.py REPO FROM TO [--report LABEL LIMIT]
Without --report prints the total (the raw count, which the pre-review coverage
check reads). With it prints the ROUND-1 SIZE line and, over the threshold,
per-file counts and the SIZE NOTE line, exiting 0 either way: size is a note,
never a refusal. A non-zero exit means only that counting failed. The report does not count
lines git shows were moved unchanged, within a file or between counted files
(TRA-470), when its three checks pass; otherwise it counts every line.
"""
import collections, os, re, subprocess, sys, tempfile

TEST = re.compile(r'(^|/)(tests?|__tests__|spec|specs|__snapshots__|fixtures|__fixtures__|testdata)/|(\.|_)(test|spec)\.[^/]+$|(^|/)test_[^/]+\.py$|\.snap$')
LOCK = re.compile(r'(^|/)(package-lock\.json|npm-shrinkwrap\.json|yarn\.lock|pnpm-lock\.yaml|bun\.lockb?|Cargo\.lock|poetry\.lock|uv\.lock|Pipfile\.lock|Gemfile\.lock|composer\.lock|go\.sum|flake\.lock)$')
DOC = re.compile(r'^(?:[^/]+|(?:.*/)?(?:docs?|documentation|changelog|changelog\.d|evidence)/.+)\.(?:md|markdown)$', re.I)
AGENT_MD = re.compile(r'(^|/)(AGENTS?|Agents|CLAUDE|Claude|CLAUDE\.local|GEMINI|SKILL)\.md$|(^|/)\.(claude|agents|codex|cursor|grok|github)/', re.I)
GEN = re.compile(r'\.min\.(js|css)$|\.generated\.[^/]+$|(^|/)(dist|generated|__generated__)/|\.pb\.go$|_pb2\.py$')

# Pinned so both counts follow one diff whatever diff.algorithm or
# diff.indentHeuristic the repo or user sets.
ALGORITHM = ["--diff-algorithm=myers", "--indent-heuristic"]
MOVED_TIMEOUT = 30

# Every color.diff slot gets its own 256-colour value, so the escape git writes
# before a line's + or - names the slot, whatever colours are configured.
SLOTS = ["context", "meta", "frag", "func", "old", "new", "commit", "whitespace",
         "oldMoved", "newMoved", "oldMovedDimmed", "oldMovedAlternative", "oldMovedAlternativeDimmed",
         "newMovedDimmed", "newMovedAlternative", "newMovedAlternativeDimmed",
         "contextDimmed", "oldDimmed", "newDimmed", "contextBold", "oldBold", "newBold"]
COLOUR = {slot: 160 + i for i, slot in enumerate(SLOTS)}
MOVED = {"-": {f"\x1b[38;5;{COLOUR[s]}m" for s in SLOTS if s.startswith("oldMoved")},
         "+": {f"\x1b[38;5;{COLOUR[s]}m" for s in SLOTS if s.startswith("newMoved")}}
SGR = re.compile(r'\x1b\[[0-9;]*m')
LEAD = re.compile(r'(?:\x1b\[[0-9;]*m)*')
RESET = "\x1b[m"


def moved_command(repo):
    """The coloured diff, every option that affects it on the command line."""
    cmd = ["git", "-C", repo, "--literal-pathspecs", "-c", "core.quotePath=false"]
    for slot in SLOTS:
        cmd += ["-c", f"color.diff.{slot}={COLOUR[slot]}"]
    return cmd + ["diff", "--no-renames", "--no-ext-diff", "--no-textconv"] + ALGORITHM + \
        ["--color=always", "--color-moved=blocks", "--color-moved-ws=no", "--ws-error-highlight=none"]


def counted(repo, base, head):
    """(added, removed, path) for every counted file, in numstat (path) order."""
    raw = subprocess.run(["git", "-C", repo, "diff", "--numstat", "-z", "--no-renames"] + ALGORITHM + [base, head], capture_output=True, check=True).stdout.decode(errors="replace")
    rows = [r for r in raw.split("\0") if r]
    paths = [r.split("\t", 2)[2] for r in rows]
    generated = set()
    if paths:
        attrs = subprocess.run(["git", "-C", repo, "check-attr", "-z", "linguist-generated", "--"] + paths, capture_output=True).stdout.decode(errors="replace").split("\0")
        for i in range(0, len(attrs) - 2, 3):
            if attrs[i + 2] in ("set", "true"):
                generated.add(attrs[i])
    out = []
    for r in rows:
        added, removed, path = r.split("\t", 2)
        if TEST.search(path) or LOCK.search(path) or GEN.search(path) or (DOC.search(path) and not AGENT_MD.search(path)) or path in generated or added == "-":
            continue
        if int(added) + int(removed):
            out.append((int(added), int(removed), path))
    return out


def parse(text):
    """Coloured diff to [(header, [(sign, moved, line text), ...]), ...] per file.

    A line is moved when the escape git wrote before its + or - is one of the
    moved colours set above; nothing inside the line decides it. With
    --ws-error-highlight=none git writes each changed line as its colour, the
    sign, the line exactly as in the file and one reset, so only that reset is
    removed: escapes that are part of the file's own text stay in the text."""
    sections, lines, in_hunk = [], None, False
    for line in text.split("\n"):
        bare = SGR.sub("", line)
        if bare.startswith("diff --git "):
            lines, in_hunk = [], False
            sections.append((bare, lines))
        elif lines is None:
            continue
        elif bare.startswith("@@"):
            in_hunk = True
        elif in_hunk:
            lead = LEAD.match(line).group(0)
            sign = line[len(lead):len(lead) + 1]
            if sign in MOVED:
                moved = any(code in MOVED[sign] for code in SGR.findall(lead))
                text = line[len(lead) + 1:]
                if text.endswith(RESET):
                    text = text[:-len(RESET)]
                lines.append((sign, moved, text))
    return sections


def header_matches(header, path):
    return re.fullmatch(r'diff --git (?:[a-z]/)?' + re.escape(path) + r' (?:[a-z]/)?' + re.escape(path), header) is not None


def disagreement(files, sections):
    """The first counted file whose coloured-diff counts differ from numstat, or None."""
    for i, (added, removed, path) in enumerate(files):
        if i >= len(sections) or not header_matches(sections[i][0], path):
            return path
        signs = collections.Counter(sign for sign, _, _ in sections[i][1])
        if (signs["+"], signs["-"]) != (added, removed):
            return path
    if len(sections) > len(files):
        return sections[len(files)][0][len("diff --git "):]
    return None


def discounts(sections):
    """Moved lines discounted per section: for each text t, moved(t) is the smaller
    of the removed and added lines git marked moved with text t; that many of
    each are discounted, taken in diff (path) order."""
    marked = {"-": collections.Counter(), "+": collections.Counter()}
    for _, lines in sections:
        for sign, moved, text in lines:
            if moved:
                marked[sign][text] += 1
    left = {sign: {t: min(marked["-"][t], marked["+"][t]) for t in marked[sign]} for sign in marked}
    out = []
    for _, lines in sections:
        k = 0
        for sign, moved, text in lines:
            if moved and left[sign].get(text, 0) > 0:
                left[sign][text] -= 1
                k += 1
        out.append(k)
    return out


PROBE_MOVED = ["probe moved block line one alpha bravo charlie", "probe moved block line two delta echo foxtrot"]
PROBE_ANCHOR = [f"anchor line {w} that stays where it is" for w in ("one", "two", "three", "four", "five")]
PROBE_INDENT = ["def probe_indented_one(): return 'golf hotel india'", "def probe_indented_two(): return 'juliet kilo lima'"]


def probe(repo):
    """True when this machine's git marks a known moved block as moved and does
    not mark a known re-indented block, with the same command."""
    with tempfile.TemporaryDirectory() as tmp:
        old, new = os.path.join(tmp, "old"), os.path.join(tmp, "new")
        with open(old, "w") as f:
            f.write("\n".join(PROBE_MOVED + PROBE_ANCHOR + PROBE_INDENT) + "\n")
        with open(new, "w") as f:
            f.write("\n".join(PROBE_ANCHOR + PROBE_MOVED + ["    " + l for l in PROBE_INDENT]) + "\n")
        try:
            r = subprocess.run(moved_command(repo) + ["--no-index", old, new], capture_output=True, timeout=MOVED_TIMEOUT)
        except (OSError, subprocess.SubprocessError):
            return False
    if r.returncode != 1:
        return False
    lines = [l for _, ls in parse(r.stdout.decode(errors="surrogateescape")) for l in ls]
    want = sorted([("-", True, t) for t in PROBE_MOVED] + [("+", True, t) for t in PROBE_MOVED]
                  + [("-", False, t) for t in PROBE_INDENT] + [("+", False, "    " + t) for t in PROBE_INDENT])
    return sorted(lines) == want


def moved_lines(repo, base, head, files):
    """([moved lines per counted file], None), or (None, the reason no discount applies)."""
    try:
        r = subprocess.run(moved_command(repo) + [base, head, "--"] + [p for _, _, p in files], capture_output=True, timeout=MOVED_TIMEOUT)
    except subprocess.TimeoutExpired:
        return None, "coloured diff timed out"
    except (OSError, subprocess.SubprocessError):
        return None, "coloured diff failed"
    if r.returncode != 0:
        return None, "coloured diff failed"
    sections = parse(r.stdout.decode(errors="surrogateescape"))
    path = disagreement(files, sections)
    if path is not None:
        return None, f"line counts disagree in {path}"
    per = discounts(sections)
    if sum(per) and not probe(repo):
        return None, "git move check failed on this machine"
    return per, None


def main(argv):
    repo, base, head = argv[1:4]
    files = counted(repo, base, head)
    raw = sum(a + r for a, r, _ in files)
    if len(argv) < 5 or argv[4] != "--report":
        print(raw)
        return 0
    label, limit = argv[5], int(argv[6])
    moved, reason = moved_lines(repo, base, head, files) if files else ([], None)
    if moved is None:
        moved = [0] * len(files)
    rows = [(a + r - m, m, p) for (a, r, p), m in zip(files, moved)]
    total = sum(c for c, _, _ in rows)
    if reason:
        note = f"; moved-line discount not applied: {reason}"
    elif sum(moved):
        note = f"; {sum(moved)} lines moved unchanged not counted"
    else:
        note = ""
    print(f"ROUND-1 SIZE: {total} changed non-test lines from {label} (size note above {limit}{note})")
    if total > limit:
        for c, m, path in sorted(rows, key=lambda row: (-row[0], row[2])):
            print(f"  {c:6d}  {m:6d} moved  {path}")
        print(f"SIZE NOTE: over {limit} changed non-test lines; reviewed whole in this round (no split asked)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
