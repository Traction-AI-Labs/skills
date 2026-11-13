# Document Gauntlet

These examples are for a clone of this package directory. If you installed the Claude Code plugin, ask for a document gauntlet in session instead.

Document Gauntlet runs six independent breadth lenses followed by two independent adversarial reviews of one committed document revision, and returns two outputs: a short list of errors the document must fix and a sparring memo for the author. The default pair is Claude and Codex. Pass `--engines grok,codex` or `--engines claude,grok` to substitute Grok for one engine. Breadth uses Claude when Claude is in the pair; otherwise Grok. A row is `RUNNING` until its reviewer exits, then `FAILED` if it has no valid result; neither state is convergence.

## Quickstart

Open a terminal in the extracted package directory, the one containing this README and `skills/doc-gauntlet`. The portable runner runs from the package and does not need to be copied into an Agent Skills directory. Install the requirements below, authenticate the `claude` and `codex` CLIs, and commit the document you want reviewed in a dedicated clean worktree. Replace `docs/plan.md` with your document's path, use `--type requirements` for a requirements or specification document, then run:

```sh
(
RUN="$(DOC_GAUNTLET_REPO="<absolute review worktree>" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh prepare --authorize-provider --doc docs/plan.md --type plan | sed -n 's/^WORKDIR=//p')"
wait_for_lens() {
  while [ ! -f "$RUN/completion/breadth-$1.done" ]; do sleep 2; done
}
for lens in coherence feasibility scope-guardian; do
  DOC_GAUNTLET_DIR="$RUN" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh run-cli --lens "$lens"
done
for lens in coherence feasibility scope-guardian; do wait_for_lens "$lens"; done
for lens in product-lens security-lens design-lens; do
  DOC_GAUNTLET_DIR="$RUN" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh run-cli --lens "$lens"
done
for lens in product-lens security-lens design-lens; do wait_for_lens "$lens"; done
for result in "$RUN"/results/breadth-*.json; do
  printf '\n%s\n' "$result"
  cat "$result"
done
printf '%s' "If any breadth error needs a fix, press Ctrl-C now. Otherwise press Enter to start the final pair. "
if ! IFS= read -r _; then
  printf '%s\n' "No confirmation received. Stopping before the final reviewers." >&2
  exit 1
fi
DOC_GAUNTLET_DIR="$RUN" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh run-cli --engine claude
DOC_GAUNTLET_DIR="$RUN" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh run-cli --engine codex
while ! OUTPUT="$(DOC_GAUNTLET_DIR="$RUN" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh collect 2>&1)"; do
  printf '%s\n' "$OUTPUT"
  printf '%s\n' "$OUTPUT" | grep -Fxq 'GAUNTLET: RUNNING' || exit 1
  sleep 2
done
printf '%s\n' "$OUTPUT"
)
```

Read each breadth-lens JSON finding before the final line. Every finding is one of two kinds. An `error` or `omission` (a false premise, a wrong or unverifiable fact, broken logic, a contradiction, or wording that would make a reader act wrongly) goes on the error list and is fixed in the document; a fix corrects or deletes, never adds a hedge. A `sparring` point goes into a short memo for the author (a two-line verdict, then at most six ranked points, each with a concrete fix) and is the author's to weigh, never auto-applied. `ADVERSARIAL: BLOCK` means a reviewer reported at least one error or omission; `ADVERSARIAL: CONVERGED` means none, and may still carry sparring points. The review gate passes when no verified error remains. `GAUNTLET: RUNNING` names unfinished reviewers. `GAUNTLET: FAILED` names completed reviewers without a valid result; inspect the printed failure, recover only that reviewer, then collect again. Save the output before running `clean`.

A document gets up to two rounds, one when a code gauntlet has already reviewed the same change. Each successful round is appended to the round record at `~/.gauntlet/rounds.jsonl` (override the path with `GAUNTLET_ROUND_RECORD`), keyed on the repository and the document path; a round is a distinct document content, so a re-run on an unchanged document is a retry of the same round. The runner numbers rounds and refuses nothing on round count; `--override-round-budget` is accepted and ignored. Breadth runs once.

The second round, after the errors are fixed and committed, prepares only the two adversarial reviewers. It has no breadth rows, so do not run the quickstart above against it; run this instead, with the first round's saved `collect` output as the prior findings:

```sh
RUN="$(DOC_GAUNTLET_REPO="<absolute review worktree>" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh prepare --authorize-provider --doc docs/plan.md --type plan --pair-only --prior-findings <round-1-collect-output> | sed -n 's/^WORKDIR=//p')"
DOC_GAUNTLET_DIR="$RUN" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh run-cli --engine claude
DOC_GAUNTLET_DIR="$RUN" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh run-cli --engine codex
while ! OUTPUT="$(DOC_GAUNTLET_DIR="$RUN" bash skills/doc-gauntlet/scripts/doc-gauntlet.sh collect 2>&1)"; do
  printf '%s\n' "$OUTPUT"
  printf '%s\n' "$OUTPUT" | grep -Fxq 'GAUNTLET: RUNNING' || exit 1
  sleep 2
done
printf '%s\n' "$OUTPUT"
```

Pass `--prior-findings <file>` to `prepare` when a previous round exists. The runner snapshots it and tells every prepared reviewer not to repeat accepted or known findings unless they remain in the current document.

## Requirements

- Bash, Git, Python 3 and `timeout`
- Authenticated CLIs for the prepared pair (`claude` and `codex` by default; `grok` when substituted)
- Claude Code, Codex, or Grok Build TUI for optional matching native reviewers
- Explicit provider authorisation before document or repository content is sent

The runner has five commands: `prepare`, `run-cli`, `ingest`, `collect` and `clean`. The six breadth lenses run in two practical waves of three. Inspect breadth findings before starting the adversarial pair. `collect` reports only the pair outcome as `ADVERSARIAL: CONVERGED|BLOCK`; the host owns the overall verdict after breadth adjudication. A fix changes the pinned revision, so commit it and prepare a fresh run.

A host may use a fresh read-only native reviewer, pass the exact prepared native prompt, save the returned text verbatim, then call `ingest`. The host owns one fixed native wait, interruption, one native retry and one same-engine CLI fallback. The runner validates the pinned scope, starts CLI legs detached, refuses concurrent same-leg launches and takes the last matching JSON object.

Both provider CLIs can inspect the full repository and receive a provider-native output schema; tolerant ingestion remains the backstop. Each leg has a 1800-second default bound, overridable globally with `GAUNTLET_PROVIDER_TIMEOUT_SECONDS` or per engine with `GAUNTLET_TIMEOUT_CLAUDE_SECONDS`, `GAUNTLET_TIMEOUT_CODEX_SECONDS`, and `GAUNTLET_TIMEOUT_GROK_SECONDS`. Common secret-bearing selected inputs are refused, but that check is only a backstop. Use an operator-trusted repository without provider-readable secrets. The package includes its attributed review kernel and has no Compound Engineering runtime dependency.

When every prepared leg fails, `collect` writes `results/gauntlet-failed.json` with their raw exit codes and diagnostics. This is a durable failure artefact, never a review verdict.

Record the result before running `clean`, which removes the explicitly named run directory and refuses while a leg is running. `clean --force` is reserved for abandoning an active run. This release is a clean protocol cut; existing v2 run directories are incompatible. See `skills/doc-gauntlet/references/compatibility.md` for host support.

`collect` also copies every finished run, passed or failed, into a private archive at `~/.gauntlet/runs/` (`GAUNTLET_ARCHIVE` relocates it; a root inside a git worktree is refused unless it is ignored there) and prints `ARCHIVE: <path>`. The archive keeps results, the scope pins and each reviewer's raw output, unredacted, so it can contain document and repository content the reviewers quoted. A failed leg's provider diagnostics are kept only as a sanitised failure summary; the raw diagnostic output is deleted. It is never pruned; delete old runs yourself, and keep the folder out of backups and repositories you share. `clean` removes only the scratch run directory, not the archive.

Licensed under MIT.
