# Ruling page

When Claude needs you to decide something complicated (several decisions at once, or options with
trade-offs), it builds a one-file HTML page instead of asking you to read a document:

- a short brief at the top (the background, and the choices already made, folded away);
- one card per decision, in plain words, with Claude's recommendation pre-selected (drawn dashed until you
  confirm it), the reason in one line, and what would change it;
- the alternatives as buttons, each with what it does and its downside, and a note box for your own words;
- cards that need more than one pick: several questions on one card, "choose any" options, or a typed answer;
- pictures of each option where the choice is visual, and the exact words of anything the pick would send;
- a progress strip and a contents rail showing what you have answered;
- "Accept all picks" and "Copy my answers", which puts one block per decision on your clipboard to paste back
  into chat, listing anything you left unanswered.

A second template, **open questions**, answers questions you asked: each card shows your question, the
answer, what is still owed, a **Got it** button, and any decisions that follow from it.

Simple yes/no questions stay in chat.

## Install

**Claude Code**

```
/plugin marketplace add Traction-AI-Labs/skills
/plugin install ruling-page@traction
```

**Claude app** (desktop or web)

1. Get `Ruling page by Traction Studio.zip`. If someone has sent it to you, skip to step 2. To build
   it from this repository, run `bash scripts/build-zip.sh ruling-page` from the repository
   root; it lands in `plugins/ruling-page/dist/`.
2. In the Claude app, open **Customize**, then **Skills**, upload the zip and check it is switched on.

**Codex:** copy `plugins/ruling-page/skills/ruling-page` to `~/.codex/skills/ruling-page`.

## Use

Nothing to set up. When a decision needs a page, Claude builds one and opens it (Claude Code) or shows
it as an artifact (Claude app). Click through, then press **Copy my answers** and paste into the chat.

In Claude Code the page is a file, so your answers are saved in the browser as you click and survive a
reload. In the Claude app, answers last only while the artifact is open, so copy them before you close
it. If your browser blocks the clipboard, the page says so and leaves the text selected for you to copy.

## Test

`node plugins/ruling-page/scripts/template.test.mjs` from the repository root loads the template the way the Claude app
does (a sandboxed frame with storage blocked) and fails on a script error or a broken behaviour. It needs Node 18+
and Playwright (`npm i --no-save playwright && npx playwright install chromium`).

After changing a template, also run the two static checks in `skills/ruling-page/scripts/house-check/`
(`edges.py` for one-sided accents, `same.py` for the shared engine and colour tokens); the skill's
"Changing the templates" section has the commands.
