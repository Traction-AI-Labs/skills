#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/gauntlet.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GAUNTLET_ROUND_RECORD="$TMP/rounds.jsonl"
export GAUNTLET_ARCHIVE="$TMP/archive"

git init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.name test
git -C "$TMP/repo" config user.email test@example.invalid
printf 'base\n' > "$TMP/repo/app.txt"
git -C "$TMP/repo" add app.txt
git -C "$TMP/repo" commit -qm base
git -C "$TMP/repo" checkout -qb feature
printf 'changed\n' > "$TMP/repo/app.txt"
git -C "$TMP/repo" commit -am change -q

mkdir "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'started\n' > "$(dirname "$0")/claude.started"
sleep 1
if [[ -f "$(dirname "$0")/claude.fail" ]]; then
  printf 'forced provider failure\n' >&2
  exit 7
fi
prompt="$(cat)"
model="$(printf '%s\n' "$prompt" | sed -n 's/^Requested model: //p')"
sha="$(printf '%s\n' "$prompt" | sed -n 's/^Scope SHA: //p')"
digest="$(printf '%s\n' "$prompt" | sed -n 's/^Scope digest: //p')"
printf '{"engine":"claude","model":"%s","transport":"claude-cli","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$model" "$sha" "$digest"
EOF
chmod +x "$TMP/bin/claude"

# Desktop command cells terminate their process group as soon as the launcher
# returns. The macOS launcher must therefore submit the worker to launchd and
# explicitly carry the run path into that separate environment.
REAL_LAUNCHCTL="$(command -v launchctl)"
cat > "$TMP/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == submit && -n "${FAKE_LAUNCHCTL_SUBMIT:-}" ]]; then printf '%s\n' "$@" > "$FAKE_LAUNCHCTL_SUBMIT"; fi
exec /bin/launchctl "$@"
EOF
chmod +x "$TMP/bin/launchctl"

wait_for_file() {
  local file="$1" attempts=0
  while [[ ! -f "$file" && "$attempts" -lt 600 ]]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done
  if [[ ! -f "$file" ]]; then
    printf 'timed out waiting for %s\n' "$file" >&2
    case "$file" in */completion/*) cat "${file%/completion/*}/failures/claude.worker" >&2 2>/dev/null || true ;; esac
    exit 1
  fi
}

prepare_run() {
  local run="$1" prompt sha digest native
  GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$run" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity lifecycle >/dev/null
  prompt="$run/prompts/codex-native.md"
  sha="$(sed -n 's/^Scope SHA: //p' "$prompt")"
  digest="$(sed -n 's/^Scope digest: //p' "$prompt")"
  native="$run/codex-native.txt"
  printf '{"engine":"codex","model":"gpt-5.6-terra","transport":"codex-native","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$sha" "$digest" > "$native"
  GAUNTLET_DIR="$run" bash "$RUNNER" ingest --engine codex --text "$native"
}

run="$TMP/slow-run"
prepare_run "$run"
PATH="$TMP/bin:$PATH" REAL_LAUNCHCTL="$REAL_LAUNCHCTL" FAKE_LAUNCHCTL_SUBMIT="$TMP/slow.launchctl" \
  GAUNTLET_DIR="$run" bash "$RUNNER" run-cli --engine claude > "$TMP/launch.out"
wait_for_file "$TMP/bin/claude.started"
grep -Fx 'submit' "$TMP/slow.launchctl"
grep -Fx "GAUNTLET_DIR=$run" "$TMP/slow.launchctl"
grep -Fx 'leg claude started: bound 1800s' "$TMP/launch.out"

if GAUNTLET_DIR="$run" bash "$RUNNER" collect > "$TMP/running.out"; then exit 1; fi
grep -Fx 'GAUNTLET: RUNNING' "$TMP/running.out"
grep -Fx 'BOUND: claude 1800s' "$TMP/running.out"
grep -Fx 'RUNNING: claude' "$TMP/running.out"

if PATH="$TMP/bin:$PATH" \
  GAUNTLET_DIR="$run" bash "$RUNNER" run-cli --engine claude > /dev/null 2> "$TMP/lock.err"; then exit 1; fi
grep -Fq 'claude CLI leg is already running' "$TMP/lock.err"

if GAUNTLET_DIR="$run" bash "$RUNNER" clean > /dev/null 2> "$TMP/clean.err"; then exit 1; fi
grep -Fq 'refusing to clean while legs are running: claude' "$TMP/clean.err"

wait_for_file "$run/completion/claude.done"
GAUNTLET_DIR="$run" bash "$RUNNER" collect > "$TMP/final.out"
grep -Fx 'GAUNTLET: APPROVE' "$TMP/final.out"
# A finished run is archived outside the scratch directory, once, and survives clean.
archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/final.out")"
[[ "$archive" == "$TMP/archive/"*-gauntlet-lifecycle-* ]]
test -f "$archive/results/claude.json"
test -f "$archive/results/codex.json"
test -f "$archive/rows.json"
test -f "$archive/scope/head"
test -f "$archive/.complete"
compgen -G "$archive/raw/claude-cli-*.transcript.jsonl" > /dev/null
test -f "$archive/raw/codex-native.txt"
test ! -e "$archive/scope/diff.patch"
GAUNTLET_DIR="$run" bash "$RUNNER" collect > "$TMP/final-again.out"
[[ "$(sed -n 's/^ARCHIVE: //p' "$TMP/final-again.out")" == "$archive" ]]
# An interrupted copy: the destination was chosen and recorded, nothing was renamed into place,
# and a partial sibling was left behind. The next collect rebuilds the same destination,
# beside the recorded path even when GAUNTLET_ARCHIVE now points elsewhere.
mv "$archive" "$archive.moved"
mkdir -p "$(dirname "$archive")/.partial-$(basename "$archive")/junk"
GAUNTLET_ARCHIVE="$TMP/other-root" GAUNTLET_DIR="$run" bash "$RUNNER" collect > "$TMP/final-resumed.out"
test ! -e "$TMP/other-root"
[[ "$(sed -n 's/^ARCHIVE: //p' "$TMP/final-resumed.out")" == "$archive" ]]
test -f "$archive/.complete"
test -f "$archive/results/claude.json"
test ! -e "$(dirname "$archive")/.partial-$(basename "$archive")"
GAUNTLET_DIR="$run" bash "$RUNNER" clean
test ! -e "$run"
test -f "$archive/results/claude.json"
first_archive="$archive"

failed_run="$TMP/failed-run"
prepare_run "$failed_run"
touch "$TMP/bin/claude.fail"
PATH="$TMP/bin:$PATH" \
  GAUNTLET_DIR="$failed_run" bash "$RUNNER" run-cli --engine claude > /dev/null
wait_for_file "$TMP/bin/claude.started"
if GAUNTLET_DIR="$failed_run" bash "$RUNNER" collect > "$TMP/failed-running.out"; then exit 1; fi
grep -Fx 'GAUNTLET: RUNNING' "$TMP/failed-running.out"
wait_for_file "$failed_run/completion/claude.done"
# An archive root inside the reviewed repository (and not ignored there) is refused before anything is written.
if GAUNTLET_ARCHIVE="$TMP/repo/receipts" GAUNTLET_DIR="$failed_run" bash "$RUNNER" collect > /dev/null 2> "$TMP/archive.err"; then exit 1; fi
grep -Fq 'lies inside a git worktree and is not ignored there' "$TMP/archive.err"
test ! -e "$TMP/repo/receipts"
if GAUNTLET_DIR="$failed_run" bash "$RUNNER" collect > "$TMP/failed-final.out"; then exit 1; fi
grep -Fx 'GAUNTLET: FAILED' "$TMP/failed-final.out"
grep -Fx 'FAILED: claude' "$TMP/failed-final.out"
# A failed run is archived too: its diagnostics are the post-facto record.
archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/failed-final.out")"
test -f "$archive/failures/claude.txt"
test -f "$archive/results/codex.json"
# Same identity and digest as the first run: the destination still differs, so neither run overwrites the other.
[[ "$archive" != "$first_archive" ]]
test -f "$first_archive/results/claude.json"

echo 'gauntlet-lifecycle.test.sh: OK'
