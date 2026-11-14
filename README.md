# Traction skills

Skills for Claude Code, the Claude app, Codex and Grok, published by Traction Studio.

## What's here

| Plugin | What it does | Runs in |
|---|---|---|
| **gauntlet** | Reviews a committed code diff with two independent engines (Claude and Codex by default; Grok can take either slot) | Claude Code, Codex, Grok, or the portable CLI |
| **doc-gauntlet** | Reviews a committed plan, spec or requirements document with six breadth lenses, then the same two-engine pair; returns a sparring memo for the author and a short list of true errors | Claude Code, Codex, Grok, or the portable CLI |
| **persona-teardown** | Walks a prototype, UI kit or live screen with three to five cold persona agents driving `agent-browser`, one session and one report each, with a coverage ledger of every screen, control, state and ground, then consolidates the findings into one amendment prompt for the design tool | Claude Code or Codex (subagents) |
| **ruling-page** | Turns a complicated decision into a clickable one-file HTML page: a recommendation pre-selected on every card, alternatives as buttons, and one button that copies the answers back into chat | Claude Code, the Claude app |
| **reading-page** | Turns anything longer than a chat message into one self-contained HTML page to read instead of markdown: the bottom line first, a contents rail, callouts, sortable tables, folded evidence, light and dark | Claude Code, the Claude app, Codex |
| **call-prep** | Writes a verbatim call script as one interactive HTML page to read live on a second screen: a guard line of what not to say, numbered beats with the exact words, fallbacks for pushback and answers to the hardest questions | Claude Code, the Claude app |
| **humanize-writing** | Rewrites a draft so it reads like a person wrote it for its reader, adding nothing the draft did not say: removes the templates current models write in, says each point in the writer's own voice, keeps technical text's steps and figures, and checks every edit against the draft | Claude Code, the Claude app, Codex |
| **go-deeper** | Rewrites a task to be more ambitious before doing it: what a top professional in the field would do that wasn't asked, the rawest material they'd start from, the methods and tools they'd use and an outside judge, then a rewritten prompt. Also covers altitude (the outcome behind the deliverable) and range (methods from other fields) | Claude Code, the Claude app, Codex |

Each plugin's own README covers set-up and use in more detail.

## Install

### Claude Code

```
/plugin marketplace add Traction-AI-Labs/skills
/plugin install gauntlet@traction
/plugin install doc-gauntlet@traction
/plugin install persona-teardown@traction
/plugin install ruling-page@traction
/plugin install call-prep@traction
/plugin install reading-page@traction
/plugin install humanize-writing@traction
/plugin install go-deeper@traction
```

Install only the ones you want.

### Codex

```
git clone https://github.com/Traction-AI-Labs/skills.git
cp -R skills/plugins/gauntlet/skills/gauntlet ~/.codex/skills/gauntlet
cp -R skills/plugins/doc-gauntlet/skills/doc-gauntlet ~/.codex/skills/doc-gauntlet
cp -R skills/plugins/persona-teardown/skills/persona-teardown ~/.codex/skills/persona-teardown
```

The same pattern works for any other skill (`plugins/<plugin>/skills/<skill>`). To update, remove the
old directory and copy again.

### Grok

Same copy, destination `~/.grok/skills/<skill>`.

### The Claude app

ruling-page, call-prep, reading-page, humanize-writing and go-deeper install as upload zips. Build them from the repository root:

```
bash plugins/ruling-page/scripts/build-zip.sh
bash plugins/call-prep/scripts/build-zip.sh
bash plugins/reading-page/scripts/build-zip.sh
bash plugins/humanize-writing/scripts/build-zip.sh
bash plugins/go-deeper/scripts/build-zip.sh
```

Each lands in that plugin's `dist/` folder. In the Claude app, open **Customize**, then **Skills**, upload
each zip and check it is switched on. The zips are build outputs; never commit them.

### Portable CLI

Clone the repo. From `plugins/gauntlet` or `plugins/doc-gauntlet`, follow that directory's README.

## Before you run a gauntlet

The two gauntlets need Bash, Git, Python 3 and GNU `timeout` (on macOS, `brew install coreutils`).
Authenticate the CLIs in the pair you will prepare (`claude` and `codex` by default; `grok` if you pass
`--engines`). The Codex reviewer defaults to `gpt-6.1-sol`, which needs Codex CLI 0.159.3 or
later.

Use a dedicated clean worktree with no secrets the providers can read. `prepare` requires
`--authorize-provider`: that flag sends the pinned diff or document, and whatever the reviewer can read
in the worktree, to those providers.

The default pair is Claude and Codex. Pass `--engines grok,codex` or `--engines claude,grok` to put Grok
in one slot. Choose the pair at prepare.

The other plugins need no CLIs or keys. persona-teardown needs `agent-browser` installed, and
reading-page's build script needs [uv](https://docs.astral.sh/uv/).

## Licence

MIT. doc-gauntlet includes Every's review kernel, and humanize-writing draws on ideas from several
open-source writing skills; see [NOTICE.md](NOTICE.md).

## Changelog

Every release, newest first, is in [CHANGELOG.md](CHANGELOG.md).
