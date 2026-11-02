#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/doc-gauntlet.sh"
TMP="$(mktemp -d)"
# The test owns its HOME: a fake Grok login for the legs that need one, and nothing of the real home is read or written.
export HOME="$TMP/home"; mkdir -p "$HOME/.grok"; printf '{}\n' > "$HOME/.grok/auth.json"
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
if [[ -n "${FAKE_CLAUDE_RELEASE:-}" ]]; then while [[ ! -e "$FAKE_CLAUDE_RELEASE" ]]; do sleep 0.05; done; fi
if [[ "${FAKE_CLAUDE_FAIL:-}" == yes ]]; then
  printf 'forced provider failure\n' >&2
  exit 7
fi
prompt="$(cat)"
lens="$(printf '%s\n' "$prompt" | sed -n 's/^You are the \([a-z-]*\) document-review lens.*/\1/p')"
printf '{"reviewer":"%s","findings":[],"residual_risks":[],"deferred_questions":[]}\n' "$lens"
EOF
chmod +x "$TMP/bin/claude"
cat > "$TMP/bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'started\n' > "$FAKE_CODEX_STARTED"
printf 'forced provider failure\n' >&2
exit 7
EOF
chmod +x "$TMP/bin/codex"

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
if grep -q '^ARCHIVE:' "$TMP/running.out"; then exit 1; fi

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

# A breadth-only round: every lens is in and the pair has not started (it does
# not run while breadth leaves an error open). collect archives it, so the
# lens results survive clean for the next round's --prior-findings.
breadth_run="$TMP/breadth-run"
DOC_GAUNTLET_REPO="$TMP/repo" DOC_GAUNTLET_DIR="$breadth_run" bash "$RUNNER" prepare \
  --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture >/dev/null
for lens in coherence feasibility scope-guardian product-lens security-lens design-lens; do
  printf '{"reviewer":"%s","findings":[],"residual_risks":[],"deferred_questions":[]}\n' "$lens" > "$TMP/breadth-$lens.txt"
  DOC_GAUNTLET_DIR="$breadth_run" bash "$RUNNER" ingest --lens "$lens" --transport claude-native --text "$TMP/breadth-$lens.txt"
done
if DOC_GAUNTLET_DIR="$breadth_run" bash "$RUNNER" collect > "$TMP/breadth-only.out"; then exit 1; fi
grep -Fx 'GAUNTLET: RUNNING' "$TMP/breadth-only.out"
breadth_archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/breadth-only.out")"
test -f "$breadth_archive/.complete"
for lens in coherence feasibility scope-guardian product-lens security-lens design-lens; do test -f "$breadth_archive/results/breadth-$lens.json"; done
test ! -e "$breadth_archive/results/adversarial-claude.json"
# Once a pair leg has started, a collect makes no further partial archive; the
# finished run gets its own archive and the breadth-only one keeps what it held.
head="$(cat "$breadth_run/head.commit")"; digest="$(cat "$breadth_run/scope.digest")"
for engine in claude codex; do
  printf '{"engine":"%s","model":"fixture","transport":"%s-native","scope_sha":"%s","scope_digest":"%s","verdict":"CONVERGED","findings":[]}\n' "$engine" "$engine" "$head" "$digest" > "$TMP/breadth-run-$engine.txt"
  DOC_GAUNTLET_DIR="$breadth_run" bash "$RUNNER" ingest --engine "$engine" --transport "$engine-native" --text "$TMP/breadth-run-$engine.txt"
  if [[ "$engine" == claude ]]; then
    if DOC_GAUNTLET_DIR="$breadth_run" bash "$RUNNER" collect > "$TMP/breadth-pair-running.out"; then exit 1; fi
    grep -Fx 'RUNNING: codex' "$TMP/breadth-pair-running.out"
    if grep -q '^ARCHIVE:' "$TMP/breadth-pair-running.out"; then exit 1; fi
  fi
done
DOC_GAUNTLET_DIR="$breadth_run" bash "$RUNNER" collect > "$TMP/breadth-full.out"
grep -Fx 'ADVERSARIAL: CONVERGED' "$TMP/breadth-full.out"
full_archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/breadth-full.out")"
[[ -n "$full_archive" && "$full_archive" != "$breadth_archive" ]]
test -f "$full_archive/results/adversarial-codex.json"
test -f "$full_archive/results/breadth-coherence.json"
test ! -e "$breadth_archive/results/adversarial-claude.json"
DOC_GAUNTLET_DIR="$breadth_run" bash "$RUNNER" clean
test -f "$breadth_archive/results/breadth-security-lens.json"

# A pair leg started by run-cli. From the moment run-cli writes the leg's bound,
# collect makes no further breadth-only archive; and run-cli drops the
# breadth-only archive's record, so a pair whose legs only fail (and so never
# reach ingest) still gets its own archive with the pair's failures in it.
pair_run="$TMP/pair-run"
DOC_GAUNTLET_REPO="$TMP/repo" DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" prepare \
  --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture >/dev/null
for lens in coherence feasibility scope-guardian product-lens security-lens; do
  DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" ingest --lens "$lens" --transport claude-native --text "$TMP/breadth-$lens.txt"
done
# Five lenses in and the pair not started: breadth is unfinished, so no archive.
if DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" collect > "$TMP/pair-five.out"; then exit 1; fi
grep -Fx 'RUNNING: design-lens claude codex' "$TMP/pair-five.out"
if grep -q '^ARCHIVE:' "$TMP/pair-five.out"; then exit 1; fi
DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" ingest --lens design-lens --transport claude-native --text "$TMP/breadth-design-lens.txt"
if DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" collect > "$TMP/pair-breadth.out"; then exit 1; fi
pair_breadth_archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/pair-breadth.out")"
test -f "$pair_breadth_archive/.complete"
PATH="$TMP/bin:$PATH" FAKE_CLAUDE_STARTED="$TMP/pair-claude.started" FAKE_CLAUDE_RELEASE="$TMP/pair-claude.release" FAKE_CLAUDE_FAIL=yes \
  DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" run-cli --engine claude > /dev/null
wait_for_file "$TMP/pair-claude.started"
if DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" collect > "$TMP/pair-running.out"; then exit 1; fi
grep -Fx 'GAUNTLET: RUNNING' "$TMP/pair-running.out"
if grep -q '^ARCHIVE:' "$TMP/pair-running.out"; then exit 1; fi
: > "$TMP/pair-claude.release"
wait_for_file "$pair_run/completion/adversarial-claude.done"
PATH="$TMP/bin:$PATH" FAKE_CODEX_STARTED="$TMP/pair-codex.started" \
  DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" run-cli --engine codex > /dev/null
wait_for_file "$pair_run/completion/adversarial-codex.done"
if DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" collect > "$TMP/pair-failed.out"; then exit 1; fi
grep -Fx 'GAUNTLET: FAILED' "$TMP/pair-failed.out"
pair_archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/pair-failed.out")"
[[ -n "$pair_archive" && "$pair_archive" != "$pair_breadth_archive" ]]
test -f "$pair_archive/failures/adversarial-claude.txt"
test -f "$pair_archive/failures/adversarial-codex.txt"
test ! -e "$pair_breadth_archive/failures/adversarial-claude.txt"
DOC_GAUNTLET_DIR="$pair_run" bash "$RUNNER" clean

# A refused ingest or run-cli after a breadth-only archive keeps its record:
# the next collect names the same archive and makes no second copy.
refused_run="$TMP/refused-run"
DOC_GAUNTLET_REPO="$TMP/repo" DOC_GAUNTLET_DIR="$refused_run" bash "$RUNNER" prepare \
  --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture >/dev/null
for lens in coherence feasibility scope-guardian product-lens security-lens design-lens; do
  DOC_GAUNTLET_DIR="$refused_run" bash "$RUNNER" ingest --lens "$lens" --transport claude-native --text "$TMP/breadth-$lens.txt"
done
if DOC_GAUNTLET_DIR="$refused_run" bash "$RUNNER" collect > "$TMP/refused-breadth.out"; then exit 1; fi
refused_archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/refused-breadth.out")"
test -f "$refused_archive/.complete"
if DOC_GAUNTLET_DIR="$refused_run" bash "$RUNNER" ingest --engine codex --transport claude-native --text "$TMP/breadth-run-codex.txt" > /dev/null 2> "$TMP/refused-ingest.err"; then exit 1; fi
grep -Fq 'adversarial transport must match its engine' "$TMP/refused-ingest.err"
if GAUNTLET_TIMEOUT_CLAUDE_SECONDS=soon DOC_GAUNTLET_DIR="$refused_run" bash "$RUNNER" run-cli --engine claude > /dev/null 2> "$TMP/refused-run-cli.err"; then exit 1; fi
grep -Fq 'timeout for claude must be a positive whole number of seconds' "$TMP/refused-run-cli.err"
if DOC_GAUNTLET_DIR="$refused_run" bash "$RUNNER" collect > "$TMP/refused-again.out"; then exit 1; fi
[[ "$(sed -n 's/^ARCHIVE: //p' "$TMP/refused-again.out")" == "$refused_archive" ]]
test ! -e "$refused_archive-2"
DOC_GAUNTLET_DIR="$refused_run" bash "$RUNNER" clean --force

# A pair-only run whose pair has not started is not a breadth-only round: no archive.
printf '{"findings":[]}\n' > "$TMP/pair-only-prior.json"
pair_only_run="$TMP/pair-only-run"
DOC_GAUNTLET_REPO="$TMP/repo" DOC_GAUNTLET_DIR="$pair_only_run" bash "$RUNNER" prepare \
  --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture --pair-only --prior-findings "$TMP/pair-only-prior.json" >/dev/null
if DOC_GAUNTLET_DIR="$pair_only_run" bash "$RUNNER" collect > "$TMP/pair-only.out"; then exit 1; fi
grep -Fx 'RUNNING: claude codex' "$TMP/pair-only.out"
if grep -q '^ARCHIVE:' "$TMP/pair-only.out"; then exit 1; fi
DOC_GAUNTLET_DIR="$pair_only_run" bash "$RUNNER" clean --force

# A --prior-findings file named - is read as a file, never as standard input.
printf '{"findings":[{"status":"accepted","section":"Dash decision"}]}\n' > "$TMP/-"
(cd "$TMP" && DOC_GAUNTLET_REPO="$TMP/repo" DOC_GAUNTLET_DIR="$TMP/dash-run" bash "$RUNNER" prepare \
  --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture --prior-findings - < /dev/null > /dev/null)
grep -Fq 'Dash decision' "$TMP/dash-run/scope/prior-findings.snapshot"
rm -f -- "$TMP/-"
DOC_GAUNTLET_DIR="$TMP/dash-run" bash "$RUNNER" clean --force

echo 'doc-gauntlet-lifecycle.test.sh: OK'
