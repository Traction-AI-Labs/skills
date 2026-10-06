---
name: reading-page
description: Use whenever the person you work with is meant to READ something longer than a chat message, in any project - a research report, plan, brief, handoff, review, summary, status write-up or investigation. Builds a polished, self-contained interactive HTML page (contents rail, bottom-line box, callouts, sortable tables, folded evidence, light and dark) from markdown with one command and opens it for them. Never hand them a .md file to read. Decisions they must rule on go to the ruling-page skill instead.
---

# Reading page

People read long agent output far better as a designed page than as raw markdown. Anything longer
than a chat message that the reader is meant to read goes out as one self-contained HTML page: a
contents rail, the bottom line first, callouts, sortable tables, folded evidence, light and dark.
The markdown can stay the agent's record beside it; the page is how the reader reads it.

**Use it for:** research reports, plans, briefs, handoffs, reviews, summaries, investigations,
anything longer than a chat message that they are meant to read.
**Not for:** chat replies (stay in chat); decisions they must rule on (`ruling-page`; a report that
also needs rulings links to its ruling page from a decision callout); call prep (`call-prep`).

## Build it

1. Write the report as markdown beside where it belongs (the project's repo: `research/`, the
   plan or status folder). The markdown stays the agent record and goes in git.
2. Build the page beside it, same name, `.html`:
   ```bash
   uv run <skill-dir>/scripts/build.py <report>.md \
     --author "Claude" --status "Research complete"
   ```
   `<skill-dir>` is the folder holding this SKILL.md. Output defaults to `<report>.html`. Dependencies are pinned in the script header (PEP 723),
   so `uv run` needs nothing installed. Optional `--title`, `--date YYYY-MM-DD`, `--template`;
   front matter (`title`, `date`, `author`, `status`) works too.
3. Check it before they see it (below), commit both files, then `open <report>.html` and say in
   the message which page is open. They never get "read X.md".

## Write the markdown so the page comes out right

The script reads the patterns agents already write. Use them on purpose:

| Write this | Get this |
|---|---|
| `# Title` (a leading H1) | Page title. Always consumed; `--title` or front matter `title` overrides its text |
| First paragraph starting `Date: 2026-10-07.` | Date moves into the header; the rest of that paragraph becomes the standfirst. Anything else before the first `##` opens the article |
| `## Recommendation` / `Bottom line` / `Summary` / `TL;DR` / `Verdict` / `Answer` | The section's opening paragraph becomes the bottom-line box. Put the answer first, opening with one bold sentence. A section that opens with a list, a heading or a bold label gets no box |
| `## Sources` / `Evidence` / `References` / `Appendix` / `Method` / `Notes` | A folded section, closed by default |
| `## 2. Buy options` (a number, a full stop, a space) | Numbered section; the number shows in the contents. `## 2026 roadmap`, `## 3 risks` and `## 2.0 notes` stay plain titles |
| `**Main risks:**` then a list | Risk callout with the list inside (labels with risk, caveat, concern) |
| `**Smallest version worth having:**` / `**Recommendation:**` / `**Next steps:**` | Recommendation callout |
| `**Decision needed:**` / `**Open question:**` | Decision callout; link the ruling page from it |
| `**When X would be right instead:**` / `**Note:**` / `**Alternative:**` | Note callout |
| A paragraph that is only a short bold label, e.g. `**Authz model.**` | An H3 sub-heading in the contents. Label means up to eight words, no ending `!` or `?`, and no sentence words (not, must, should, is, are, we, you, it, this...): `**Do not ship before Friday.**` stays a bold paragraph |
| `> [!RECOMMENDATION]` `[!RISK]` `[!DECISION]` `[!NOTE]` `[!VERIFIED]` `[!INFERRED]` `[!BOTTOMLINE]` | The matching callout (GitHub's `[!TIP]` `[!WARNING]` `[!IMPORTANT]` `[!CAUTION]` map too) |
| `[V]`, `[V, source]`, `[V: how]`, `[I]`, `[I, why]` | Inline Verified / Inferred marks with the source beside them (never inside code, so `` `[V]` `` stays literal) |
| `Claim.[^1]` with `[^1]: https://source` (or a prose note) anywhere | Superscript `1` linking to a Notes section at the end of the page; each note links back to where it was cited. Prefer this or a `## Sources` list for citations |
| Tables | Styled tables; four or more rows sort by header click; cards on a phone |
| Code fences | Blocks with a Copy button |
| Bare `https://` URLs | Links; external links open in a new tab |
| `[Jump](#1-options)` (GitHub-style anchor; `#risk-1` for the second `## Risk`) | A working in-page link to that heading |
| `![alt](diagram.png)` in the markdown's folder (or a subfolder) | Embedded in the page (data: URI), so the HTML travels alone. Absolute paths, `../` and symlinks leading outside the folder are never read: they show the alt text |
| `![alt](https://...)` remote image | Never loaded (it would need the network and tells the host the page was opened): alt text and the URL show as text. Save the image beside the markdown to show it. A missing file shows its alt text |
| Raw HTML (`<details>`, `<script>`, `<!--`) | Shown as text, never run. Only http(s), mailto, relative and `#` links become links |

Lead with the answer. Keep paragraphs short. Prefer a table for any comparison of three or more
things. Put raw evidence under a Sources or Evidence heading so it folds away.

## Check before they see it

Headless only, never on the reader's screen. `scripts/browser_check.sh <page>.html` (needs
`agent-browser`) loads the page at phone width with JavaScript off and on, and checks the contents,
links, ids, the phone bar, sideways overflow and the console; it exits non-zero on any failure.
Headless browsers are heavy: if the reader's machine is busy, run it on another machine. When you
change the template or `build.py`, also build `scripts/fixtures/long-tokens.md` and check that page.

Then read it as they will: the bottom line answers the question without scrolling. Fix what looks
off; if the template is the problem, fix the template, not the one page.

## What the page does

- Header with title, standfirst, date, author, status, and theme / open-evidence / print tools.
- Sticky contents rail with scroll-spy on desktop; on narrower screens a sticky bar showing the
  current section that opens the contents as a sheet. The contents list is written into the HTML,
  so without JavaScript (iOS Quick Look of a file) it shows as a plain list above the page and the
  bar and tool buttons are hidden.
- Bottom-line box, callouts (recommendation, risk, decision needed, note, verified, inferred),
  provenance marks, sortable tables that stack into cards on a phone, code copy buttons,
  collapsible evidence, a hairline reading-progress bar.
- Light and dark follow the system; the toggle overrides and is remembered.
- Print or save as PDF opens every fold, drops the chrome and prints external URLs.
- Typography: Charter body, Avenir Next headings (both ship with macOS and iOS; fallbacks
  elsewhere), measure about 68 characters. No external assets, no network, works from `file://`.
- No time estimates anywhere: no reading-time badge.

## Hand-built pages

For something markdown cannot express, copy `references/template.html` and replace only the
marked regions (`<title>`, `@title`, `@standfirst`, `@meta`, `@toc`, `@body`). Fill `@toc` with the
same static list `build.py` writes (one link per h2 and h3, in order), so the contents still show
where scripts do not run, such as an iPhone Quick Look preview; an empty `@toc` is filled by the
script only when JavaScript runs. Prefer `build.py` whenever markdown can express the page. The demo body in the
template shows every component's markup; the script at the bottom builds the contents,
scroll-spy, copy buttons, sorting and phone cards from whatever is in the article.
