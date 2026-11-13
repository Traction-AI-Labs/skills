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

- **gauntlet 0.7.0 and doc-gauntlet 0.6.2** (14 November 2026). gauntlet: a review budget by kind of change (rounds
  per change, one raise past it for a demonstrated consequence, `FIXES CHECKED` after the last round, a recurrence
  ladder for a class of finding that keeps returning); a round-1 gate that checks for a pre-review and a run-once, with
  an enforcement list (`enforce.tsv`) that turns the refusals on per repository and everything else a warning;
  `--run-once` can run a repository's own CI; a standing approval is recognised when main is brought in; a finding is
  dropped or downgraded only through `dispose` with a passing test; a large round can split its reviewers by file group
  (`prepare --group`); the changed-line count leaves out tests, generated files and documentation, and a large round 1
  is a note, never a refusal. doc-gauntlet: a document's round count defers to the repository's own review budget,
  and Grok may substitute for either engine while it has usage. This refresh follows the source, so three
  small fixes made only in these copies for 0.6.0 are not in it (a symlinked home folder denied by its target, test
  fixtures that own their home and a launchctl stand-in, and the timeout check before the leg lock); they return
  once the source carries them.
- **ruling-page 0.3.1 and reading-page 0.3.1** (13 November 2026). A ruling page on a design decision shows each
  option as an annotated picture, never in words alone. A reading page whose markdown opens with an HTML comment
  (a provenance note, say) still takes its title from the first heading, and the comment no longer shows as text.
- **ruling-page 0.3.0 and reading-page 0.3.0** (12 November 2026). Pages say whether they need the reader. A ruling
  page opens with a coral "This needs you" banner while it is live; once answered or replaced, `STATE` in its data
  turns the banner teal with a tick or grey with an arrow and a link to the page that took over, switches the answer
  controls off and folds the old cards, still readable, under "Show the old cards". A reading page takes front-matter
  `status`: `live`, `reference`, `replaced` (the whole old body folds) or `partly-replaced` (each section is marked
  as still standing or replaced, and replaced ones fold). Pages without a state render exactly as before.
- **call-prep 0.3.0** (12 November 2026). Anything the caller sends, pastes or shares during the call is now a "Send
  now" block in the beat where they send it, with its own Copy button, before the line that says it has gone. A new
  check, `scripts/check_prep.py`, fails a page where a line says something has been sent with no send before it in
  the same beat, and lists the sends by beat for the handover, which now names them first.
- **reading-page 0.2.4** (12 November 2026). Inline code in prose, the standfirst and table cells never renders under
  11px, so it stays readable at phone width.
- **doc-gauntlet 0.6.1** (12 November 2026). The client-draft review's worth-asking test now covers every message
  to a colleague that carries a question or ask, not only asks they will relay to a client; a message that gets no
  reviewer has its author run the same tests.
- **reading-page 0.2.3** (9 November 2026). A code block inside a list item or a callout now scrolls inside its own box
  with JavaScript off, as top-level code blocks already did; before, a long line in one ran past the right edge at phone
  width. The overflow fixture gains a nested-fence case, tests now guard the nested wrapper, and the page-script
  test matches only a script tag at the start of a line.
- **ruling-page 0.2.2 and reading-page 0.2.2** (6 November 2026). ruling-page: a card can carry an optional
  `short` label, which the rail, the card head and the progress bar show in place of a long `id` (a tracker key
  such as `pricing-2026-K1` shows as `K1`); answers stay saved and copied under `id`. Both ruling templates carry
  the change, so their shared engine stays word for word the same. reading-page: code inside a source note never
  renders under 11.5px, so it stays readable at phone width.
- **gauntlet 0.6.1 and ruling-page 0.2.1** (4 November 2026). gauntlet: reviewers question the value of every
  hold, switch and timer the diff adds or keeps on a path it touches, and report as material one that names neither
  the failure it prevents nor the rule or ruling it implements, or that blocks more than that failure needs, saying what it
  blocks in normal use and the change that removes or narrows it. ruling-page: a pasted line whose note asks a
  question is not yet a go, whatever option it picks; answer the question first, saying what it means for the
  decision, and act only after the reply. A line passed on to another thread carries its question, and that
  thread waits too.

- **gauntlet 0.6.0, doc-gauntlet 0.6.0 and reading-page 0.2.1** (3 November 2026). gauntlet and doc-gauntlet:
  Grok legs run without a forced output schema (it let Grok answer without opening a file), keep its JSON output
  as the record, and a one-turn reply fails the leg; the Grok sandbox denies only instruction files that exist and
  never a symlink; `--prior-findings` can be given more than once; a leg that lands or is retried after the round
  was archived gets its own archive; reviewers are told to read every changed file's hunks and trace every existing
  user of what changed, and to report every defect they trace. gauntlet also treats `--exclude` paths literally
  and adds `collect --started-only` (record a prepared leg you never started as not run) and a locked `clean`.
  doc-gauntlet: a breadth-only round is archived, and the client-draft review in `derivation-ledger.md` gains the
  rules on naming the fault and never the sentence, the final figures check, read-only reviewers, deriving what
  someone said from their own words, one round on a short message, and a reviewer's tool-call budget.
  reading-page: the "decision" callout also matches "needs the approver's go", "needs <name>'s ruling" and
  similar; the browser check also resizes a desktop page to phone width and fails if anything covers the title.

- **ruling-page 0.2.0, reading-page 0.2.0 and call-prep 0.2.0** (2 November 2026). One shared look across
  the three pages, with no one-sided accents: state shows as a tinted fill, a full outline or a label.
  ruling-page: a new engine with a brief at the top, a progress strip, a contents rail and a status per
  card; optional downsides and "what would change my pick" lines; cards with several questions, "choose
  any" options and typed answers; your pick drawn dashed until confirmed; Copy my answers gives one block
  per card and lists what was left unanswered; answers saved by 0.1 pages carry over. The open-questions
  variant runs on the same engine. Two static checks for template changes, `edges.py` and `same.py`.
  reading-page: callouts as tinted panels with a label chip, a link on every heading and footnote
  previews; the bottom-line box carries on in its paragraph after the bold opening sentence. call-prep:
  a "What you send" panel with copy buttons, a call clock, beat-done and focus keys, script size, and
  each beat ends with what comes next; the figures check gets the sources and a value-free list
  of the figures, never the draft, and runs on any client call whose script quotes a figure.
- **call-prep 0.1.3** (26 October 2026). A prep is done only when everything the call promises is ready: each
  artefact it sends or shows is written for the counterpart, independently reviewed and send-ready before the call,
  listed in a "What you send" panel at the top, with any part that depends on the call named. Asks are explained in
  plain words in their beat, figures framed as agreed are attributed from the transcript, and the handover leads
  with a readiness count. The review now covers every handed-over artefact whatever the call's topic, plus an
  adversarial test for instructions the counterpart will run.
- **humanize-writing 0.2.0** (25 October 2026). Rewritten from scratch as an editor that adds nothing the draft
  did not say. It names the genre, the writer and the reader first, targets the templates current models write in
  (genre skeletons, slogan pairs, payoff clauses, staged feeling, a bold label on every step) with five sentence
  tests, then says each remaining point the way the writer would say it to that reader, and checks every edit
  against the draft in both directions. Technical documents keep their steps, headings, commands and figures and
  lose their decoration; articles, cover letters and bios get their own rules. The personality pass and the
  banned list are gone; a pattern catalogue and one worked edit per genre replace them. Credits the open-source
  skills whose ideas it draws on.
- **go-deeper 0.1.0** (25 October 2026). First release: the depth prompt with its four-part analysis and
  rewritten prompt, plus altitude, range and the self-efficacy notes from Felix Rieseberg's essay. Upload-zip
  builder included.
- **humanize-writing 0.1.0** (24 October 2026). First release: the editing rules, the content, language and style
  patterns to remove, the personality pass, and a banned list of words, phrases and emojis with plain
  replacements. Upload-zip builder included.
- **call-prep 0.1.2** (21 October 2026). The skill and its template now agree: the post-call section is
  "After the call", the full shape is the core plus every section whose condition the call meets, and unused
  template sections are deleted with their nav links and keys. A number in a quoted line needs a source or the
  *unverified* label, done beats on a part-2 page sit outside the beat cap, the call's length comes from the
  calendar, and the `g` key hides only the guard line, which never makes the window safe to share.
- **call-prep 0.1.1** (21 October 2026). Quoted lines read the way the caller talks across a table. Times,
  dates and addresses stay as written ("7am", "14 Oct", an email address), each beat is quoted in short
  blocks, and the skill lists the tells to check for after writing: spoken colons, lines that announce what
  is coming, verbless headlines, runs of short punchy sentences, aphorisms and validation openers. Where a
  recording of the caller exists, it reads a few minutes of it first.
- **gauntlet 0.5.1 and doc-gauntlet 0.5.1** (1 October 2026). Each plugin README now matches its skill:
  gauntlet documents `prepare --timeout-seconds` and the per-leg `./diff.patch`; doc-gauntlet describes the
  error list and the sparring memo. Documentation only.
- **gauntlet 0.5.0 and doc-gauntlet 0.5.0** (1 October 2026). The Codex reviewer defaults to `gpt-6.1-sol`
  in every profile (fast used `gpt-5.6-terra`, balanced and deep `gpt-5.6-sol`), and doc-gauntlet's Codex
  default moves with it. Needs Codex CLI 0.159.3 or later: older CLIs reject the model on a ChatGPT account.
  `--codex-model` still picks another.
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
