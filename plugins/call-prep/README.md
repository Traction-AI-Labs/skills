# Call prep

Ask Claude to prep you for a call and you get a script you can read from while you talk, not a list of
points to cover. It is one interactive HTML page for a second screen:

- a header with the time, who's on the call, and a guard line of what you must not say;
- five to eight numbered beats, each with the exact words to say in quotes and short stage directions;
- a fallback line under any beat likely to meet pushback, and answers to the hardest questions they
  might ask, in their hardest phrasing;
- for a yes/no call (a hiring screen, a vendor pick), a checklist and a one-line rule for deciding at
  the close;
- keyboard jumps between beats (`1` to `8`, `j`/`k`, `a` for answers, `d` for decide, `g` to hide the
  guard line).

Never screen-share the window the prep is in.

## Install

**Claude Code**

```
/plugin marketplace add Traction-AI-Labs/skills
/plugin install call-prep@traction
```

**Claude app** (desktop or web)

1. Get `Call prep by Traction Studio.zip`. If someone has sent it to you, skip to step 2. To build it
   from this repository, run `bash plugins/call-prep/scripts/build-zip.sh` from the repository root;
   it lands in `plugins/call-prep/dist/`.
2. In the Claude app, open **Customize**, then **Skills**, upload the zip and check it is switched on.

**Codex:** copy `plugins/call-prep/skills/call-prep` to `~/.codex/skills/call-prep`.

## Use

Ask, for example: *Prep me for my 15:00 call with the new client. Here's the last email and our notes
from the kickoff.* Claude checks your calendar for the time and attendees when it can, pulls every number
from the source you gave it, and writes the page. In Claude Code it opens the file; in the Claude app it
shows the page as an artifact. For a pricing or negotiation call, ask for the review pass: two fresh
reviewers check every number against the sources and read the script cold as you.

## Test

`node plugins/call-prep/scripts/template.test.mjs` from the repository root loads the template the way the Claude app
does (a sandboxed frame with storage blocked) and fails on a script error or a broken behaviour. It needs Node 18+
and Playwright (`npm i --no-save playwright && npx playwright install chromium`).
