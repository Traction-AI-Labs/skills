# Gauntlet

These examples are for a clone of this package directory. If you installed the Claude Code plugin, ask for a gauntlet in session instead.

Gauntlet runs two independent reviews of one committed code diff. The default pair is Claude and Codex. Pass `--engines grok,codex` or `--engines claude,grok` to substitute Grok for one engine. It pins the base, HEAD, diff, prompts, models and reviewer rows in a private run directory, then accepts one validated result from each prepared engine.

## Quickstart

Open a terminal in the extracted package directory, the one containing this README and `skills/gauntlet`. The portable runner runs from the package and does not need to be copied into an Agent Skills directory. Install the requirements below, authenticate the `claude` and `codex` CLIs, and commit the code you want reviewed in a dedicated clean worktree. Then run:

```bash
RUN="$(GAUNTLET_REPO="<absolute review worktree>" bash skills/gauntlet/scripts/gauntlet.sh prepare --authorize-provider --identity <branch-name> --base main --profile balanced | sed -n 's/^GAUNTLET_DIR=//p')"
GAUNTLET_DIR="$RUN" bash skills/gauntlet/scripts/gauntlet.sh run-cli --engine claude
GAUNTLET_DIR="$RUN" bash skills/gauntlet/scripts/gauntlet.sh run-cli --engine codex
while ! OUTPUT="$(GAUNTLET_DIR="$RUN" bash skills/gauntlet/scripts/gauntlet.sh collect 2>&1)"; do
  printf '%s\n' "$OUTPUT"
  printf '%s\n' "$OUTPUT" | grep -Fxq 'GAUNTLET: RUNNING' || exit 1
  sleep 2
done
printf '%s\n' "$OUTPUT"
```

`GAUNTLET: RUNNING` means at least one detached reviewer has not exited yet. `GAUNTLET: APPROVE` means both reviewers found no blocking defect. `GAUNTLET: BLOCK` means at least one reviewer reported a finding to adjudicate and repair. `GAUNTLET: FAILED` names a completed leg with no valid result; inspect the printed failure, recover that engine only, then collect again. Save the output before running `clean`.

`prepare` requires the reviewed thing's identity: `--identity <branch-name>` for a branch, or `--pr <n>` for a pull request. Each round is appended to the round record at `~/.gauntlet/rounds.jsonl` (override the path with `GAUNTLET_ROUND_RECORD`) with its identity, its round number and the `--pre-reviewed-by` value; a re-run on unchanged content keeps its round number. There is no round cap and the runner refuses nothing on round count: the loop ends at the stop state described in the skill (a round with no verified material finding, or a round whose material findings all sit in lines the previous repair wrote). `--override-round-budget` and `--supersedes` are still accepted and ignored, so older callers keep working.

Pass `--prior-findings <file>` to `prepare` when a previous round exists. The runner snapshots it and tells both reviewers not to repeat accepted or known findings unless they remain in the current code.

## Requirements

- Bash, Git, Python 3 and `timeout`
- Authenticated CLIs for the prepared pair (`claude` and `codex` by default; `grok` when substituted)
- Claude Code, Codex, or Grok Build TUI for the optional matching native reviewer
- Explicit provider authorisation before repository content is sent

The runner has five commands: `prepare`, `run-cli`, `ingest`, `collect` and `clean`. A host may use one fresh read-only native reviewer for its matching engine. It passes the exact `prompts/<engine>-native.md` file, saves the return verbatim, and calls `ingest`. The host owns one fixed native wait, interruption, one native retry and one same-engine CLI fallback. The runner owns pinned-scope validation, detached CLI completion and result parsing.

Each CLI starts detached in its own private temporary directory outside the shared run. Claude uses read-only tools; Codex uses read-only isolation with project instructions disabled; Grok uses a per-run `strict` sandbox that can read the reviewed repository, plus a kernel deny on the prepared run directory so peer results stay unreadable. The prepared prompt is copied into the provider temp dir. Each receives a provider-native output schema, while tolerant ingestion remains the backstop. Each leg is bounded by `prepare --timeout-seconds` (default 1800). At `run-cli` time `GAUNTLET_TIMEOUT_CLAUDE_SECONDS`, `GAUNTLET_TIMEOUT_CODEX_SECONDS` or `GAUNTLET_TIMEOUT_GROK_SECONDS`, then `GAUNTLET_PROVIDER_TIMEOUT_SECONDS`, override it for that leg. Each CLI leg reads the pinned diff as `./diff.patch` in its own temporary directory, copied from `scope/diff.patch` and checked against the pinned digest; its prompt never names the run directory and carries no peer output, though the Claude and Codex processes are not sandboxed from the run folder. Each attempt's reply, transcript, untrimmed stderr and start and end time are kept in the run and its private archive, never in a repository. A second `run-cli` for the same engine is refused until the first exits. Both can inspect the full repository. Known secret-bearing changed paths are refused, but that check is only a backstop. Use an operator-trusted repository without provider-readable secrets.

When both completed legs fail, `collect` writes `results/gauntlet-failed.json` with their raw exit codes and diagnostics. This is a durable failure artefact, never an approval or block verdict.

`collect` also copies every finished run, passed or failed, into a private archive at `~/.gauntlet/runs/` (`GAUNTLET_ARCHIVE` relocates it; a root inside a git worktree is refused unless it is ignored there) and prints `ARCHIVE: <path>`. The archive keeps results, the scope pins and, for each CLI attempt, the full transcript and untrimmed stderr, unredacted: it can contain repository content the reviewers read and anything a provider CLI writes to stderr, including request headers. It is never pruned; delete old runs yourself, and keep the folder out of backups and repositories you share. `clean` removes only the scratch run directory, not the archive.

Record the result before running `clean`, which removes the explicitly named run directory and refuses while a leg is running. `clean --force` is reserved for abandoning an active run. A fix changes the pinned scope, so commit it and prepare a fresh run.

This release is a clean protocol cut. Existing v2 run directories are incompatible. See `skills/gauntlet/references/compatibility.md` for host support.

Licensed under MIT.
