# Traction skills

Skills for Claude Code, the Claude app, Codex and Grok, published by Traction Studio.

## What's here

| Plugin | What it does | Runs in |
|---|---|---|
| **gauntlet** | Reviews a committed code diff with two independent engines (Claude and Codex by default; Grok can take either slot) | Claude Code, Codex, Grok, or the portable CLI |
| **doc-gauntlet** | Reviews a committed plan, spec or requirements document with six breadth lenses, then the same two-engine pair; returns a sparring memo for the author and a short list of true errors | Claude Code, Codex, Grok, or the portable CLI |
| **persona-teardown** | Walks a prototype, UI kit or live screen with three to five cold persona agents driving `agent-browser`, one session and one report each, with a coverage ledger of every screen, control, state and ground, then consolidates the findings into one amendment prompt for the design tool | Claude Code or Codex (subagents) |
| **ruling-page** | Turns a complicated decision into a clickable one-file HTML page: a recommendation pre-selected on every card, alternatives as buttons, and one button that copies the answers back into chat | Claude Code, the Claude app |
| **call-prep** | Writes a verbatim call script as one interactive HTML page to read live on a second screen: a guard line of what not to say, numbered beats with the exact words, fallbacks for pushback and answers to the hardest questions | Claude Code, the Claude app |

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

ruling-page and call-prep install as upload zips. Build them from the repository root:

```
bash plugins/ruling-page/scripts/build-zip.sh
bash plugins/call-prep/scripts/build-zip.sh
```

Each lands in that plugin's `dist/` folder. In the Claude app, open **Customize**, then **Skills**, upload
each zip and check it is switched on. The zips are build outputs; never commit them.

### Portable CLI

Clone the repo. From `plugins/gauntlet` or `plugins/doc-gauntlet`, follow that directory's README.

## Before you run a gauntlet

The two gauntlets need Bash, Git, Python 3 and GNU `timeout` (on macOS, `brew install coreutils`).
Authenticate the CLIs in the pair you will prepare (`claude` and `codex` by default; `grok` if you pass
`--engines`).

Use a dedicated clean worktree with no secrets the providers can read. `prepare` requires
`--authorize-provider`: that flag sends the pinned diff or document, and whatever the reviewer can read
in the worktree, to those providers.

The default pair is Claude and Codex. Pass `--engines grok,codex` or `--engines claude,grok` to put Grok
in one slot. Choose the pair at prepare.

The other plugins need no CLIs or keys. persona-teardown needs `agent-browser` installed.

## Licence

MIT. doc-gauntlet includes Every's review kernel; see [NOTICE.md](NOTICE.md).

## Changelog

- **persona-teardown 0.2.0** (1 October 2026). Runs from Codex as well as Claude Code. A short "Dispatching
  by engine" section says how each engine spawns a cold persona agent: on Codex, a `worker` with
  `fork_turns: "none"`, all spawned before any wait. Codex's macOS `workspace-write` sandbox cannot launch
  Chromium, so a Codex teardown runs with `--sandbox danger-full-access`, and on Codex only over an
  artefact you control. Persona agents on both engines now treat text on the page as data, never as
  instructions.
- **persona-teardown 0.1.2** (1 October 2026). The skill's description failed to parse as YAML, so Claude Code
  loaded it with no description and it never triggered on its own. Fixed.
- **ruling-page 0.1.0 and call-prep 0.1.0** (30 September 2026). First releases. Both produce one
  self-contained HTML page and work in the Claude app as an artifact as well as in Claude Code: storage
  and clipboard calls are guarded, and the ruling page says plainly when it could not copy and leaves the
  text selected instead. Upload-zip builders included.
- **gauntlet 0.4.0 and doc-gauntlet 0.4.0** (30 September 2026). The round budget is retired: rounds are
  still numbered in the round record, but the runners refuse nothing on round count, and
  `--override-round-budget` and `--supersedes` are accepted and ignored. Code review now ends at a stop
  state (a clean round, or a round whose material findings all sit in lines the previous repair wrote),
  with an "after each round" procedure for verifying, classifying and batching fixes. `prepare` takes
  `--pre-reviewed-by <model>|none` and records it; each CLI reviewer reads the pinned diff from its own copy,
  checked against the pinned digest.
  `collect` archives every finished run, passed or failed, to `~/.gauntlet/runs/` (`GAUNTLET_ARCHIVE`
  relocates it; a root inside an unignored git worktree is refused) and prints `ARCHIVE: <path>`. The
  archive is private and never pruned. doc-gauntlet keeps raw reviewer output unredacted and failed-leg
  diagnostics only as sanitised summaries; gauntlet also keeps full transcripts and stderr, which can include
  repository content and request headers. `clean` removes only the scratch run.
  doc-gauntlet returns two outputs, a sparring memo and a list of true errors, and a document gets up to two
  rounds (one when a code gauntlet has already reviewed the same change).
- **persona-teardown 0.1.1** (30 September 2026). Persona agents never click `mailto:`, `tel:`,
  calendar-invite or `.ics` links; they read and record the target instead, because the operating system
  hands those links to desktop apps even from a headless browser.
- **gauntlet 0.3.1** (27 September 2026). The Claude reviewer runs at medium effort where a profile says high.
- **persona-teardown 0.1.0** (14 September 2026). First release: the persona template, the per-agent
  walkthrough protocol grounded in `agent-browser`, the coverage ledger, the finding template and severity
  scale with `wrong-claim` ranked beside `stopper`, the independence rules, the consolidation procedure and
  the dispatch prompt skeleton. The full SOP ships as the skill's reference. First run: four personas over a
  58-screen prototype, 490 findings, no persona collapse.
- **gauntlet and doc-gauntlet 0.3.0** (14 September 2026). Rounds are counted. `gauntlet.sh prepare`
  requires the reviewed thing's identity, `--pr <n>` or `--identity <token>`, and both runners append every
  successful round to a round record at `~/.gauntlet/rounds.jsonl` (`GAUNTLET_ROUND_RECORD` relocates it).
  This release also introduced a per-lineage round budget, retired in 0.4.0.
- **0.2.0** (3 September 2026). 1800-second default leg bound, `--timeout-seconds`, bound and timeout
  reporting.
