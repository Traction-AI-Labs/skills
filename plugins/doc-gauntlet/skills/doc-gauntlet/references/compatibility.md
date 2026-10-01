# Compatibility

| Host | Matching native review | Portable option |
|---|---|---|
| Codex | one fresh read-only Codex reviewer, with no unrelated live collaboration task during the mailbox-wide wait | CLI for the other prepared engine |
| Claude Code | one fresh read-only Claude reviewer with one bounded final-result/status primitive | CLI for the other prepared engine |
| Grok Build TUI | one fresh read-only grok reviewer with one bounded wait | CLI for the other prepared engine |
| Other hosts | none | both prepared CLIs |

The Codex leg defaults to `gpt-6.1-sol` and needs Codex CLI 0.159.3 or later; older CLIs reject that model on a ChatGPT account. `--codex-model` picks another.

Breadth native prompts are `<run>/prompts/breadth-<lens>.md`. Breadth uses Claude when Claude is in the pair; otherwise Grok. Adversarial native prompts are `<run>/prompts/adversarial-<engine>-native.md`; CLI uses the matching `*-cli.md` file. Read the prepared pair, breadth engine, models, and effort from `rows.json`.

On Codex, dispatch `explorer` with `fork_turns: none`, use one bounded `wait_agent`, and call `interrupt_agent` if unfinished. On Claude Code, dispatch one fresh `Explore` task, use one bounded final-result/status call, and use `TaskStop` if unfinished.

The host owns one fixed native wait, interruption, one native retry, and one same-engine CLI fallback. The runner owns detached CLI completion, per-leg launch locks, collection state, and guarded cleanup. Changed auto-loaded instructions, missing native primitives, an unrelated live Codex collaboration task, or an untrusted repository select CLI. The runner does not model native host timing or retry state.
