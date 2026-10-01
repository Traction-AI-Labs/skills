#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/doc-gauntlet.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GAUNTLET_ROUND_RECORD="$TMP/rounds.jsonl"
export GAUNTLET_ARCHIVE="$TMP/archive"

mkdir -p "$TMP/repo/docs"
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.name test
git -C "$TMP/repo" config user.email test@example.invalid
printf '# Plan\n' > "$TMP/repo/docs/plan.md"
git -C "$TMP/repo" add docs/plan.md
git -C "$TMP/repo" commit -qm base
git -C "$TMP/repo" checkout -qb feature
printf '\nChanged.\n' >> "$TMP/repo/docs/plan.md"
git -C "$TMP/repo" commit -am change -q

mkdir "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'started\n' > "$FAKE_CLAUDE_STARTED"
sleep "${FAKE_CLAUDE_SLEEP:-1}"
if [[ "${FAKE_CLAUDE_FAIL:-}" == yes ]]; then
  printf 'forced provider failure\n' >&2
  exit 7
fi
prompt="$(cat)"
lens="$(printf '%s\n' "$prompt" | sed -n 's/^You are the \([a-z-]*\) document-review lens.*/\1/p')"
printf '{"reviewer":"%s","findings":[],"residual_risks":[],"deferred_questions":[]}\n' "$lens"
EOF
chmod +x "$TMP/bin/claude"

wait_for_file() {
  local file="$1" attempts=0
  while [[ ! -f "$file" && "$attempts" -lt 600 ]]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done
  [[ -f "$file" ]] || { printf 'timed out waiting for %s\n' "$file" >&2; exit 1; }
}

prepare_run() {
  local run="$1" lens head digest engine text
  DOC_GAUNTLET_REPO="$TMP/repo" DOC_GAUNTLET_DIR="$run" bash "$RUNNER" prepare \
    --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture >/dev/null
  for lens in feasibility scope-guardian product-lens security-lens design-lens; do
    text="$run/$lens-native.txt"
    printf '{"reviewer":"%s","findings":[],"residual_risks":[],"deferred_questions":[]}\n' "$lens" > "$text"
    DOC_GAUNTLET_DIR="$run" bash "$RUNNER" ingest --lens "$lens" --transport claude-native --text "$text"
  done
  head="$(cat "$run/head.commit")"; digest="$(cat "$run/scope.digest")"
  for engine in claude codex; do
    text="$run/$engine-native.txt"
    printf '{"engine":"%s","model":"fixture","transport":"%s-native","scope_sha":"%s","scope_digest":"%s","verdict":"CONVERGED","findings":[]}\n' "$engine" "$engine" "$head" "$digest" > "$text"
    DOC_GAUNTLET_DIR="$run" bash "$RUNNER" ingest --engine "$engine" --transport "$engine-native" --text "$text"
  done
}

run="$TMP/slow-run"
prepare_run "$run"
PATH="$TMP/bin:$PATH" FAKE_CLAUDE_STARTED="$TMP/slow.started" FAKE_CLAUDE_SLEEP=1 \
  DOC_GAUNTLET_DIR="$run" bash "$RUNNER" run-cli --lens coherence > "$TMP/launch.out"
wait_for_file "$TMP/slow.started"
grep -Fx 'leg coherence started: bound 1800s (source: config)' "$TMP/launch.out"

if DOC_GAUNTLET_DIR="$run" bash "$RUNNER" collect > "$TMP/running.out"; then exit 1; fi
grep -Fx 'GAUNTLET: RUNNING' "$TMP/running.out"
grep -Fx 'RUNNING: coherence' "$TMP/running.out"
grep -Fq 'BOUND: breadth-coherence 1800s (source: config)' "$TMP/running.out"

if PATH="$TMP/bin:$PATH" FAKE_CLAUDE_STARTED="$TMP/second.started" FAKE_CLAUDE_SLEEP=1 \
  DOC_GAUNTLET_DIR="$run" bash "$RUNNER" run-cli --lens coherence > /dev/null 2> "$TMP/lock.err"; then exit 1; fi
grep -Fq 'coherence CLI leg is already running' "$TMP/lock.err"
test ! -e "$TMP/second.started"

if DOC_GAUNTLET_DIR="$run" bash "$RUNNER" clean > /dev/null 2> "$TMP/clean.err"; then exit 1; fi
grep -Fq 'refusing to clean while legs are running: coherence' "$TMP/clean.err"

wait_for_file "$run/completion/breadth-coherence.done"
DOC_GAUNTLET_DIR="$run" bash "$RUNNER" collect > "$TMP/final.out"
grep -Fx 'ADVERSARIAL: CONVERGED' "$TMP/final.out"
# A finished run is archived outside the scratch directory, once, and survives clean.
archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/final.out")"
[[ "$archive" == "$TMP/archive/"*-doc-gauntlet-doc-docs-plan.md-* ]]
test -f "$archive/results/adversarial-claude.json"
test -f "$archive/results/breadth-coherence.json"
test -f "$archive/rows.json"
test -f "$archive/head.commit"
test -f "$archive/scope.digest"
test -f "$archive/.complete"
test -f "$archive/raw/raw-breadth-coherence.txt"
test -f "$archive/scope/document.snapshot"
test -f "$archive/source-document.path"
test -f "$archive/repository.path"
DOC_GAUNTLET_DIR="$run" bash "$RUNNER" collect > "$TMP/final-again.out"
[[ "$(sed -n 's/^ARCHIVE: //p' "$TMP/final-again.out")" == "$archive" ]]
# An interrupted copy: the destination was chosen and recorded, nothing was renamed into place,
# and a partial sibling was left behind. The next collect rebuilds the same destination,
# beside the recorded path even when GAUNTLET_ARCHIVE now points elsewhere.
mv "$archive" "$archive.moved"
mkdir -p "$(dirname "$archive")/.partial-$(basename "$archive")/junk"
GAUNTLET_ARCHIVE="$TMP/other-root" DOC_GAUNTLET_DIR="$run" bash "$RUNNER" collect > "$TMP/final-resumed.out"
test ! -e "$TMP/other-root"
[[ "$(sed -n 's/^ARCHIVE: //p' "$TMP/final-resumed.out")" == "$archive" ]]
test -f "$archive/.complete"
test ! -e "$(dirname "$archive")/.partial-$(basename "$archive")"
DOC_GAUNTLET_DIR="$run" bash "$RUNNER" clean
test ! -e "$run"
test -f "$archive/results/adversarial-claude.json"
first_archive="$archive"

failed_run="$TMP/failed-run"
prepare_run "$failed_run"
PATH="$TMP/bin:$PATH" FAKE_CLAUDE_STARTED="$TMP/failed.started" FAKE_CLAUDE_SLEEP=1 FAKE_CLAUDE_FAIL=yes \
  DOC_GAUNTLET_DIR="$failed_run" bash "$RUNNER" run-cli --lens coherence > /dev/null
wait_for_file "$TMP/failed.started"
if DOC_GAUNTLET_DIR="$failed_run" bash "$RUNNER" collect > "$TMP/failed-running.out"; then exit 1; fi
grep -Fx 'GAUNTLET: RUNNING' "$TMP/failed-running.out"
wait_for_file "$failed_run/completion/breadth-coherence.done"
# An archive root inside the reviewed repository (and not ignored there) is refused before anything is written.
if GAUNTLET_ARCHIVE="$TMP/repo/receipts" DOC_GAUNTLET_DIR="$failed_run" bash "$RUNNER" collect > /dev/null 2> "$TMP/archive.err"; then exit 1; fi
grep -Fq 'lies inside a git worktree and is not ignored there' "$TMP/archive.err"
test ! -e "$TMP/repo/receipts"
if DOC_GAUNTLET_DIR="$failed_run" bash "$RUNNER" collect > "$TMP/failed-final.out"; then exit 1; fi
grep -Fx 'GAUNTLET: FAILED' "$TMP/failed-final.out"
grep -Fx 'FAILED: coherence' "$TMP/failed-final.out"
# A failed run is archived too: its diagnostics are the post-facto record.
archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/failed-final.out")"
test -f "$archive/failures/breadth-coherence.txt"
test -f "$archive/results/adversarial-claude.json"
# Same identity and digest as the first run: the destination still differs, so neither run overwrites the other.
[[ "$archive" != "$first_archive" ]]
test -f "$first_archive/results/adversarial-claude.json"

echo 'doc-gauntlet-lifecycle.test.sh: OK'
