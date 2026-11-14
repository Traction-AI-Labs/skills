"""Builds the render copies of each page from the plugins' own templates and the made-up examples in docs/examples/.

Usage: python3 -I scripts/media/fill.py <repository root> <work dir>. The templates are read, never edited; every
copy is written to the work dir. render.sh calls this.
"""
import html
import json
import re
import sys
from pathlib import Path

root, work = Path(sys.argv[1]), Path(sys.argv[2])
ex = root / "docs" / "examples"
work.mkdir(parents=True, exist_ok=True)


def drop_leading_comments(text):
    """The examples open with a "Made-up example" comment line; the page copy starts after it."""
    while True:
        m = re.match(r"\s*<!--.*?-->[ \t]*\n", text, re.S)
        if not m:
            return text
        text = text[m.end():]


# ruling-page: swap the template's data script for the example's, and set the <h1> from its TITLE
t = (root / "plugins/ruling-page/skills/ruling-page/references/template.html").read_text()
m = re.search(r"(<!-- DATA:[^\n]*\n<script>\n)(.*?)(\n</script>\n<!-- END DATA -->)", t, re.S)
assert m, "ruling-page template: DATA region not found"
data = (ex / "ruling-page/data.js").read_text()
title = re.search(r'^const TITLE = "([^"]+)";$', data, re.M)
assert title, "ruling-page example: const TITLE line not found"
t = t[:m.start(2)] + data.rstrip() + t[m.end(2):]
t, n = re.subn(r'(<h1 class="tp-h1" id="tp-title">)[^<]*(</h1>)', lambda g: g.group(1) + html.escape(title.group(1)) + g.group(2), t)
assert n == 1, "ruling-page template: h1 not found"
(work / "ruling.html").write_text(t)

# call-prep: splice the example into the template's PREP region and set the <title> from its title comment
t = (root / "plugins/call-prep/skills/call-prep/references/prep-template.html").read_text()
m = re.search(r"(<!-- PREP:[^\n]*-->\n)(.*?)(<!-- END PREP -->)", t, re.S)
assert m, "call-prep template: PREP region not found"
region = (ex / "call-prep/prep-region.html").read_text()
title = re.search(r"^<!-- title: (.+?) -->$", region, re.M)
assert title, "call-prep example: <!-- title: ... --> line not found"
t = t[:m.start(2)] + drop_leading_comments(region) + t[m.end(2):]
t, n = re.subn(r"<title>.*?</title>", lambda g: f"<title>{html.escape(title.group(1))}</title>", t, count=1)
assert n == 1, "call-prep template: <title> not found"
(work / "call-prep.html").write_text(t)

# reading-page: the markdown after its label line goes to the plugin's own build script (render.sh runs it)
(work / "reading.md").write_text(drop_leading_comments((ex / "reading-page/flaky-test.md").read_text()))

# terminal sessions: one page per session; ?step=N shows the first N typed commands with their output
tmpl = (root / "scripts/media/terminal.html").read_text()
for name in ("gauntlet", "doc-gauntlet"):
    lines = (ex / name / "session.txt").read_text().splitlines()
    title = next(line.split(":", 1)[1].strip() for line in lines if line.startswith("# title:"))
    steps, cur = [], None
    for line in (line for line in lines if not line.startswith("#")):
        if line.startswith("$ "):
            cur = {"cmd": line[2:], "out": []}
            steps.append(cur)
        elif cur is not None:
            cur["out"].append(line)
    page = tmpl.replace("__TITLE__", html.escape(title)).replace("__STEPS__", json.dumps(steps).replace("</", "<\\/"))
    (work / f"terminal-{name}.html").write_text(page)
    (work / f"terminal-{name}.steps").write_text(str(len(steps)))
print("fill.py: wrote", ", ".join(sorted(p.name for p in work.iterdir() if p.is_file())))
