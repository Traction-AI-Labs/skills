# Persona teardown SOP

Project-agnostic procedure for running a panel of persona agents through a prototype or live UI with
`agent-browser`, and consolidating what they find into one amendment prompt for a design tool.

Reasoning, sources and the numbers behind every rule here:
the research note behind it (kept in the author's learnings repo). This SOP is written to be
runnable without reading it.

Prior art: nothing published as at 14 Sep 2026 does the multi-persona, browser-driven,
coverage-ledgered version of this. The closest is `EliaAlberti/ux-audit-skill`
(https://github.com/EliaAlberti/ux-audit-skill, MIT), a single-evaluator heuristic audit from static
screenshots, and its evidence discipline is better tested than anything invented here, so four of its
rules are borrowed below and attributed inline. Two more come from
`tommyjepsen/awesome-ux-skills`. The research note's "Existing skills and plugins" section has the
full survey and says what was deliberately not adopted.

## When to use it and what it produces

Use it when an artefact exists and needs to be attacked before it goes anywhere: an exported clickable
prototype, a UI kit, a design-tool export, a staging build, a single screen. Three to five persona
agents each independently walk every screen, every control and every state, and report defects one per
line with a screenshot for each. The orchestrator merges the reports mechanically and emits one
amendment prompt for the design tool. It produces three independent teardown reports plus one
amendment prompt, and it produces no code changes; the persona agents never fix anything. Do not use
it to learn what real users think, because persona output is a search heuristic for finding defects,
not evidence about people.

## Inputs the orchestrator must have

Gather all of these before dispatching anyone. A missing input is not a thing to work around; it
changes the output quality more than any prompting choice.

1. **The artefact served over HTTP**, with the base URL written down. For a static export, serve the
   folder rather than opening `file://` paths, because file-origin restrictions break fetch-based
   drawers and theme toggles: `python3 -m http.server 8787 --directory <folder>` then
   `http://localhost:8787/<entry>.html`. Confirm it loads once yourself before dispatching.
2. **A screen inventory, or a command that derives one.** If the artefact has a Screens drawer, nav or
   index, derive the list from it rather than guessing. Deriving it by reading the artefact's own markup
   is allowed for the orchestrator and forbidden to the persona agents. Write the list to a file the
   agents read.
3. **Persona definitions**, one per agent, in the template below. Three is the working default.
4. **A source of truth for "expected"** so findings can cite something: the spec, PRD, design brief,
   the design system's own rules, or the original design-tool prompt. If there is no source of truth,
   say so explicitly in the dispatch, because the agents must then mark nearly every expectation as
   assumption-sourced, and assumption-sourced findings become questions rather than fixes.
5. **Output paths**, one directory per persona, never shared:
   `<work>/teardown/<persona-name>/report.md` and `<work>/teardown/<persona-name>/screenshots/`.
6. **The viewport and ground matrix**: which widths and which of light and dark are in scope, and how
   the artefact switches ground (a visible toggle, or the OS colour scheme).
7. **The do-not-change list**: what in the artefact is settled and must survive the amendment round.
   Seed it with whatever the human already knows is fixed; the personas' positive findings extend it.
8. **The named-check list**: a short shared vocabulary of recurring defect types, each with a stable
   ID, handed to every persona so the same defect is labelled identically by all of them. Borrowed from
   `EliaAlberti/ux-audit-skill`, where its purpose is consistency across audits; here its purpose is
   that the consolidation step can key on an ID instead of hoping three agents chose the same words.
   A workable starting set, extend per project: `DEAD-END`, `INERT-CONTROL`, `WRONG-CLAIM`,
   `COUNT-MISMATCH`, `PLACEHOLDER-LEFT-IN`, `TRUNCATED`, `CLIPPED`, `PATTERN-DRIFT` (the same thing
   behaves differently on two screens), `TERM-DRIFT` (the same thing is named differently on two
   screens), `NO-FEEDBACK`, `NO-EMPTY-STATE`, `UNCONFIRMED-DESTRUCTIVE`, `UNLABELLED-CONTROL`,
   `CONTRAST-SUSPECT`, `GROUND-BREAK` (renders wrong in one of light or dark), `VIEWPORT-BREAK`.
   An agent that needs a type not on the list coins one in the same shape and says it is new.

Check `agent-browser doctor --offline --quick` once before dispatching. A broken CLI wastes three
agents rather than one.

## Persona definition template

Every field must be able to change what the agent reports. As the `ux-personas` skill in
`tommyjepsen/awesome-ux-skills` puts it: if a field does not make any design choice easier, cut it.
Demographics almost never pass that test. The two fields that do most of the differentiating work are
"never notices" and "pass bar", and they are the two most often left out.

```
Persona name:        <short hyphenated words, no letters or numbers>
Arrived to do:       <the one concrete job they opened this artefact to do>
Vocabulary they own: <terms they use and expect to see>
Vocabulary they will not recognise: <terms that will read as jargon or noise to them>
Looks at first:      <what their eye goes to on any screen, before anything else>
Never notices:       <what they are constitutionally blind to; be specific and be willing to
                      exclude things that are genuinely defects>
Tolerance:           <what they click past without comment, versus what stops them cold>
Pass bar:            <one sentence in their own voice: what has to be true for them to say this is
                      good enough to show someone>
Stakes:              <what it costs them personally if this artefact is wrong>
```

Filled example, generic domain operator:

```
Persona name:        careful-file-operator
Arrived to do:       Take one real case file through from intake to the point where it is ready to
                     hand on, and satisfy myself nothing was silently dropped on the way.
Vocabulary they own: file, case, checklist, outstanding items, chase, sign-off, audit trail,
                     "who touched this last".
Vocabulary they will not recognise: pipeline, ingestion, artefact, orchestration, entity,
                     confidence score, embedding.
Looks at first:      counts and statuses. How many items, how many outstanding, what state is this
                     in, and does that number match what I just did.
Never notices:       typography, spacing, colour choices, icon style, animation, dark mode
                     rendering. Will not comment on aesthetics even when asked.
Tolerance:           will click past an ugly screen without comment; stops cold at a number that
                     does not reconcile, a status with no explanation, or anything that looks like
                     it silently discarded work.
Pass bar:            "I can see every outstanding item on one screen, and I can tell you who did
                     the last thing to this file and when."
Stakes:              a dropped item on a real file is their name against the mistake.
```

Never use a real person's name as a persona name, and never write a persona as a caricature of a
named colleague or client.

## Per-agent walkthrough protocol

This is the procedure the persona agent follows. Give it to the agent verbatim, with the placeholders
filled. Every browser command below is from the `agent-browser` reference; if a command is needed that
is not here, the agent runs `agent-browser skills get core --full` and reads it, and never guesses a
flag.

### Standing rules, restated at the top of every screen's ledger entry

Copy these three lines into the report above each screen's block. That restatement is the anti-drift
mechanism; it costs a line and makes drift visible in the artefact rather than hidden in context.

- I am `<persona-name>`. I arrived to `<arrived to do>`. My pass bar is `<pass bar>`.
- I did not click it, I do not report it.
- No praise without a named element.

### Setup

```bash
SESSION=<persona-name>
OUT=<work>/teardown/<persona-name>
mkdir -p "$OUT/screenshots"

agent-browser --session "$SESSION" set viewport 1440 900
agent-browser --session "$SESSION" set media light
agent-browser --session "$SESSION" open <base-url>
agent-browser --session "$SESSION" wait --load networkidle
agent-browser --session "$SESSION" snapshot -i
agent-browser --session "$SESSION" screenshot --annotate "$OUT/screenshots/entry-light-desktop.png"
```

The `--session <persona-name>` is mandatory and is what keeps the three agents from sharing browser
state. Refs (`@e1`, `@e2`, ...) are reassigned on every snapshot and go stale the moment the page
changes, so re-snapshot after every action that changes anything.

### Build the coverage ledger first, before reporting anything

Write the ledger into the report before the first finding. No conclusions, no summary and no
top-three may be written until every row is marked.

1. Open the Screens drawer or nav and enumerate every entry:
   ```bash
   agent-browser --session "$SESSION" snapshot -i
   # or, if the drawer has to be opened first:
   agent-browser --session "$SESSION" find text "Screens" click
   agent-browser --session "$SESSION" snapshot -i
   ```
2. For each screen entry, open it and enumerate its controls:
   ```bash
   agent-browser --session "$SESSION" click @eN
   agent-browser --session "$SESSION" snapshot -i          # every interactive element
   agent-browser --session "$SESSION" snapshot             # the content, for copy checks
   ```
3. Write one ledger row per cell of screen by control by state by viewport by ground. States means
   whatever this artefact actually has: default, hover, focus, disabled, loading, empty, populated,
   overflow, error, success, selected. Do not paste a generic state list; enumerate what is there.
4. Mark every row `reached`, `unreachable` with the reason, or `not-attempted` with the reason. A row
   left unmarked is a failed run.

Ledger row format, one line each:

```
| screen-id | element visible label | state | viewport | ground | reached / unreachable / not-attempted | note |
```

### Walking each screen

Per screen, in this order:

1. Screenshot the screen as arrived at, annotated:
   `agent-browser --session "$SESSION" screenshot --annotate "$OUT/screenshots/<screen-id>-<ground>-<viewport>.png"`
2. Read the content: `agent-browser --session "$SESSION" snapshot` and
   `agent-browser --session "$SESSION" get text @eN` for anything that needs quoting exactly.
3. Ask the four walkthrough questions against the persona's own goal, and write a finding for any
   answer that is no:
   - Will this persona try to achieve the right outcome here?
   - Will they notice that the correct control is available?
   - Will they associate that control with the outcome they want?
   - After acting, will they see that progress was made?
4. Then sweep the screen mechanically for the rest: layout and clipping, overlapping or truncated text,
   copy and typos, placeholder or lorem content left in, wrong or missing labels, inconsistent
   terminology against the other screens, empty states, missing feedback, destructive actions without
   confirmation, contrast, missing alt text, unlabelled inputs, focus order.
5. **One control at a time.** Click exactly one control, re-snapshot, record what changed, then either
   return or proceed. Never chain two clicks before a snapshot, because the report then cannot say
   which click caused what.
   ```bash
   agent-browser --session "$SESSION" click @e7
   agent-browser --session "$SESSION" snapshot -i
   agent-browser --session "$SESSION" get url
   agent-browser --session "$SESSION" screenshot "$OUT/screenshots/<screen-id>-after-<element-slug>.png"
   agent-browser --session "$SESSION" back      # or click the drawer entry again
   ```
6. Check the console after any screen that does anything:
   ```bash
   agent-browser --session "$SESSION" errors
   agent-browser --session "$SESSION" console
   ```
7. Both viewports, both grounds, for every screen:
   ```bash
   agent-browser --session "$SESSION" set viewport 390 844
   agent-browser --session "$SESSION" reload
   agent-browser --session "$SESSION" set media dark
   agent-browser --session "$SESSION" reload
   ```
   If the artefact carries its own light and dark toggle rather than following the OS scheme, use it,
   and record which mechanism was used: `agent-browser --session "$SESSION" find text "Dark" click`.
   Check both mechanisms if both exist; a toggle that disagrees with `set media dark` is itself a
   finding.
8. Close down at the end: `agent-browser --session "$SESSION" close`.

### The three things that need a specific handling

**A dead end.** A screen with no visible way to proceed toward the goal and no visible way back.
Do not infer it. Prove it: snapshot the full tree (`snapshot`, not `snapshot -i`), scroll to the bottom
(`scroll down 2000` then snapshot again) to rule out an offscreen control, screenshot full page
(`screenshot --full`), then record it as a stopper and state in the observed field exactly which
controls were present and what each did when clicked.

**A wrong claim.** The interface asserts something untrue: a count that does not match what is on
screen, a status that contradicts the last action, a label naming a thing that is not there, a promise
the product does not ship. Quote the claim exactly, state what is actually true and how that was
established, and rank it as a wrong claim regardless of how small it looks. A wrong claim that reads
as a copy nit gets sorted into polish and shipped, which is the exact failure this category exists to
prevent.

**A broken state.** The UI is in a state it should not be able to reach: two things selected that are
mutually exclusive, a modal that will not close, content rendered over other content. Verify it
reproduces at least once by repeating the action sequence from a reload before writing it up.

### What the agent may not do

- May not fix anything, edit anything, or suggest an implementation.
- May not read the artefact's source, markup, CSS or JavaScript. The walk is from the browser only.
  The screen inventory is derived from the drawer as rendered, not from the file.
- May not report anything it did not click. An expectation about what a control would do is a question
  for the human, never a defect. This single rule is the largest lever on report quality.
- May not use an adjective without a named element and a screenshot attached. "Cramped" about a named
  card with a screenshot is fine. "Cramped" about a screen is not.
- May not praise anything outside the "what works and should be kept" section, and not even there
  without naming the element and quoting its label.
- May not paraphrase copy. Copy claims quote the copy verbatim.
- May not write a summary, a conclusion or a top-three before every ledger row is marked.
- May not read another persona's report, directory or session, and may not ask for one.
- May not stop at a count. There is no target number of findings; the stopping condition is the ledger.

### Finding template

One finding, one line, fixed fields, pipe-separated:

```
| <check-id> | <screen-id> | <element, quoted by its visible label exactly as rendered; "no visible label" if none> | <action taken> | <what was observed> | <what was expected> (source: spec / other-screen / design-system / persona-goal / assumption) | <severity> | <screenshot path> |
```

The expectation source field is load-bearing. If the source is `assumption`, the finding is
automatically a question for the human and not a defect. Record it anyway; do not suppress it.

The check ID comes from the named-check list in the orchestrator's inputs. Use the list's ID wherever
one fits; coin a new one in the same shape and mark it `(new)` only when nothing fits.

Never guess a value that could have been measured. `agent-browser get styles <sel>`,
`get text @eN` and `get value @eN` exist, so a font size, a colour, a computed property or a copy
string is measured or it is not claimed. Rule adapted from the `design-analysis` skill in
`tommyjepsen/awesome-ux-skills`. For anything genuinely borderline that the tool cannot settle,
notably a contrast ratio, write the finding as `CONTRAST-SUSPECT ... verify with a contrast checker`
rather than asserting a ratio. Rule from `EliaAlberti/ux-audit-skill`.

### Severity scale

Named in words so a level is never mistaken for a count. Apply the behavioural test, not a feeling.

| Severity | Test |
|---|---|
| `stopper` | This persona cannot proceed toward their goal from this screen by any visible means, or the artefact loses their work. |
| `wrong-claim` | The interface states something that is not true. Ranked with stoppers regardless of visual size. |
| `major` | The persona reaches the goal, but by a path they would describe as broken. No reasonable workaround, or the workaround is not discoverable. |
| `minor` | Noticed, worked around, would mention it unprompted. |
| `polish` | Noticed, would not mention unless asked. |
| `question` | Cannot be judged from the browser. Needs product truth, a spec, or a human decision. Not a defect. |

### Closing sections of the report, in this order

1. **Coverage summary.** Counts from the ledger: rows total, reached, unreachable, not-attempted.
   Screens visited out of screens enumerated. Viewports and grounds actually covered.
2. **What was not reached**, one row per unreached ledger row, each with its reason. A report with no
   such section is treated as incomplete, not as complete coverage.
3. **Not assessable from this artefact.** Distinct from not reached, and mandatory. Properties this
   medium cannot expose, named rather than guessed: real latency, server and network errors, true
   screen-reader semantics, print, long-session behaviour, anything behind an unimplemented control in
   a static export. Borrowed from `EliaAlberti/ux-audit-skill`, whose equivalent section stops the
   agent inventing behaviour it had no way to observe. Without this bucket an agent either omits these
   or fabricates them.
4. **What works and should be kept.** Two to five items, each naming an element and quoting its label,
   under exactly the same referent and screenshot rules as a defect. Borrowed from
   `EliaAlberti/ux-audit-skill`. This is the only channel through which praise is admissible, and it
   is what the orchestrator builds the do-not-change section from, so a teardown that skips it forces
   the orchestrator to guess what was fine.
5. **The persona's three biggest problems, in their own words.** Three short paragraphs in the
   persona's voice, each naming the screens and elements behind it. This section is the only place
   unfalsifiable voice is allowed, it sits below the ledger, and it may not introduce a problem that
   is not already a numbered finding above.

## Independence rules for the orchestrator

Half the value of a panel sits in findings only one persona will ever produce, so contamination
destroys exactly the part being paid for. LLM agents anchor harder on a peer's report than humans do,
and the cheap way for an agent to satisfy the task is to agree, so independence has to be mechanical
rather than requested.

- One `--session <persona-name>` per agent. Never a shared session.
- One output directory per agent. No shared scratch file, no shared findings file, no shared log.
- The orchestrator never shows one persona's findings to another, in the dispatch or in any follow-up
  message, not even as an example of format.
- Same protocol, same ledger, different persona. The protocol is identical across agents by design; the
  persona is the only variable.
- The coverage ledger structure and the screen inventory are shared, because they describe what exists
  rather than what was noticed. Sharing what exists while isolating what was noticed is the whole trick,
  and it is also what makes the reports mergeable.
- Dispatch all agents concurrently. Sequential dispatch invites passing the earlier report along as
  context.
- No reconciliation round between agents, ever. Collaborative merging measurably deflates the problem
  count and inflates severity, because evaluators give way under persuasion. The merge is the
  orchestrator's job alone.
- If an agent returns a report that quotes another persona or matches another's wording suspiciously,
  discard it and re-run that persona in a fresh session.

## Consolidation procedure

Done by the orchestrator alone, mechanically.

1. **Merge.** Concatenate all findings into one table, adding a persona column. Do not edit any
   finding's wording.
2. **Dedupe** by the orchestrator's judgment, not by an algorithm. Four agents describe one element four ways, so an exact match on (check-id, screen-id, element) rarely fires; use the check ID and the screen as the clustering key, then read the clustered rows and decide which are one defect. A script that clusters is a reading aid; the merge is a judgment the orchestrator makes and can defend. Two levels: the same defect on the same element of the same screen is one row; the same check across screens (three personas hitting `TERM-DRIFT` on three screens) is one cross-screen pattern with the per-screen occurrences listed under it, which is what turns a list into a theme the design tool can act on. Keep every persona's severity separately; do not average them and do not collapse to one. Where severities disagree, record the spread, because a finding one persona calls a stopper and two call polish is a more interesting object than either verdict.
3. **Rank** lexicographically: severity first (`stopper` and `wrong-claim` together at the top, then
   `major`, `minor`, `polish`), then the number of personas who hit it. Count orders within a severity
   band and never filters. Nothing is dropped for being a singleton; most real findings are singletons.
4. **Classify** each row from the record, not from taste:
   - **fix**: the expectation cites a spec, the design system, or another screen in the same artefact.
   - **variant to draw**: two personas wanted incompatible things, or the expectation came from a
     persona goal rather than a source of truth. The design tool draws both and a human picks.
   - **question for the human**: the expectation was assumption-sourced, or the finding turns on
     product truth the artefact cannot settle. These never go to the design tool. A design tool asked
     an open question invents an answer and draws it.
5. **Verify before writing the prompt.** Every screenshot path referenced exists on disk. Every quoted
   copy string is actually present in the artefact. Any finding failing either check is demoted to a
   question.
6. **Write the amendment prompt** in this structure:

```
WHAT THIS IS
  One paragraph: the artefact, that three personas walked it independently, and that the changes
  below are ranked by severity then by how many personas hit each one.

WHAT CHANGED AND WHY
  One paragraph per theme, not per finding. The pattern behind a cluster of findings, and the
  persona whose goal it blocks.

PER-SCREEN CHANGES
  One block per screen, screens in the artefact's own order.
    <screen-id>
      - <element, quoted label>: <change>. <why, one clause, naming the persona.> [severity]
  Fixes only. Variants and questions do not appear here.

COPY PASS
  Every copy change as a from-and-to pair, both quoted verbatim. Never a description of the change.

DEAD-END PASS
  Every stopper as: screen, the control that was missing or inert, and where the persona needed to
  get to.

VARIANTS TO DRAW
  One block per contested decision: what is contested, the two or three versions to draw, and which
  is the recommended default. Each names the personas on each side.

DO NOT CHANGE
  An explicit list of what is settled and must survive: the screens that were clean, the components
  that were right, the copy that was correct, the design-system rules to honour. Built from the
  human's seed list plus every persona's "what works and should be kept" section. This is the
  section most likely to be skipped and the one that stops the tool redesigning what was fine.

ATTACHED
  The screenshot paths, grouped by screen, so the tool sees the current state rather than a prose
  description of it.
```

Keep the questions-for-the-human list out of the prompt and hand it to the human separately as a
numbered list, each item stating what is unknown and what decision it blocks.

## Known failure modes and countermeasures

| Failure | What it looks like | Countermeasure |
|---|---|---|
| Persona collapse into a generic helpful reviewer | Three reports that read identically; findings no persona-specific field could have produced | Restate the three persona anchors above every screen's ledger block; make "never notices" a real exclusion the agent must honour even when it sees a genuine defect there |
| Persona drift over a long run | Later screens reported in a flatter, more generic voice than earlier ones | Per-screen anchor restatement; one screen per ledger block rather than one long narrative; if a run exceeds roughly thirty screens, split it into two dispatches with the persona restated in full |
| Sycophancy toward the artefact | "The layout is clean and modern"; praise with no element named | Ban praise without a named element and a screenshot; no adjective without a referent |
| Hallucinated findings from inferred behaviour | "Clicking Continue would probably take the user to..."; a defect in a control never exercised | The did-not-click-it rule. An unexercised control produces a question, never a defect |
| Invented copy | A quoted string that is not in the artefact | Copy claims quote verbatim; the orchestrator verifies every quoted string exists before the prompt is written |
| Impressionistic coverage | A confident report that silently covered 60% of the screens | The ledger gates the prose; the what-was-not-reached section is mandatory and counted |
| Stopping at a plausible number | Five to ten tidy findings and a wrap-up | Name no target count anywhere in the dispatch. The stopping condition is the ledger, and only the ledger |
| Agreement drift between agents | The second and third reports echo the first | One session and one directory per persona; concurrent dispatch; the orchestrator never quotes one to another; discard and re-run any report that echoes |
| Count deflation and severity inflation in the merge | The merged list is shorter than any single report and everything is now major | No reconciliation round. Mechanical dedupe on screen plus element by the orchestrator, all severities retained |
| Singletons filtered out | Only findings two or three personas hit survive into the prompt | Count orders within a severity band, never filters. Nothing is dropped for being a singleton |
| The same defect described three different ways | Dedupe misses it and the design tool gets three unrelated asks | The shared named-check list. Dedupe keys on the check ID, then on the ID across screens for cross-screen patterns |
| Fabricated latency, error or screen-reader findings | Findings about properties a static export cannot expose | The mandatory not-assessable section gives them somewhere honest to go |
| Asserted measurements | A stated font size, hex or contrast ratio that was never measured | Measure it with `get styles` or do not claim it; flag anything unmeasurable for verification |
| An empty do-not-change section | The amendment round redesigns the screens that were fine | Every persona owes two to five kept-as-is items, under the same referent rules as a defect |
| Stale refs | A click lands on the wrong element after the page changed | Re-snapshot after every page-changing action; one control at a time |
| Source-reading | Findings citing markup, CSS or a data attribute | The no-source-reading rule. Inventory comes from the rendered drawer, not the file |
| The design tool redesigning what was fine | The amendment round changes screens nobody complained about | The do-not-change section, written explicitly and never omitted |
| A design tool inventing an answer to an open question | A drawn screen resolving something the humans had not decided | Questions for the human never enter the design-tool prompt |

## Prompt skeleton for dispatching one persona agent

Copy, fill the placeholders, dispatch one per persona. Identical for every persona except the persona
block and the paths.

```
You are running a persona teardown of an artefact in a browser. Work alone. Do not read any other
agent's output and do not ask for it.

YOUR PERSONA
<paste the filled persona definition template>

THE ARTEFACT
Served at <base-url>. It is <one line: what it is, e.g. a static exported UI kit with a Screens
drawer>. Screen inventory, if one was derived: <path or "derive it from the drawer yourself">.

NAMED CHECKS
<paste the named-check list: the stable IDs every persona must use to label a defect type>

SOURCE OF TRUTH FOR "EXPECTED"
<path to spec / design brief / design-system rules>, or: "There is no spec. Mark nearly every
expectation as assumption-sourced and expect most of your findings to be questions."

SCOPE
Viewports: <e.g. 1440x900 and 390x844>. Grounds: <light and dark>. Ground is switched by
<the toggle's visible label, or "the OS colour scheme via set media">.

OUTPUT
Report: <work>/teardown/<persona-name>/report.md
Screenshots: <work>/teardown/<persona-name>/screenshots/
Browser session: use --session <persona-name> on every agent-browser command.
Scratch files (page-text dumps, snapshots saved to disk): only under a subfolder named after the persona,
never at a shared scratch root, so no two agents ever write the same filename.

PROCEDURE
Follow this file, section "Per-agent walkthrough
protocol", exactly. Run `agent-browser skills get core --full` before your first command and never
guess a flag.

In short: build the coverage ledger first from the drawer and from `snapshot -i` on every screen
(every screen, every control, every state, both viewports, both grounds); mark every row reached,
unreachable or not-attempted; walk every screen asking the four walkthrough questions against your
own goal, then sweep mechanically; one control at a time, re-snapshot after every action; screenshot
every finding; write findings one per line in the fixed template, labelled with a named check ID and
the severity scale from the SOP; then the coverage summary, then what you did not reach, then what
was not assessable from this artefact, then two to five things that work and should be kept, then
your three biggest problems in your own words.

HARD RULES
- If you did not click it, you do not report it. An expectation about what a control would do is a
  question for the human, never a defect.
- No adjective without a named element and a screenshot.
- No praise outside the "what works and should be kept" section, and not even there without naming
  the element.
- Quote copy verbatim. Never paraphrase it.
- Never guess a value you could have measured with `get styles`, `get text` or `get value`. Anything
  genuinely unmeasurable, such as a contrast ratio, is flagged for verification, never asserted.
- Do not read the artefact's source, markup, CSS or JavaScript.
- Do not fix anything and do not propose an implementation.
- Do not write a summary, a conclusion or a top-three until every ledger row is marked.
- There is no target number of findings. Report every defect you observe. The ledger is your
  stopping condition.
- Above every screen's ledger block, restate these three lines: who you are and what you came to
  do; your pass bar; "I did not click it, I do not report it."

When you are done, close your session (`agent-browser --session <persona-name> close`) and report
back only the path to your report, your coverage counts, and your findings count by severity.
```

## Runs, for calibration

- **A 58-screen fintech intake prototype, 14 Sep 2026.** Four Opus general-purpose agents in parallel, one persona each (the paying owner, the domain operator, the product lead, the engineer who builds it), cold, against a static React kit with a Screens drawer, two grounds, three native viewports. Each covered 58 of 58 screens on both grounds in one dispatch, so the "split above thirty screens" advice above was not needed: durations 69 to 150 minutes, 470k to 510k tokens each, 214 to 371 tool calls. Findings per persona: 108, 119, 143, 120 (490 total; 67 stoppers, 83 wrong claims). No persona collapse: every major theme was hit by all four in different words, and each report carried singletons the others missed (the engineer alone found drawer entries that work from some states and not others; the operator alone found rule evidence alternating by row parity and a met line whose reason said the document was absent; the product lead alone counted the nineteen rule-as-prose paragraphs; the owner alone found a third party's dead end). Two practical lessons folded in above: scratch files under a persona-named subfolder, and viewport screenshots by default. One persona wrote its report only at the end despite the incremental instruction; nothing was lost, but a mid-run nudge to flush was needed. The severity spread differed by persona (the operator rated 41 stoppers, the product lead 3) because the behavioural test reads differently through different goals; the merge kept every rating.
