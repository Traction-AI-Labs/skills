---
name: ruling-page
description: Use when you need the person you're working with to rule on a COMPLICATED decision (several decisions at once, or options with trade-offs that need explaining), or when asks from several threads need one answer. Builds a clickable one-file HTML ruling page with your recommendation pre-selected on every card and a "Copy my answers" button, instead of asking them to read a markdown file or a long chat message. Simple yes/no decisions stay in chat.
---

# Ruling page

Complicated decisions go to the person as a page they click through, never as a document they have
to read ("see the table in plan.md", "answer K1 to K10 at the top of the spec"). Simple decisions stay
in chat: an HTML page for a yes/no is noise.

**Simple or complicated?** One yes/no, or a pick between two options whose difference fits on one
line: ask in chat, with your recommendation and a one-line why. Several decisions, or options with
real trade-offs: build a page.

## Build it

1. Copy `references/template.html` next to the record the decisions belong to (the plan, spec or
   status folder), named for what it rules on, for example `2026-10-02-pricing-rulings.html`.
   **In the Claude app**, where there is no local folder, fill the template and show it as an HTML
   artifact instead; the rest of this skill is the same.
2. Replace only the `D` array and the `<h1>`. Every field is plain text: the page shows any HTML in it
   literally, so text pasted from a source cannot run. Fields per card:
   - `id`: short and stable (`K1`, `D3`). Answers are saved under it, so never renumber a card they
     may already have answered.
   - `group` (optional): a section heading, for example one per workstream.
   - `title`, `q`: plain words, one sentence for the question. No codes, lane names or jargon they
     would have to look up.
   - `opts`: `[["label", "what this does in practice, in one line"], ...]`.
   - `pick`: the index of your recommendation. It is pre-selected and marked MY PICK.
   - `why`: one or two sentences.
   - `ev`: the evidence in plain words. A file path or ticket id may follow as reference only, never
     as something they must open.
3. Check it before they see it. With a shell: the script must parse (extract it and run
   `node --check`), and every card must render (count `.card` elements in a headless browser).
   Without one, read the `D` array through once for unbalanced quotes and brackets.
4. Show it. In Claude Code, open the file for them (`open` on macOS, `xdg-open` on Linux, `start` on
   Windows) and lead your message with one line: the page is open, where it is, and how many cards.
   In the Claude app, the artifact is the page; say so in one line above it.

## One card per decision

- The question in one sentence.
- What each option does in practice, not what it is called.
- Your recommendation pre-selected, with one line of why.
- The evidence behind it in plain words.
- Answerable in seconds: a pre-selected pick, the alternatives as buttons, and an "other" box for
  their own words.

Several decisions, or asks from several threads, go on one page, not one page each.

## What the page already does

- "Accept all picks", a live count of cards changed from your picks, and a free-text box per card.
- Answers save in the browser as they click and type, keyed by page path and card id, so a reload
  or cards you add later never lose them. Add cards by editing the file; never rebuild it with new
  ids for the same decisions. **In a Claude app artifact, browser storage is blocked**, so answers
  last only while the artifact is open. The page detects this and says "Not saved in this window: copy
  your answers before you close it" in place of "Answers save as you go"; tell them too.
- "Copy my answers" puts one line per card on the clipboard for them to paste into chat. Where the
  clipboard is blocked, the page says so and leaves the text selected on screen to copy by hand.

## After they paste

Record their pasted answers verbatim, with the time, wherever the decisions are written down (the
plan, spec or requirements file), then act on them. If another thread owns some cards, pass its lines
on.

## Threads variant: open questions with answers

When the page carries answers to questions they asked, not only decisions, use
`references/template-threads.html`. Each card is a thread: their question verbatim with when and where
they asked it, the answer, what is still owed and by whom, a **Got it** tick (saved like a choice),
then one or more branch decisions with the same pick buttons. Replace only the `T` array and the
`<h1>`. Branch ids are stable (`Q1a`, `Q1b`). "Copy my answers" gives one line per thread (got it or
not read yet) with its decisions indented below.

## Common mistakes

| Mistake | Fix |
|---|---|
| A page for a single yes/no | Ask in chat |
| "Please read plan.md and answer the questions at the top" | Build the page; the file stays the record |
| Option labels that name the thing ("Option B: lane two") | Say what it does in practice |
| Evidence as a path they have to open | Plain-words evidence; the path below it for reference |
| New ids when adding cards to a page they've started | Keep existing ids; add new ones |
| One page per thread when several threads need answers today | One page, grouped |
