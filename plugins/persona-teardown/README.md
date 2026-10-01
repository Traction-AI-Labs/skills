# Persona teardown

A panel of persona agents walks a prototype, UI kit, design-tool export or live screen in a real browser, every screen by every control by every state by every ground, and reports defects one per line with a screenshot each. The orchestrator merges the reports and emits one amendment prompt for the design tool. It is a search heuristic for defects, not evidence about users.

Once installed (Claude Code plugin, or the skill copied into Codex), ask for a teardown in session ("tear this down as the paying customer, the operator and the product lead"). The skill carries the orchestrator's checklist, the persona template, the per-agent protocol, the finding template, the severity scale, the consolidation steps and a dispatch prompt skeleton; `skills/persona-teardown/references/persona-teardown-sop.md` is the full procedure with the reasoning.

## What it needs

- `agent-browser` on the PATH (`npm i -g agent-browser && agent-browser install`), which the persona agents drive.
- The artefact served over HTTP (a static export: `python3 -m http.server`), a screen inventory or a nav to derive one from, a source of truth for "expected" (the spec or the design system's rules), and one output directory per persona.
- Claude Code or Codex with subagents; three personas is the default, four or five when the artefact has distinct audiences. In Claude Code each persona is one `general-purpose` agent with an explicit model. In Codex each is a `worker` spawned with `fork_turns: "none"`, and the session needs `--sandbox danger-full-access`, because the macOS `workspace-write` sandbox cannot launch Chromium. Full access lets each persona read and send anything your account can, so on Codex only tear down an artefact you control (your own export or staging URL). Install for Codex by copying `skills/persona-teardown` to `~/.codex/skills/persona-teardown`.

## The rules that carry it

- A persona reports only what it clicked. An expectation about an unexercised control is a question for a human, never a defect.
- The coverage ledger is written before any finding and is the only stopping condition. No target count is named anywhere.
- Independence is mechanical: one browser session and one directory per persona, concurrent dispatch, no reconciliation round, the orchestrator never shows one report to another.
- `wrong-claim` (the interface states something untrue) ranks with `stopper`, whatever its visual size.
- Praise is admissible only in the "what works and should be kept" section, naming the element, and that section becomes the amendment prompt's do-not-change list.

## Cost

One run over a 58-screen prototype: four Opus agents, 70 to 150 minutes and about half a million tokens each. Scope the second loop to the screens that changed.
