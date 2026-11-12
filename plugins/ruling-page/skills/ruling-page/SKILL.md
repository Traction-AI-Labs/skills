---
name: ruling-page
description: Use when you need the person you're working with to rule on a COMPLICATED decision (several decisions at once, or options with trade-offs that need explaining), or when asks from several threads need one answer. Builds a clickable one-file HTML ruling page with your recommendation pre-selected on every card and a "Copy my answers" button, instead of asking them to read a markdown file or a long chat message. Simple yes/no decisions stay in chat.
---
<!-- SOURCE-REVISION 46e23df0 -->

# Ruling page

Complicated decisions go to the person as a page they click through, never as a document they have
to read ("see the table in plan.md", "answer K1 to K10 at the top of the spec"). Simple decisions stay
in chat: an HTML page for a yes/no is noise.

**Simple or complicated?** One yes/no, or a pick between two options whose difference fits on one
line: ask in chat, with your recommendation and a one-line why. Several decisions, or options with
real trade-offs: build a page.

## Build it

1. Copy `references/template.html` next to the record the decisions belong to (the plan, spec or
   status folder; a private one when a client or third party can read that folder), named for what it rules on, for example `2026-10-02-pricing-rulings.html`.
   **In the Claude app**, where there is no local folder, fill the template and show it as an HTML
   artifact instead; the rest of this skill is the same.
2. In the data script, replace `RULER`, `BRIEF` and `D` (keep the `svg` helper above `D` if your
   frames use inline SVG), and the `<h1>`; the sample shows each kind of card once. Every field is plain
   text: the page shows any HTML in it literally, so text pasted from a source cannot run.
   - `RULER`: the name of whoever rules. It heads Copy my answers; leave it empty and the heading is
     just "Rulings:".
   - `BRIEF` (optional): `{date, lede, body, decided: [[title, detail], ...], source: [label, href]}`:
     the line under the title, the background, the choices already made (folded, with one note box),
     and a link to the full report.
   - `RULING_BRIDGE` (optional, leave it out unless you need it): `{origin, id}`, only when a host page
     embeds the ruling page in a frame and collects the answers. Answers are posted to that exact
     origin, never to `*`.

   Fields per card:
   - `id`: short, stable and unique (`K1`, `D3`). Answers are saved under it, so never renumber a card
     they may already have answered. Answers are saved by option position: on such a card, add options
     only at the end, and give a changed question a new id (`D3b`). A repeated id is left out with a
     console error.
   - `short` (optional): the label the rail, the card head and the progress bar show, for a long `id` such as a
     tracker key (`pricing-2026-K1` shows as `K1`). Answers stay saved and copied under `id`. It is for
     cards only (a part shows its own `id`); keep each `short` unique on the page.
   - `group` (optional): a section heading, for example one per workstream.
   - `title`, `q`: plain words, one sentence for the question. No codes, lane names or jargon they
     would have to look up.
   - `opts`: `[["label", "what this does in practice, in one line", "downside (optional)"], ...]`.
   - `pick`: the index of your recommendation. It is pre-selected, drawn dashed until they confirm it.
   - `why`: one or two sentences. `flip` (optional): what would change your pick.
   - `ev`: the evidence in plain words. A file path or ticket id may follow as reference only, never
     as something they must open.
   - `text` (optional): when the card approves something going out (an email, a comment, a reply), the
     exact words, so they never have to open a file to see them. Shown collapsed under the question;
     `textLabel` renames the toggle and `textOpen: true` shows it open. Set it whenever the pick sends
     the words, so they are on screen when the pick is accepted.
   - `frames` (optional): `[{src, cap}, ...]`, pictures of what each option looks like (design frames,
     screenshots). Thumbnails sit under the question and enlarge on click, with arrow keys between them.
     `src` is a `data:image/...` URI (keeps the file self-contained) or a plain relative path beside the
     page; anything else is dropped. Use it whenever the options are visual.
   - Also optional: `chip` (a short flag beside the title, "Can wait"); `context` (background: a blank
     line between paragraphs, `- ` bullets, `**bold**`); `multi: true` ("choose any"; `pick` becomes a
     list of indexes); `input: "text"` with `placeholder` (a typed answer instead of options); `parts:
     [{id, q, opts, pick, why, flip, multi, input, placeholder}]` (several questions on one card; give
     each part a stable id like `K1a`, as answers are saved under it and a missing id is taken from the
     part's position).
3. Check it before they see it. With a shell and a headless browser (for example `agent-browser`):
   open the file, then check that the number of `.tp-card` elements equals the number of cards in `D`,
   that the page and console show no errors, and that `rulingText()` (the text Copy my answers would
   copy) starts `Rulings (<RULER>): 0 of <N> answered` (`Rulings: 0 of <N>` with no `RULER`), with every
   card id after a line break. Copy any picture files with the page, at the same relative paths. With
   a shell but no browser, the extracted scripts must at least pass `node --check`. Without a shell,
   read the data through once for unbalanced quotes and brackets.
4. Show it. In Claude Code, open the file for them (`open` on macOS, `xdg-open` on Linux, `start` on
   Windows) and lead your message with one line: the page is open, where it is, and how many cards.
   In the Claude app, the artifact is the page; say so in one line above it.

## One card per decision

- The question in one sentence.
- What each option does in practice, not what it is called.
- Your recommendation pre-selected, with one line of why.
- The evidence behind it in plain words.
- Answerable in seconds: a pre-selected pick, the alternatives as buttons, and a note box for
  their own words.

Several decisions, or asks from several threads, go on one page, not one page each.

## When the page no longer needs answers
Both templates ship with `const STATE = {status: "live"};` in the data script: keep it, and the page opens with a
"This needs you" banner (coral, "!") above the title. Once they have answered, or another page takes over, replace
that line; the page is never deleted or moved. Every field is needed except `why`, `answers_in` and the `_title`s:
- `{status: "replaced", replaced_by: "<the replacement's .html>", replaced_by_title, replaced_on: "12 Nov 2026", why}`
- `{status: "answered", answered_on, answers_in: "<the .html where the answers are recorded>", answers_in_title, why}`.
  Leave `answers_in` out when the answers are recorded only in markdown (a `plan.md`); never link the `.md`.

The banner then reads "Nothing for you to answer here" with the link and date, the instructions, tally, Accept all
picks, the notes and Send your answers are hidden or switched off, Copy is switched off, and the cards fold, dimmed,
under "Show the old cards", where they can still be read (background, the text that goes out, pictures) but not
answered. Printing opens the fold. A missing field, a link that is not another page's `.html` (a `.md`, `mailto:` or
text file) or an unknown status is a console error, so step 3's check catches it. A page whose data has no `STATE`
line (made from an older template) shows no banner and works exactly as before.

A page made from an older template has no code that reads `STATE`, so adding the line does nothing. To give it a
state, copy its data script (RULER, BRIEF, D or T) and its `<h1>` into the current template, add the `STATE` line,
and save it over the old file at the same path, so answers already saved in the browser carry over. Whenever a
page's state changes, run step 3's check and show it again as step 4 says, or they keep seeing the old live page.

## What the page already does

- "Accept all picks" confirms your recommended pick on every choice not yet answered, partly answered
  cards included, never over an answer or a note. A status word per card, a live tally, a count of
  answers that differ from your pick, and note boxes per card, on the decided list and for the whole page.
- Answers save in the browser as they click and type, keyed by page path and card id, so a reload or
  cards you add later never lose them, and answers saved by the previous version of the template carry
  over. Add cards by editing the file in place; never rebuild it with new ids for the same decisions,
  and never move or rename it once they have opened it. **In a Claude app artifact, browser storage is
  blocked**, so answers last only while the artifact is open. The page detects this and says "Not saved
  in this window: copy your answers before you close it"; tell them too.
- "Copy my answers" puts one block per card, led by its id and title, on the clipboard for them to
  paste into chat. Where the clipboard is blocked, the page says so and leaves the text selected on
  screen to copy by hand. From the sample, with `RULER` set:
  ```
  Rulings (<RULER>): 2 of 7 answered, 2 not your pick
  S1 Where customer emails land: A shared inbox (your pick)
  S2 How fast we promise to reply: Four working hours (NOT your pick)
  S3 Weekend cover: not answered (your pick was Nobody at the weekend) | note: Who answers on public holidays?
      Only if it's busy.
  S4 The questions customers ask most: not answered
  W1 When the new website goes live:
    W1a Which pages go live first? -> Home; Pricing (NOT your pick)
    W1b When should it go live? -> not answered (your pick was End of the month)
    W1c Anything the launch must include? -> Check the contact form on day one.
  W2 The home page layout: not answered (your pick was Layout A, one column)
  W3 Tell the team about the launch: not answered (your pick was Yes, send it)
  Already decided | note: Keep the old address for a year.
  Anything else: Do the support desk first.
  Partly answered: S3, W1
  Not answered: S4, W2, W3
  ```

## After they paste

Record their pasted answers verbatim, with the time, wherever the decisions are written down (the
plan, spec or requirements file; a private one when others can read it), then act on the answered lines only. A line that reads "not answered
(your pick was ...)", and every id under "Partly answered" or "Not answered", is still open: never act
on your own pick for it; ask about those ids once, in chat. If another thread owns some cards, pass its
lines on.

A line whose note asks a question is not yet a go, whatever option it picks: answer the question in plain
words, saying what it means for the decision (that this is new work, what it costs, that the earlier work
did not cover it), and act only after they reply. A line passed on to another thread carries its question,
and that thread waits too.

## Threads variant: open questions with answers

When the page carries answers to questions they asked, not only decisions, use
`references/template-threads.html`. Each card is a thread: their question verbatim with when and where
they asked it, the answer, what is still owed and by whom, a **Got it** button (saved like a choice),
then one or more branch decisions with the same pick buttons. Replace only the data script (`RULER`,
`BRIEF` with `date` and `lede`, `T`) and the `<h1>`. Thread fields: `id`, `short` (optional, as above), `group`, `title`, `asked`,
`when`, `answer`, `owed` (empty hides it), `ev`, `branches: [{id, q, opts, pick, why, flip, multi}]`.
Branch ids are stable (`Q1a`, `Q1b`). Check it as in step 3: the card count equals the number of
threads in `T`, and `rulingText()` starts `Open questions: 0 of <N> answers read, 0 of <B> decisions
answered` (B is the number of branches). "Copy my answers" gives one line per thread (got it or not
read yet) with its decisions indented below.

## Changing the templates

The look is shared with `reading-page` and `call-prep`. No one-sided accents: never a border, shadow
or bar down one side of a box (or moved to its top or bottom); show state with a tinted fill, a full
outline, a label or a filled marker, never colour alone. The two ruling templates share their engine
(the script from "Ruling page engine. Authors never edit below this line.") word for word: change both.
After any template change, from this skill's folder in a clone of its repository:

```bash
python3 -I scripts/house-check/edges.py references/template.html references/template-threads.html \
  ../../../reading-page/skills/reading-page/references/template.html \
  ../../../call-prep/skills/call-prep/references/prep-template.html
python3 -I scripts/house-check/same.py references/template.html references/template-threads.html \
  ../../../reading-page/skills/reading-page/references/template.html \
  ../../../call-prep/skills/call-prep/references/prep-template.html
```

`edges.py` exits 1 on a one-sided edge in the CSS as written; `same.py` exits 1 if the two engines
differ or a shared `--tp-*` token has two values. Then run the plugin's `scripts/template.test.mjs`
(see the README) and look at the pages at phone and desktop width, light and dark.

## Common mistakes

| Mistake | Fix |
|---|---|
| A page for a single yes/no | Ask in chat |
| "Please read plan.md and answer the questions at the top" | Build the page; the file stays the record |
| Option labels that name the thing ("Option B: lane two") | Say what it does in practice |
| Evidence as a path they have to open | Plain-words evidence; the path below it for reference |
| New ids when adding cards to a page they've started | Keep existing ids; add new ones |
| Acting on your own pick for a card they left unanswered | Ask about the open ids once, in chat |
| One page per thread when several threads need answers today | One page, grouped |
