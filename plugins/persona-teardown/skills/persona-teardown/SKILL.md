---
name: persona-teardown
description: 'Use when the user asks to tear down, walk through or review a prototype, UI kit, exported design or live screen as a persona or a panel of personas ("teardown", "rip it apart as X", "walk the prototype as the customer", "persona review"). Runs the persona-teardown SOP: cold persona agents driving agent-browser, exhaustive coverage ledger, one finding per line, consolidated into a design-tool amendment prompt.'
---

# Persona teardown

Three to five persona agents independently walk every screen, control and state of an artefact in a
real browser and report every defect one per line with a screenshot each. The orchestrator merges the
reports mechanically into one amendment prompt for the design tool. No code changes; the agents never
fix anything.

Full reasoning, the source numbers behind every rule, the survey of existing skills and what was
deliberately not adopted from them: `references/persona-teardown-sop.md`, bundled with this skill (the
research note behind it is not bundled; the SOP runs without it). Read the SOP if a rule
here looks arbitrary or the case needs adapting.

Do not use this to learn what real users think. A persona is a search heuristic for finding defects,
never evidence about people. Findings must be checkable from their own record.

## Orchestrator checklist

Gather all of these before dispatching anyone, then dispatch all agents concurrently.

- [ ] **Artefact served over HTTP**, URL written down. For a static export:
      `python3 -m http.server 8787 --directory <folder>`. Never `file://`; file-origin rules break
      fetch-based drawers and theme toggles. Load it once yourself first.
- [ ] **Screen inventory** derived from the Screens drawer, nav or index, written to a file the agents
      read. The orchestrator may read the artefact's markup to derive it; the personas may not.
- [ ] **Persona definitions**, one per agent (template below). Three is the default.
- [ ] **Named-check list**: stable IDs so all personas label the same defect identically, which is what
      lets dedupe key on an ID rather than on wording. Starting set: `DEAD-END`, `INERT-CONTROL`,
      `WRONG-CLAIM`, `COUNT-MISMATCH`, `PLACEHOLDER-LEFT-IN`, `TRUNCATED`, `CLIPPED`, `PATTERN-DRIFT`,
      `TERM-DRIFT`, `NO-FEEDBACK`, `NO-EMPTY-STATE`, `UNCONFIRMED-DESTRUCTIVE`, `UNLABELLED-CONTROL`,
      `CONTRAST-SUSPECT`, `GROUND-BREAK`, `VIEWPORT-BREAK`.
- [ ] **Source of truth for "expected"**: spec, brief, design-system rules, or the original design
      prompt. If there is none, say so in the dispatch; most findings then become questions.
- [ ] **Output paths, one directory per persona, never shared**:
      `<work>/teardown/<persona-name>/report.md` and `.../screenshots/`.
- [ ] **Viewport and ground matrix**, and how ground is switched (a visible toggle, or OS scheme).
- [ ] **Do-not-change seed list**: what is already settled.
- [ ] `agent-browser doctor --offline --quick` passes.

Independence is mechanical, not requested. Half the value sits in findings only one persona produces,
so contamination destroys what you are paying for. One `--session` and one directory per persona; no
shared scratch file; the orchestrator never shows one persona's findings to another, not even as a
format example; same protocol, different persona; no reconciliation round between agents, ever. The
screen inventory and ledger structure are shared because they describe what exists, not what was
noticed. Discard and re-run any report that echoes another's wording.

## Dispatching by engine

Persona agents run shell commands and write files, so they need a writable role, and each starts cold.

- **Claude Code:** one `general-purpose` agent per persona with an explicit `model`, all in one message.
  Never a fork.
- **Codex:** one `spawn_agent` per persona with `agent_type: "worker"` and `fork_turns: "none"` (an
  omitted `fork_turns` copies the orchestrator's whole history into the persona), all spawned before any
  `wait_agent`. `task_name` takes lowercase letters, digits and underscores only, so `busy_shopper` for
  persona `busy-shopper`; the `--session` and directory keep the hyphenated name. Wait in minutes, not
  seconds, until every persona returns; `interrupt_agent` any you give up on and record it as not
  reached. Codex's macOS sandbox cannot launch Chromium in `workspace-write`, even with network access
  and `~/.agent-browser` writable, so run the session with `--sandbox danger-full-access`
  (`sandbox_mode = "danger-full-access"` in config); spawned agents inherit it.

## Persona template

If a field does not make any design choice easier, cut it. Demographics almost never qualify.
"Never notices" and "pass bar" do the most differentiating work and are the most often omitted.

```
Persona name:        <hyphenated words, never letters or numbers, never a real person's name>
Arrived to do:       <the one concrete job they opened this artefact to do>
Vocabulary they own: <terms they use and expect to see>
Vocabulary they will not recognise: <terms that read as jargon to them>
Looks at first:      <what their eye goes to on any screen>
Never notices:       <what they are blind to; a real exclusion, honoured even over a genuine defect>
Tolerance:           <what they click past, versus what stops them cold>
Pass bar:            <one sentence in their voice: what makes this good enough to show someone>
Stakes:              <what it costs them personally if this is wrong>
```

## Per-agent protocol

Run `agent-browser skills get core --full` before the first command. Never guess a flag.

```bash
SESSION=<persona-name>; OUT=<work>/teardown/<persona-name>; mkdir -p "$OUT/screenshots"
agent-browser --session "$SESSION" set viewport 1440 900
agent-browser --session "$SESSION" set media light
agent-browser --session "$SESSION" open <base-url>
agent-browser --session "$SESSION" wait --load networkidle
agent-browser --session "$SESSION" snapshot -i
agent-browser --session "$SESSION" screenshot --annotate "$OUT/screenshots/entry-light-desktop.png"
```

**Ledger first.** Open the drawer (`find text "Screens" click`), enumerate every screen, open each,
`snapshot -i` for controls and `snapshot` for content. One row per screen by control by state by
viewport by ground. States means what this artefact actually has; do not paste a generic list. Mark
every row `reached`, `unreachable` with a reason, or `not-attempted` with a reason. No prose until
every row is marked.

```
| screen-id | element visible label | state | viewport | ground | reached/unreachable/not-attempted | note |
```

**Per screen.** Annotated screenshot. Read content, `get text @eN` for anything to be quoted. Ask the
four walkthrough questions against the persona's own goal and write a finding for every no: will they
try the right outcome, notice the control is available, associate it with the outcome they want, see
progress after acting. Then sweep mechanically: clipping, truncation, copy and typos, placeholder
content, wrong or missing labels, terminology drift against other screens, empty states, missing
feedback, unconfirmed destructive actions, contrast, alt text, unlabelled inputs, focus order.

**One control at a time**, re-snapshot after every action, refs go stale the moment the page changes:

```bash
agent-browser --session "$SESSION" click @e7
agent-browser --session "$SESSION" snapshot -i
agent-browser --session "$SESSION" get url
agent-browser --session "$SESSION" screenshot "$OUT/screenshots/<screen-id>-after-<element-slug>.png"
agent-browser --session "$SESSION" back
agent-browser --session "$SESSION" errors && agent-browser --session "$SESSION" console
```

**Both viewports, both grounds, every screen:**

```bash
agent-browser --session "$SESSION" set viewport 390 844 && agent-browser --session "$SESSION" reload
agent-browser --session "$SESSION" set media dark  && agent-browser --session "$SESSION" reload
# if the artefact has its own toggle, use it too and record which mechanism:
agent-browser --session "$SESSION" find text "Dark" click
```

A toggle that disagrees with `set media dark` is itself a finding. Close at the end:
`agent-browser --session "$SESSION" close`.

**Dead end**: prove it, never infer it. Full `snapshot`, `scroll down 2000`, snapshot again,
`screenshot --full`, then record which controls were present and what each did when clicked.
**Wrong claim**: quote the claim exactly, state what is actually true and how that was established.
**Broken state**: reproduce it once from a reload before writing it up.

### What the agent may not do

The full list goes to the agent in the dispatch skeleton's HARD RULES below. The two that carry the
most weight: **if you did not click it, you do not report it** (an expectation about what a control
would do is a question for the human, never a defect, and this is the single largest lever on report
quality), and **no target number of findings** (the ledger is the stopping condition; naming any
number makes that number the stopping condition instead). The rest: no fixing, no reading the
artefact's source, no adjective without a named element and a screenshot, no praise outside the keep
section, no paraphrased copy, no guessed measurement, no prose before the ledger is complete, no
reading another persona's output, and a three-line persona anchor restated above every screen's
ledger block.

### Finding template

```
| <check-id> | <screen-id> | <element, visible label quoted exactly; "no visible label" if none> | <action> | <observed> | <expected> (source: spec / other-screen / design-system / persona-goal / assumption) | <severity> | <screenshot path> |
```

Source `assumption` makes it a question for the human, not a defect. Record it anyway.

### Severity

| Severity | Test |
|---|---|
| `stopper` | Cannot proceed toward the goal from this screen by any visible means, or work is lost. |
| `wrong-claim` | The interface states something untrue. Ranked with stoppers regardless of visual size, because a wrong claim that reads as a copy nit gets sorted into polish and shipped. |
| `major` | Reaches the goal by a path they would call broken. No discoverable workaround. |
| `minor` | Noticed, worked around, would mention unprompted. |
| `polish` | Noticed, would not mention unless asked. |
| `question` | Not judgeable from the browser. Needs product truth or a human decision. Not a defect. |

### Closing sections, in order

1. **Coverage summary**: ledger counts, screens visited of screens enumerated, viewports and grounds.
2. **What was not reached**: one row per unreached row, with its reason. Mandatory.
3. **Not assessable from this artefact**: properties the medium cannot expose (real latency, server
   errors, true screen-reader semantics, anything behind an unimplemented control). Mandatory; without
   it the agent either omits these or fabricates them.
4. **What works and should be kept**: two to five items, element named and label quoted, same referent
   rules as a defect. The only admissible channel for praise, and the source of the do-not-change list.
5. **The persona's three biggest problems in their own words**: three short paragraphs, each naming
   screens and elements, introducing nothing not already a numbered finding above.

## Consolidation

Orchestrator alone, mechanically. Never a reconciliation round between agents: collaborative merging
measurably deflates the problem count and inflates severity.

1. **Merge** into one table with a persona column. Do not edit any finding's wording.
2. **Dedupe** by judgment, not algorithm: cluster by check ID and screen (a script may cluster; the
   orchestrator reads and decides), then collapse the same check across screens into one pattern with
   its occurrences listed. Keep every persona's severity; record the spread where they disagree.
3. **Rank** lexicographically: severity first (`stopper` and `wrong-claim`, then `major`, `minor`,
   `polish`), then persona count. Count orders within a band and never filters. Nothing is dropped for
   being a singleton; most real findings are singletons.
4. **Classify** from the record, not from taste. Expectation cites a spec, the design system or another
   screen in the kit → **fix**. Personas wanted incompatible things, or the expectation came from a
   persona goal → **variant to draw**. Expectation was assumption-sourced, or it turns on product truth
   → **question for the human**, which never enters the design-tool prompt, because a design tool asked
   an open question invents an answer and draws it.
5. **Verify** every screenshot path exists on disk and every quoted copy string is actually in the
   artefact. Anything failing is demoted to a question.
6. **Amendment prompt** sections, in order: WHAT THIS IS · WHAT CHANGED AND WHY (one paragraph per
   theme, naming the persona whose goal it blocks) · PER-SCREEN CHANGES (fixes only, element label
   quoted, change, why in one clause, severity) · COPY PASS (from-and-to pairs, both quoted verbatim)
   · DEAD-END PASS · VARIANTS TO DRAW (what is contested, the versions, the recommended default, the
   personas on each side) · DO NOT CHANGE (seed list plus every persona's kept-as-is items; the
   section most often skipped and the one that stops the tool redesigning what was fine) · ATTACHED
   (screenshot paths grouped by screen).

Hand the questions-for-the-human list to the human separately as a numbered list, each item stating what
is unknown and what decision it blocks.

## Failure modes worth remembering

Persona collapse into a generic reviewer → per-screen anchor restatement, and "never notices" as a
real exclusion. Sycophancy → no praise outside the keep section. Hallucinated findings → the
did-not-click-it rule. Impressionistic coverage → the ledger gates the prose and the not-reached
section is counted. Stopping at a plausible number → name no count. Agreement drift → separate
sessions and directories, concurrent dispatch, discard echoes. Merge deflation → orchestrator-only dedupe
only. Singletons filtered → count orders, never filters. Stale refs → re-snapshot every action.
The tool redesigning what was fine → the do-not-change section.

## Dispatch prompt skeleton

One per persona, identical except the persona block and the paths.

```
You are running a persona teardown of an artefact in a browser. Work alone. Do not read any other
agent's output and do not ask for it.

YOUR PERSONA
<paste the filled persona template>

THE ARTEFACT
Served at <base-url>. It is <one line>. Screen inventory: <path, or "derive it from the drawer">.

NAMED CHECKS
<paste the named-check list>

SOURCE OF TRUTH FOR "EXPECTED"
<path>, or: "There is no spec. Mark nearly every expectation as assumption-sourced and expect most
of your findings to be questions."

SCOPE
Viewports: <1440x900 and 390x844>. Grounds: <light and dark>, switched by <toggle label, or the OS
colour scheme via set media>.

OUTPUT
Report: <work>/teardown/<persona-name>/report.md
Screenshots: <work>/teardown/<persona-name>/screenshots/
Use --session <persona-name> on every agent-browser command.
Scratch files only under a subfolder named after the persona, never at a shared scratch root.

PROCEDURE
Follow references/persona-teardown-sop.md (bundled with this skill), section "Per-agent walkthrough
protocol", exactly. Run `agent-browser skills get core --full` before your first command and never
guess a flag.

In short: build the coverage ledger first from the drawer and from `snapshot -i` on every screen
(every screen, every control, every state, both viewports, both grounds); mark every row reached,
unreachable or not-attempted; walk every screen asking the four walkthrough questions against your
own goal, then sweep mechanically; one control at a time, re-snapshot after every action; screenshot
every finding; write findings one per line in the fixed template with a named check ID and a
severity; then coverage summary, what you did not reach, what was not assessable, two to five things
that work and should be kept, and your three biggest problems in your own words.

HARD RULES
- Never click `mailto:`, `tel:`, calendar-invite or `.ics` links. Read the target with
  `get attr @eN href` and record it: the operating system hands those links to desktop apps even
  from a headless browser.
- If you did not click it, you do not report it. An expectation about what a control would do is a
  question for the human, never a defect.
- No adjective without a named element and a screenshot.
- No praise outside the "what works and should be kept" section, and not even there without naming
  the element.
- Quote copy verbatim. Never paraphrase it.
- Never guess a value you could have measured with `get styles`, `get text` or `get value`. Flag
  anything unmeasurable, such as a contrast ratio, for verification rather than asserting it.
- Do not read the artefact's source, markup, CSS or JavaScript.
- Do not fix anything and do not propose an implementation.
- No summary, conclusion or top-three until every ledger row is marked.
- There is no target number of findings. The ledger is your stopping condition.
- Above every screen's ledger block, restate: who you are and what you came to do; your pass bar;
  "I did not click it, I do not report it."

When done, close your session and report back only the path to your report, your coverage counts,
and your findings count by severity.
```

## Attribution

Four rules borrowed from `EliaAlberti/ux-audit-skill` (MIT,
https://github.com/EliaAlberti/ux-audit-skill): named checks with stable IDs, the not-assessable
bucket, positive findings as the source of the do-not-change list, and flagging borderline
measurements rather than asserting them. Two from `tommyjepsen/awesome-ux-skills`: cut any persona
field that makes no design choice easier (`ux-personas`), and never guess a value you could have
measured (`design-analysis`).
