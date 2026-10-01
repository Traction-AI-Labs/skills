# Ruling page

When Claude needs you to decide something complicated (several decisions at once, or options with
trade-offs), it builds a one-file HTML page instead of asking you to read a document:

- one card per decision, in plain words, with Claude's recommendation pre-selected and the reason in one line;
- the alternatives as buttons, and a box for your own words;
- "Accept all picks" and "Copy my answers", which puts one line per decision on your clipboard to paste back into chat.

Simple yes/no questions stay in chat.

## Install

**Claude Code**

```
/plugin marketplace add Traction-AI-Labs/skills
/plugin install ruling-page@traction
```

**Claude app** (desktop or web)

1. Get `Ruling page by Traction Studio.zip`. If someone has sent it to you, skip to step 2. To build
   it from this repository, run `bash plugins/ruling-page/scripts/build-zip.sh` from the repository
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
