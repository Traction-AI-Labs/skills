#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/gauntlet.sh"
grep -Fq 'com.gauntlet.cli.{engine}' "$RUNNER"
TMP="$(mktemp -d)"; trap 'touch "$TMP/release-lifecycle-lock" 2>/dev/null || true; rm -rf "$TMP"' EXIT
export GAUNTLET_ROUND_RECORD="$TMP/rounds.jsonl"
export GAUNTLET_ARCHIVE="$TMP/archive"

git init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.name test
git -C "$TMP/repo" config user.email test@example.invalid
printf 'base\n' > "$TMP/repo/app.txt"
git -C "$TMP/repo" add . && git -C "$TMP/repo" commit -qm base
git -C "$TMP/repo" checkout -qb feature
printf 'changed\n' > "$TMP/repo/app.txt"
git -C "$TMP/repo" commit -am change -q
feature_base="$(git -C "$TMP/repo" rev-parse HEAD^)"
git -C "$TMP/repo" checkout -q main
printf 'target-only\n' > "$TMP/repo/target.txt"
git -C "$TMP/repo" add target.txt && git -C "$TMP/repo" commit -qm target-advanced
git -C "$TMP/repo" checkout -q feature
repo_canonical="$(git -C "$TMP/repo" rev-parse --show-toplevel)"

run() { GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/run" bash "$RUNNER" "$@"; }
# `! cmd` does not trip set -e, so negative assertions go through refute.
refute() { if "$@"; then echo "expected to fail: $*" >&2; exit 1; fi; }
wait_for_leg() {
  local run_dir="$1" engine="$2" attempts=0
  while [[ ! -f "$run_dir/completion/$engine.done" && "$attempts" -lt 1200 ]]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done
  [[ -f "$run_dir/completion/$engine.done" ]] || { printf 'timed out waiting for %s\n' "$engine" >&2; exit 1; }
}
printf '{"findings":[{"status":"known","location":"old.txt:1"}]}\n' > "$TMP/prior-findings.json"
run prepare --authorize-provider --base main --profile fast --identity suite --prior-findings "$TMP/prior-findings.json" > "$TMP/prepare.out"
grep -Fq 'GAUNTLET_DIR=' "$TMP/prepare.out"
test "$(python3 -c 'import os,stat,sys; print(f"{stat.S_IMODE(os.lstat(sys.argv[1]).st_mode):o}")' "$TMP/run")" = 700
# Reviewers read the pinned diff from a file; the prompt carries its path and stat, never the diff itself.
# A CLI leg reads ./diff.patch in its own working directory and its prompt never names the run.
test ! -e "$TMP/run/review"
for p in claude-cli codex-cli claude-native codex-native; do
  refute grep -Fq 'diff --git' "$TMP/run/prompts/$p.md"
  refute grep -Fq '+changed' "$TMP/run/prompts/$p.md"
  grep -Fq 'Read the whole file before judging' "$TMP/run/prompts/$p.md"
  grep -Eq 'app\.txt +\| +2 ' "$TMP/run/prompts/$p.md"
done
for p in claude-cli codex-cli; do
  grep -Fq 'The pinned diff is the file ./diff.patch' "$TMP/run/prompts/$p.md"
  refute grep -Fq "$TMP/run" "$TMP/run/prompts/$p.md"
done
for p in claude-native codex-native; do grep -Fq "The pinned diff is the file $TMP/run/scope/diff.patch" "$TMP/run/prompts/$p.md"; done
grep -Fq 'requires transport "claude-native"' "$TMP/run/prompts/claude-native.md"
grep -Fq 'requires transport "claude-cli"' "$TMP/run/prompts/claude-cli.md"
grep -Fq 'Do not re-raise a finding unless it persists in the current code;' "$TMP/run/prompts/claude-cli.md"
grep -Fq "if the premise of the change is wrong, make that your first finding" "$TMP/run/prompts/codex-cli.md"
for p in claude-cli codex-cli claude-native codex-native; do
  grep -Fq 'A test must fail when the behaviour it names breaks.' "$TMP/run/prompts/$p.md"
  grep -Fq 'A new refusal, flag, limit or boundary with no test that fails when it is switched off is a material finding.' "$TMP/run/prompts/$p.md"
  grep -Fq 'report it only when that load has a concrete consequence' "$TMP/run/prompts/$p.md"
  grep -Fq 'This round reviews the whole pinned diff, not only the repair of these findings.' "$TMP/run/prompts/$p.md"
  grep -Fq 'prior-round context supplied above is not peer output' "$TMP/run/prompts/$p.md"
done
grep -Fq '"status":"known"' "$TMP/run/prompts/codex-native.md"
test -f "$TMP/run/schemas/claude-cli.json"
test -f "$TMP/run/schemas/codex-cli.json"
grep -Fq '"claude-cli"' "$TMP/run/schemas/claude-cli.json"
grep -Fq '"codex-cli"' "$TMP/run/schemas/codex-cli.json"
grep -Fxq "Repository path: $repo_canonical" "$TMP/run/prompts/claude-native.md"
refute grep -Fq '"900"' "$TMP/run/rows.json"
grep -Fq '"timeout_seconds": 1800' "$TMP/run/rows.json"
refute grep -Fq '"dimensions"' "$TMP/run/rows.json"
test "$(cat "$TMP/run/scope/base")" = "$feature_base"
refute grep -Fq 'target-only' "$TMP/run/scope/diff.patch"
if GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/invalid-token" bash "$RUNNER" prepare --authorize-provider --base main --identity tokencheck --claude-model 'bad"model' > /dev/null 2> "$TMP/token.err"; then exit 1; fi
grep -Fq 'invalid Claude model token' "$TMP/token.err"

claude_prompt="$TMP/run/prompts/claude-native.md"
scope_sha="$(sed -n 's/^Scope SHA: //p' "$claude_prompt")"
scope_digest="$(sed -n 's/^Scope digest: //p' "$claude_prompt")"
cat > "$TMP/claude.txt" <<EOF
Here is an earlier example that must not win:
{"engine":"claude","model":"sonnet","transport":"claude-native","scope_sha":"$scope_sha","scope_digest":"$scope_digest","verdict":"BLOCK","findings":[{"severity":"P1","location":"old","failure_mode":"old","evidence":"old","causal_relation":"introduced","verification":"old"}]}

\`\`\`json
{"engine":"claude","model":"sonnet","transport":"claude-native","scope_sha":"$scope_sha","scope_digest":"$scope_digest","verdict":"APPROVE","findings":[],"summary":"extra metadata is tolerated"}
\`\`\`
EOF
run ingest --engine claude --text "$TMP/claude.txt"
grep -Fq '"verdict": "APPROVE"' "$TMP/run/results/claude.json"

cat > "$TMP/codex.txt" <<EOF
{"engine":"codex","model":"gpt-6.1-sol","transport":"codex-native","scope_sha":"$scope_sha","scope_digest":"$scope_digest","verdict":"BLOCK","findings":[{"severity":"P1","location":"app.txt:1","failure_mode":"broken","evidence":"fixture","causal_relation":"introduced","verification":"test","suggested_fix":"repair the fixture"}]}
EOF
run ingest --engine codex --text "$TMP/codex.txt"
run collect > "$TMP/collect.out"
grep -Fx 'GAUNTLET: BLOCK' "$TMP/collect.out"
(cd "$TMP" && env -u GAUNTLET_REPO GAUNTLET_DIR="$TMP/run" bash "$RUNNER" collect > "$TMP/other-cwd.out")
grep -Fx 'GAUNTLET: BLOCK' "$TMP/other-cwd.out"

GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/wrong-run" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity wrongrow > /dev/null
if GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/wrong-run" bash "$RUNNER" ingest --engine claude --text "$TMP/codex.txt" > /dev/null 2> "$TMP/wrong-row.err"; then exit 1; fi
grep -Fq 'no schema-valid result matching the prepared row' "$TMP/wrong-row.err"

# Repeated collection is read-only and a wrong row never replaces a result.
run collect > /dev/null
if run ingest --engine claude --text "$TMP/claude.txt" > /dev/null 2> "$TMP/duplicate.err"; then exit 1; fi
grep -Fq 'already has an accepted result' "$TMP/duplicate.err"
test -f "$TMP/run/completion/claude.done"
run collect > /dev/null

# A changed committed scope aborts dispatch and collection rather than using a
# stale review result.
printf 'again\n' > "$TMP/repo/app.txt"; git -C "$TMP/repo" commit -am again -q
if run collect > /dev/null 2> "$TMP/scope.err"; then exit 1; fi
grep -Fq 'prepared scope changed' "$TMP/scope.err"

# A fresh run with unfinished legs is honestly running.
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/run-two" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity runtwo > /dev/null
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/run-two" bash "$RUNNER" collect > "$TMP/incomplete.out" || true
grep -Fx 'GAUNTLET: RUNNING' "$TMP/incomplete.out"

# The portable CLI path produces the same envelope and provider failures stay
# failed instead of becoming an invented reviewer verdict.
mkdir "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$FAKE_CLAUDE_ARGS"
[[ -n "${FAKE_CLAUDE_CWD:-}" ]] && pwd > "$FAKE_CLAUDE_CWD"
[[ -n "${FAKE_CLAUDE_ENV:-}" ]] && printf '%s %s\n' "${GAUNTLET_DIR-unset}" "${GAUNTLET_WORKER_ENV_FILE-unset}" > "$FAKE_CLAUDE_ENV"
[[ -n "${FAKE_CLAUDE_DIFF:-}" ]] && cp diff.patch "$FAKE_CLAUDE_DIFF"
[[ -n "${FAKE_CLAUDE_SLEEP:-}" ]] && sleep "$FAKE_CLAUDE_SLEEP"
# The sk- literal is split so the repo secret scan does not flag this fixture; bash rejoins it.
printf '{"type":"system","subtype":"init","attempt":"%s"}\n' "${FAKE_CLAUDE_ATTEMPT:-first}"
if [[ "${FAKE_CLAUDE_FAIL:-}" == yes ]]; then for i in $(seq 1 100); do echo "diagnostic $i" >&2; done; echo "Authorization: Bearer sk-test""secret123456" >&2; exit 7; fi
echo 'claude stderr on success' >&2
echo "Authorization: Bearer sk-test""success987654" >&2
p="$(cat)"; model="$(sed -n 's/^Requested model: //p' <<<"$p")"
sha="$(sed -n 's/^Scope SHA: //p' <<<"$p")"; digest="$(sed -n 's/^Scope digest: //p' <<<"$p")"
printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"app.txt"}}]}}\n'
printf '{"type":"user","tool_result":"api_key=sk-test%s"}\n' "transcript24680"
printf '{"type":"result","subtype":"success","structured_output":{"engine":"claude","model":"%s","transport":"claude-cli","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}}\n' "$model" "$sha" "$digest"
EOF
cat > "$TMP/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$FAKE_CODEX_ARGS"
[[ -n "${FAKE_CODEX_ENV:-}" ]] && printf '%s %s\n' "${GAUNTLET_DIR-unset}" "${GAUNTLET_WORKER_ENV_FILE-unset}" > "$FAKE_CODEX_ENV"
workspace=""; prev=""; for arg in "$@"; do [[ "$prev" == -C ]] && workspace="$arg"; prev="$arg"; done
[[ -n "${FAKE_CODEX_DIFF:-}" ]] && cp "$workspace/diff.patch" "$FAKE_CODEX_DIFF"
printf '{"type":"item.completed","item":{"type":"command_execution","command":"cat app.txt"}}\n'
if [[ "${FAKE_CODEX_FAIL:-}" == yes ]]; then echo 'codex provider failed' >&2; exit 8; fi
p="$(cat)"; model="$(sed -n 's/^Requested model: //p' <<<"$p")"
sha="$(sed -n 's/^Scope SHA: //p' <<<"$p")"; digest="$(sed -n 's/^Scope digest: //p' <<<"$p")"
out=""; prev=""; for arg in "$@"; do [[ "$prev" == --output-last-message ]] && out="$arg"; prev="$arg"; done
printf '{"engine":"codex","model":"%s","transport":"codex-cli","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$model" "$sha" "$digest" > "$out"
EOF
# A fake wall clock that never moves: a duration taken from it would be 0.
mkdir "$TMP/frozen-clock"
cat > "$TMP/frozen-clock/date" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do case "$arg" in +%s) echo 946684800; exit 0 ;; +%Y%m%dT%H%M%SZ) echo 20000101T000000Z; exit 0 ;; +*) echo 2000-01-01T00:00:00Z; exit 0 ;; esac; done
echo 'Sat Jan  1 00:00:00 UTC 2000'
EOF
chmod +x "$TMP/frozen-clock/date"
REAL_TIMEOUT="$(command -v timeout)"
cat > "$TMP/bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$2" in
  claude) printf '%s\n' "$1" > "$FAKE_CLAUDE_TIMEOUT" ;;
  codex) printf '%s\n' "$1" > "$FAKE_CODEX_TIMEOUT" ;;
esac
exec "$REAL_TIMEOUT" "$@"
EOF
chmod +x "$TMP/bin/claude" "$TMP/bin/codex" "$TMP/bin/timeout"
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/cli-run" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity cli > /dev/null
PATH="$TMP/frozen-clock:$TMP/bin:$PATH" FAKE_CLAUDE_SLEEP=2 FAKE_CLAUDE_DIFF="$TMP/claude.diff" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/codex.timeout" GAUNTLET_PROVIDER_TIMEOUT_SECONDS=88 GAUNTLET_TIMEOUT_CLAUDE_SECONDS=17 FAKE_CLAUDE_ARGS="$TMP/claude.args" FAKE_CLAUDE_CWD="$TMP/claude.cwd" FAKE_CLAUDE_ENV="$TMP/claude.env" GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/cli-run" bash "$RUNNER" run-cli --engine claude
PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/codex.timeout" GAUNTLET_PROVIDER_TIMEOUT_SECONDS=88 FAKE_CODEX_DIFF="$TMP/codex.diff" FAKE_CODEX_ARGS="$TMP/codex.args" FAKE_CODEX_ENV="$TMP/codex.env" GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/cli-run" bash "$RUNNER" run-cli --engine codex
wait_for_leg "$TMP/cli-run" claude
wait_for_leg "$TMP/cli-run" codex
grep -Fq -- 'model_reasoning_effort=low -m gpt-6.1-sol' "$TMP/codex.args"
grep -Fq -- '--safe-mode' "$TMP/claude.args"
grep -Fq -- '--mcp-config' "$TMP/claude.args"
grep -Fq -- '--strict-mcp-config' "$TMP/claude.args"
grep -Fq -- '--no-session-persistence' "$TMP/claude.args"
grep -Fq -- '--output-format stream-json --verbose' "$TMP/claude.args"
refute grep -Fq -- "$TMP/cli-run" "$TMP/claude.args"
# Each leg found the pinned diff as ./diff.patch in its own working directory.
cmp "$TMP/claude.diff" "$TMP/cli-run/scope/diff.patch"
cmp "$TMP/codex.diff" "$TMP/cli-run/scope/diff.patch"
grep -Fq -- '--permission-mode dontAsk' "$TMP/claude.args"
grep -Fq -- '--tools Read,Grep,Glob' "$TMP/claude.args"
grep -Fq -- '--json-schema' "$TMP/claude.args"
grep -Fq -- '--ignore-user-config' "$TMP/codex.args"
grep -Fq -- '--strict-config' "$TMP/codex.args"
grep -Fq -- '--sandbox read-only' "$TMP/codex.args"
grep -Fq -- '--ephemeral' "$TMP/codex.args"
grep -Fq -- 'exec --json' "$TMP/codex.args"
grep -Fq -- 'project_doc_max_bytes=0' "$TMP/codex.args"
grep -Fq -- 'project_doc_fallback_filenames=[]' "$TMP/codex.args"
grep -Fq -- '--output-schema' "$TMP/codex.args"
# Environment overrides of --timeout-seconds, as in doc-gauntlet.sh: per engine, then generic.
test "$(cat "$TMP/claude.timeout")" = 17
test "$(cat "$TMP/codex.timeout")" = 88
claude_cwd="$(cat "$TMP/claude.cwd")"; codex_cwd="$(sed -n 's/.*-C \([^ ]*\).*/\1/p' "$TMP/codex.args")"
[[ "$claude_cwd" != "$TMP/cli-run"* && "$codex_cwd" != "$TMP/cli-run"* ]]
test "$(cat "$TMP/claude.env")" = 'unset unset'
test "$(cat "$TMP/codex.env")" = 'unset unset'
test ! -e "$TMP/cli-run/worker-env-claude.sh"
test ! -e "$TMP/cli-run/worker-env-codex.sh"
test ! -e "$claude_cwd"
test ! -e "$codex_cwd"
test -z "$(find "$TMP/cli-run/scope" -name 'live.*' -print -quit)"
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/cli-run" bash "$RUNNER" collect > "$TMP/cli.collect"
grep -Fx 'GAUNTLET: APPROVE' "$TMP/cli.collect"
# A successful leg keeps its transcript, its stderr and its start and end time in the archive; the
# private archive holds them unredacted, and nothing reaches the reviewed repository.
cli_archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/cli.collect")"
grep -Fq '"tool_use","name":"Read"' "$cli_archive"/raw/claude-cli-*.transcript.jsonl
grep -Fq 'claude stderr on success' "$cli_archive"/raw/claude-cli-*.stderr
refute grep -rFq 'sk-testsuccess' "$TMP/repo"
refute grep -rFq 'sk-testtranscript' "$TMP/repo"
# The private archive keeps evidence verbatim: redacting it would fail here.
grep -Fq "Authorization: Bearer sk-test""success987654" "$cli_archive"/raw/claude-cli-*.stderr
grep -Fq "api_key=sk-test""transcript24680" "$cli_archive"/raw/claude-cli-*.transcript.jsonl
test -z "$(git -C "$TMP/repo" status --porcelain)"
grep -Fq 'command_execution' "$cli_archive"/raw/codex-cli-*.transcript.jsonl
grep -Fq '"transport":"codex-cli"' "$cli_archive"/raw/codex-cli-*.txt
python3 - "$cli_archive" <<'PY'
import json, pathlib, sys
archive = pathlib.Path(sys.argv[1])
legs = [json.loads(line) for line in (archive / "raw" / "legs.jsonl").read_text().splitlines()]
assert sorted(leg["engine"] for leg in legs) == ["claude", "codex"], legs
for leg in legs:
    assert leg["exit_code"] == 0, leg
    assert leg["started_at"] and leg["ended_at"], leg
    assert isinstance(leg["seconds"], int) and leg["seconds"] >= 0, leg
    assert list((archive / "raw").glob(leg["attempt"] + ".*")), leg
# The claude leg ran under a frozen wall clock and slept 2 s: only a monotonic duration sees it.
claude = next(leg for leg in legs if leg["engine"] == "claude")
assert claude["started_at"] == claude["ended_at"] == "2000-01-01T00:00:00Z", claude
assert claude["seconds"] >= 2, claude
PY
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/failed-cli-run" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity failedcli > /dev/null
PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/failed-claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/failed-codex.timeout" FAKE_CLAUDE_ARGS="$TMP/failed-claude.args" FAKE_CLAUDE_FAIL=yes GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/failed-cli-run" bash "$RUNNER" run-cli --engine claude
PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/failed-claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/failed-codex.timeout" FAKE_CODEX_ARGS="$TMP/failed-codex.args" FAKE_CODEX_FAIL=yes GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/failed-cli-run" bash "$RUNNER" run-cli --engine codex
wait_for_leg "$TMP/failed-cli-run" claude
wait_for_leg "$TMP/failed-cli-run" codex
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/failed-cli-run" bash "$RUNNER" collect > "$TMP/failed-cli.out" || true
grep -Fx 'GAUNTLET: FAILED' "$TMP/failed-cli.out"
grep -Fx 'FAILED: claude codex' "$TMP/failed-cli.out"
test -f "$TMP/failed-cli-run/results/gauntlet-failed.json"
python3 - "$TMP/failed-cli-run/results/gauntlet-failed.json" <<'PY'
import json, sys
data=json.load(open(sys.argv[1]))
assert data['outcome'] == 'all-legs-failed'
assert [leg['leg'] for leg in data['legs']] == ['claude', 'codex']
assert all('exit_code' in leg and 'failure' in leg for leg in data['legs'])
PY
( mkdir "$TMP/failed-cli-run/locks/lifecycle.lock"; while [[ ! -f "$TMP/release-lifecycle-lock" ]]; do sleep 0.01; done; rmdir "$TMP/failed-cli-run/locks/lifecycle.lock" ) & lifecycle_holder=$!
while [[ ! -d "$TMP/failed-cli-run/locks/lifecycle.lock" ]]; do sleep 0.01; done
if GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/failed-cli-run" bash "$RUNNER" run-cli --engine claude > /dev/null 2> "$TMP/concurrent-retry.err"; then exit 1; fi
grep -Fq 'run state is being collected or updated' "$TMP/concurrent-retry.err"
test -f "$TMP/failed-cli-run/completion/claude.done"
test -f "$TMP/failed-cli-run/results/gauntlet-failed.json"
touch "$TMP/release-lifecycle-lock"
wait "$lifecycle_holder"
grep -Fq '<redacted>' "$TMP/failed-cli-run/failures/claude.txt"
grep -Fq '<diagnostic truncated>' "$TMP/failed-cli-run/failures/claude.txt"
refute grep -Fq 'sk-testsecret' "$TMP/failed-cli-run/failures/claude.txt"
# A failed leg keeps its partial transcript and untrimmed diagnostic in the archive, not only the trimmed summary.
failed_archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/failed-cli.out")"
grep -Fq 'diagnostic 50' "$failed_archive"/raw/claude-cli-*.stderr
grep -Fq "Authorization: Bearer sk-test""secret123456" "$failed_archive"/raw/claude-cli-*.stderr
refute grep -rFq 'sk-testsecret' "$TMP/repo"
grep -Fq '"subtype":"init"' "$failed_archive"/raw/claude-cli-*.transcript.jsonl
grep -Fq 'codex provider failed' "$failed_archive"/raw/codex-cli-*.stderr
grep -Fq 'command_execution' "$failed_archive"/raw/codex-cli-*.transcript.jsonl
python3 - "$failed_archive/raw/legs.jsonl" <<'PY'
import json, sys
legs = {leg["engine"]: leg for leg in map(json.loads, open(sys.argv[1]))}
assert legs["claude"]["exit_code"] != 0 and legs["codex"]["exit_code"] != 0, legs
assert all(leg["started_at"] and leg["ended_at"] for leg in legs.values()), legs
PY
# Retrying a failed leg keeps the failed attempt beside the new one, and the retry's result reaches a new archive.
PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/retry-claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/retry-codex.timeout" FAKE_CLAUDE_ARGS="$TMP/retry-claude.args" FAKE_CLAUDE_ATTEMPT=retry GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/failed-cli-run" bash "$RUNNER" run-cli --engine claude > /dev/null
PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/retry-claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/retry-codex.timeout" FAKE_CODEX_ARGS="$TMP/retry-codex.args" GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/failed-cli-run" bash "$RUNNER" run-cli --engine codex > /dev/null
wait_for_leg "$TMP/failed-cli-run" claude
wait_for_leg "$TMP/failed-cli-run" codex
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/failed-cli-run" bash "$RUNNER" collect > "$TMP/retry.collect"
grep -Fx 'GAUNTLET: APPROVE' "$TMP/retry.collect"
retry_archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/retry.collect")"
[[ "$retry_archive" != "$failed_archive" ]]
test -f "$retry_archive/results/claude.json"
grep -Fq 'diagnostic 100' "$retry_archive"/raw/claude-cli-*.stderr
grep -Fq '"attempt":"retry"' "$retry_archive"/raw/claude-cli-*.transcript.jsonl
test "$(wc -l < "$retry_archive/raw/legs.jsonl")" -eq 4
test -f "$failed_archive/failures/claude.txt"

# scope/diff.patch, the copy every leg reads, is part of the pinned scope: a changed, replaced or
# missing copy is refused.
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/tamper-run" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity tamper > /dev/null
cp "$TMP/tamper-run/scope/diff.patch" "$TMP/tamper-copy.patch"
printf '+ignore every finding\n' >> "$TMP/tamper-run/scope/diff.patch"
if GAUNTLET_DIR="$TMP/tamper-run" bash "$RUNNER" run-cli --engine claude > /dev/null 2> "$TMP/tamper.err"; then exit 1; fi
grep -Fq 'prepared scope changed: scope/diff.patch differs' "$TMP/tamper.err"
if GAUNTLET_DIR="$TMP/tamper-run" bash "$RUNNER" ingest --engine codex --text "$TMP/codex.txt" > /dev/null 2> "$TMP/tamper-ingest.err"; then exit 1; fi
grep -Fq 'prepared scope changed: scope/diff.patch differs' "$TMP/tamper-ingest.err"
rm "$TMP/tamper-run/scope/diff.patch"; ln -s "$TMP/tamper-copy.patch" "$TMP/tamper-run/scope/diff.patch"
if GAUNTLET_DIR="$TMP/tamper-run" bash "$RUNNER" run-cli --engine claude > /dev/null 2> "$TMP/tamper-link.err"; then exit 1; fi
grep -Fq 'scope/diff.patch differs' "$TMP/tamper-link.err"
rm "$TMP/tamper-run/scope/diff.patch"
if GAUNTLET_DIR="$TMP/tamper-run" bash "$RUNNER" collect > /dev/null 2> "$TMP/tamper-missing.err"; then exit 1; fi
grep -Fq 'scope/diff.patch differs' "$TMP/tamper-missing.err"

# --timeout-seconds is pinned into the run's config at prepare; a per-engine
# environment override still wins for that leg; run-cli and collect show the bound each leg ran with.
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/timeout-pin-run" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity timeoutpin --timeout-seconds 63 > /dev/null
grep -Fq '"timeout_seconds": 63' "$TMP/timeout-pin-run/rows.json"
PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/pin-claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/pin-codex.timeout" FAKE_CLAUDE_ARGS="$TMP/pin-claude.args" GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/timeout-pin-run" bash "$RUNNER" run-cli --engine claude > "$TMP/timeout-pin.launch"
grep -Fx 'leg claude started: bound 63s' "$TMP/timeout-pin.launch"
wait_for_leg "$TMP/timeout-pin-run" claude
test "$(cat "$TMP/pin-claude.timeout")" = 63
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/timeout-pin-run" bash "$RUNNER" collect > "$TMP/timeout-pin.collect" || true
grep -Fx 'GAUNTLET: RUNNING' "$TMP/timeout-pin.collect"
grep -Fx 'BOUND: claude 63s' "$TMP/timeout-pin.collect"
PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/pin-claude-env.timeout" FAKE_CODEX_TIMEOUT="$TMP/pin-codex-env.timeout" FAKE_CODEX_ARGS="$TMP/pin-codex.args" GAUNTLET_TIMEOUT_CODEX_SECONDS=9 GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/timeout-pin-run" bash "$RUNNER" run-cli --engine codex > "$TMP/timeout-pin-codex.launch"
grep -Fx 'leg codex started: bound 9s' "$TMP/timeout-pin-codex.launch"
wait_for_leg "$TMP/timeout-pin-run" codex
test "$(cat "$TMP/pin-codex-env.timeout")" = 9
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/timeout-pin-run" bash "$RUNNER" collect > "$TMP/timeout-pin-both.collect"
grep -Fx 'GAUNTLET: APPROVE' "$TMP/timeout-pin-both.collect"
grep -Fx 'BOUND: claude 63s' "$TMP/timeout-pin-both.collect"
grep -Fx 'BOUND: codex 9s' "$TMP/timeout-pin-both.collect"

# A leg that dies on timeout (exit 124) is reported as a timeout, not a
# generic diagnostic dump, so a truncated verdict can never be mistaken for
# a reviewer result.
mkdir "$TMP/timeout-bin"
cat > "$TMP/timeout-bin/timeout" <<'EOF'
#!/usr/bin/env bash
exit 124
EOF
chmod +x "$TMP/timeout-bin/timeout"
mkdir "$TMP/bin3"
cat > "$TMP/bin3/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
p="$(cat)"; sha="$(sed -n 's/^Scope SHA: //p' <<<"$p")"; digest="$(sed -n 's/^Scope digest: //p' <<<"$p")"
out=""; prev=""; for arg in "$@"; do [[ "$prev" == --output-last-message ]] && out="$arg"; prev="$arg"; done
printf '{"engine":"codex","model":"gpt-6.1-sol","transport":"codex-cli","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$sha" "$digest" > "$out"
EOF
chmod +x "$TMP/bin3/codex"
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/timeout-run" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity timeoutrun --timeout-seconds 5 > /dev/null
PATH="$TMP/bin3:$PATH" GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/timeout-run" bash "$RUNNER" run-cli --engine codex > /dev/null
PATH="$TMP/timeout-bin:$PATH" GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/timeout-run" bash "$RUNNER" run-cli --engine claude > "$TMP/timeout-run.launch"
grep -Fx 'leg claude started: bound 5s' "$TMP/timeout-run.launch"
wait_for_leg "$TMP/timeout-run" codex
wait_for_leg "$TMP/timeout-run" claude
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/timeout-run" bash "$RUNNER" collect > "$TMP/timeout-run.collect" || true
grep -Fx 'GAUNTLET: FAILED' "$TMP/timeout-run.collect"
grep -Fx 'FAILED: claude' "$TMP/timeout-run.collect"
grep -Fx 'claude: timed out after 5s' "$TMP/timeout-run.collect"
grep -Fx 'BOUND: claude 5s' "$TMP/timeout-run.collect"

# Pair substitution is exactly two distinct engines; Grok can replace one slot.
if GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/three-engines" bash "$RUNNER" prepare --authorize-provider --base main --identity engines --engines claude,codex,grok > /dev/null 2> "$TMP/three.err"; then exit 1; fi
grep -Fq 'prepare requires exactly two engines' "$TMP/three.err"
if GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/dup-engines" bash "$RUNNER" prepare --authorize-provider --base main --identity engines --engines grok,grok > /dev/null 2> "$TMP/dup.err"; then exit 1; fi
grep -Fq 'engines must be distinct' "$TMP/dup.err"
if GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/unknown-engine" bash "$RUNNER" prepare --authorize-provider --base main --identity engines --engines grok,gemini > /dev/null 2> "$TMP/unknown.err"; then exit 1; fi
grep -Fq 'unknown engine: gemini' "$TMP/unknown.err"

GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/grok-run" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity grok --engines grok,codex --prior-findings "$TMP/prior-findings.json" > /dev/null
test -f "$TMP/grok-run/prompts/grok-cli.md"
test -f "$TMP/grok-run/prompts/grok-native.md"
test -f "$TMP/grok-run/schemas/grok-cli.json"
test ! -e "$TMP/grok-run/prompts/claude-cli.md"
test ! -e "$TMP/grok-run/schemas/claude-cli.json"
grep -Fq 'requires transport "grok-cli"' "$TMP/grok-run/prompts/grok-cli.md"
for p in grok-cli grok-native; do
  grep -Fq 'A test must fail when the behaviour it names breaks.' "$TMP/grok-run/prompts/$p.md"
  grep -Fq 'A new refusal, flag, limit or boundary with no test that fails when it is switched off is a material finding.' "$TMP/grok-run/prompts/$p.md"
  grep -Fq 'report it only when that load has a concrete consequence' "$TMP/grok-run/prompts/$p.md"
  grep -Fq 'This round reviews the whole pinned diff, not only the repair of these findings.' "$TMP/grok-run/prompts/$p.md"
  grep -Fq 'prior-round context supplied above is not peer output' "$TMP/grok-run/prompts/$p.md"
done
grep -Fq '"engines": ["grok", "codex"]' "$TMP/grok-run/rows.json"
if GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/grok-run" bash "$RUNNER" run-cli --engine claude > /dev/null 2> "$TMP/unprepared.err"; then exit 1; fi
grep -Fq 'claude is not in this run' "$TMP/unprepared.err"

cat > "$TMP/bin/grok" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$FAKE_GROK_ARGS"
[[ -n "${FAKE_GROK_CWD:-}" ]] && pwd > "$FAKE_GROK_CWD"
[[ -f .grok/sandbox.toml ]] || { echo 'missing grok sandbox profile' >&2; exit 1; }
grep -Fq 'extends = "strict"' .grok/sandbox.toml
grep -Eq '^read_only = \["[^"]+"\]$' .grok/sandbox.toml
[[ -s diff.patch ]] || { echo 'missing ./diff.patch' >&2; exit 1; }
mkdir -p "$GROK_HOME/sessions"; printf '{"session":"fake-grok"}\n' > "$GROK_HOME/sessions/s1.jsonl"
grep -Eq '^deny = \[' .grok/sandbox.toml
grep -Fq 'AGENTS.md' .grok/sandbox.toml
if grep -Fq '/sessions' .grok/sandbox.toml; then echo 'sandbox names sessions' >&2; exit 1; fi
grep -Fq '/.gauntlet' .grok/sandbox.toml
[[ -n "${FAKE_GROK_ENV:-}" ]] && printf '%s %s\n' "${GAUNTLET_DIR-unset}" "${GAUNTLET_WORKER_ENV_FILE-unset}" > "$FAKE_GROK_ENV"
prompt=""
prev=""
for arg in "$@"; do
  [[ "$prev" == --prompt-file ]] && prompt="$arg"
  prev="$arg"
done
p="$(cat "$prompt")"
model="$(sed -n 's/^Requested model: //p' <<<"$p")"
sha="$(sed -n 's/^Scope SHA: //p' <<<"$p")"; digest="$(sed -n 's/^Scope digest: //p' <<<"$p")"
printf '{"engine":"grok","model":"%s","transport":"grok-cli","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$model" "$sha" "$digest"
EOF
chmod +x "$TMP/bin/grok"
cat > "$TMP/bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$2" in
  claude) printf '%s\n' "$1" > "$FAKE_CLAUDE_TIMEOUT" ;;
  codex) printf '%s\n' "$1" > "$FAKE_CODEX_TIMEOUT" ;;
  grok) printf '%s\n' "$1" > "$FAKE_GROK_TIMEOUT" ;;
esac
exec "$REAL_TIMEOUT" "$@"
EOF
chmod +x "$TMP/bin/timeout"
PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_GROK_TIMEOUT="$TMP/grok.timeout" FAKE_CODEX_TIMEOUT="$TMP/grok-codex.timeout" GAUNTLET_TIMEOUT_GROK_SECONDS=31 FAKE_GROK_ARGS="$TMP/grok.args" FAKE_GROK_CWD="$TMP/grok.cwd" FAKE_GROK_ENV="$TMP/grok.env" GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/grok-run" bash "$RUNNER" run-cli --engine grok
PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_GROK_TIMEOUT="$TMP/grok.timeout" FAKE_CODEX_TIMEOUT="$TMP/grok-codex.timeout" FAKE_CODEX_ARGS="$TMP/grok-codex.args" FAKE_CODEX_ENV="$TMP/grok-codex.env" GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/grok-run" bash "$RUNNER" run-cli --engine codex
wait_for_leg "$TMP/grok-run" grok
wait_for_leg "$TMP/grok-run" codex
grep -Fq -- '--prompt-file' "$TMP/grok.args"
grep -Fq -- '--json-schema' "$TMP/grok.args"
grep -Eq -- '--sandbox g[0-9a-f]{16}' "$TMP/grok.args"
refute grep -Fq -- '--sandbox gauntlet ' "$TMP/grok.args"
refute grep -Fq -- '--sandbox read-only' "$TMP/grok.args"
grep -Fq -- '--permission-mode dontAsk' "$TMP/grok.args"
grep -Fq -- '--tools read_file,grep,list_dir' "$TMP/grok.args"
grep -Fq -- '--disallowed-tools Agent,search_tool,use_tool' "$TMP/grok.args"
grep -Fq -- '--no-subagents' "$TMP/grok.args"
grep -Fq -- '--disable-web-search' "$TMP/grok.args"
refute grep -Fq -- '--cwd' "$TMP/grok.args"
test "$(cat "$TMP/grok.timeout")" = 31
test "$(cat "$TMP/grok.env")" = 'unset unset'
grok_cwd="$(cat "$TMP/grok.cwd")"
[[ "$grok_cwd" != "$TMP/grok-run"* ]]
test ! -e "$grok_cwd"
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/grok-run" bash "$RUNNER" collect > "$TMP/grok.collect"
grep -Fx 'GAUNTLET: APPROVE' "$TMP/grok.collect"
# Grok's session files reach the archive; its copied credentials never do.
grok_archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/grok.collect")"
grep -Fq 'fake-grok' "$grok_archive"/raw/grok-cli-*.sessions/s1.jsonl
test -z "$(find "$grok_archive" -name auth.json -print -quit)"
test -f "$TMP/grok-run/results/grok.json"
test ! -e "$TMP/grok-run/results/claude.json"

# A tracked public environment template is review scope, while real environment files remain blocked.
# These branches read and write a record of their own.
export GAUNTLET_ROUND_RECORD="$TMP/branch-rounds.jsonl"
git -C "$TMP/repo" checkout -qb public-env-example feature
printf 'PUBLIC_SETTING=example\n' > "$TMP/repo/.env.example"
git -C "$TMP/repo" add .env.example && git -C "$TMP/repo" commit -qm public-env-example
GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/public-env-example-run" bash "$RUNNER" prepare --authorize-provider --base feature --identity publicenv > /dev/null
test -f "$TMP/public-env-example-run/scope/diff.patch"
grep -Fq '.env.example' "$TMP/public-env-example-run/scope/diff.patch"

# Secret paths fail before prompt creation or provider invocation.
git -C "$TMP/repo" checkout -qb secret feature
printf 'secret\n' > "$TMP/repo/.env.production"; git -C "$TMP/repo" add . && git -C "$TMP/repo" commit -qm secret
mkdir -p "$TMP/repo/secrets"; printf 'key\n' > "$TMP/repo/secrets/app.pem"; printf 'visible\n' > "$TMP/repo/visible.txt"
git -C "$TMP/repo" add . && git -C "$TMP/repo" commit -qm directory-secret
if GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/secret-run" bash "$RUNNER" prepare --authorize-provider --base feature --identity secretpath > /dev/null 2> "$TMP/secret.err"; then exit 1; fi
grep -Fq '.env.production' "$TMP/secret.err"
if GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/excluded-secret-run" bash "$RUNNER" prepare --authorize-provider --base feature --identity excludedsecret --exclude .env.production --exclude secrets > /dev/null 2> "$TMP/excluded-secret.err"; then exit 1; fi
grep -Fq '.env.production' "$TMP/excluded-secret.err"

GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$TMP/run-two" bash "$RUNNER" clean --force
test ! -e "$TMP/run-two"

# ---------------------------------------------------------------------------
# Rounds: identity on prepare, the round record, the pre-review field, and what
# prepare and collect print. This block runs in its own scratch repository with
# its own record file, isolated from the scenarios above and from the operator's
# real record. There is no round cap: nothing here is refused for its round.
# ---------------------------------------------------------------------------
ROUNDS="$TMP/rounds"
mkdir -p "$ROUNDS" "$TMP/fixtures"
export GAUNTLET_ROUND_RECORD="$ROUNDS/record/rounds.jsonl"
RECORD="$ROUNDS/record/rounds.jsonl"
SCRATCH_REPO="$ROUNDS/repo"

new_scratch_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.invalid
  printf 'base\n' > "$1/app.txt"
  git -C "$1" add app.txt
  git -C "$1" commit -qm base
}
scratch_prepare() {
  local dir="$1"; shift
  GAUNTLET_REPO="$SCRATCH_REPO" GAUNTLET_DIR="$dir" bash "$RUNNER" prepare --authorize-provider --base main --profile fast "$@"
}
scratch_run() {
  local dir="$1"; shift
  GAUNTLET_REPO="$SCRATCH_REPO" GAUNTLET_DIR="$dir" bash "$RUNNER" "$@"
}
# Accepts a native fixture result, which is the ingest_locked append path.
scratch_accept() {
  local dir="$1" engine="${2:-claude}" prompt model sha digest fixture
  prompt="$dir/prompts/$engine-native.md"
  model="$(sed -n 's/^Requested model: //p' "$prompt")"
  sha="$(sed -n 's/^Scope SHA: //p' "$prompt")"
  digest="$(sed -n 's/^Scope digest: //p' "$prompt")"
  fixture="$TMP/fixtures/$(basename "$dir")-$engine.json"
  printf '{"engine":"%s","model":"%s","transport":"%s-native","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' \
    "$engine" "$model" "$engine" "$sha" "$digest" > "$fixture"
  GAUNTLET_REPO="$SCRATCH_REPO" GAUNTLET_DIR="$dir" bash "$RUNNER" ingest --engine "$engine" --text "$fixture"
}
# Runs a leg through the fixture CLI worker, which is the finish_cli_leg append
# path. FAKE_CLAUDE_FAIL/FAKE_CODEX_FAIL in the caller's environment make it fail.
scratch_cli() {
  local dir="$1" engine="$2"
  PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" \
    FAKE_CLAUDE_TIMEOUT="$TMP/rounds-claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/rounds-codex.timeout" \
    FAKE_CLAUDE_ARGS="$TMP/rounds-claude.args" FAKE_CODEX_ARGS="$TMP/rounds-codex.args" \
    FAKE_CLAUDE_FAIL="${FAKE_CLAUDE_FAIL:-}" FAKE_CODEX_FAIL="${FAKE_CODEX_FAIL:-}" \
    GAUNTLET_REPO="$SCRATCH_REPO" GAUNTLET_DIR="$dir" bash "$RUNNER" run-cli --engine "$engine" > /dev/null
  wait_for_leg "$dir" "$engine"
  # The round line precedes the sentinel: the moment the sentinel is visible,
  # an accepted result already has its line on disk (or its recorded failure).
  if [[ -f "$dir/results/$engine.json" ]]; then
    [[ -d "$dir/round-recorded" || -f "$dir/failures/round-record.txt" ]] || { printf 'sentinel published before the round line in %s\n' "$dir" >&2; exit 1; }
  fi
  # The launch lock is released last, so the leg is entirely finished once it
  # is gone.
  local attempts=0
  while [[ -d "$dir/locks/$engine.lock" && "$attempts" -lt 1200 ]]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done
  [[ ! -d "$dir/locks/$engine.lock" ]] || { printf 'timed out waiting for the %s leg to settle in %s\n' "$engine" "$dir" >&2; exit 1; }
}
record_lines() { if [[ -f "$1" ]]; then awk 'END {print NR}' "$1"; else printf '0\n'; fi; }
file_mode() { python3 -c 'import os,stat,sys; print(f"{stat.S_IMODE(os.lstat(sys.argv[1]).st_mode):o}")' "$1"; }

new_scratch_repo "$ROUNDS/repo"
git -C "$ROUNDS/repo" checkout -qb work
printf 'A\n' > "$ROUNDS/repo/app.txt"
git -C "$ROUNDS/repo" commit -qam commit-a

# 1. prepare requires exactly one identity, and refuses a malformed one.
rc=0; scratch_prepare "$ROUNDS/t1a" > /dev/null 2> "$TMP/t1a.err" || rc=$?
test "$rc" -eq 1
grep -Fq 'prepare requires exactly one of --pr <number> or --identity <token>' "$TMP/t1a.err"
grep -Fq 're-run with --pr <n> for a pull request or --identity <branch> otherwise' "$TMP/t1a.err"
test ! -e "$ROUNDS/t1a"
test ! -e "$ROUNDS/record"
rc=0; scratch_prepare "$ROUNDS/t1b" --pr 7 --identity work > /dev/null 2> "$TMP/t1b.err" || rc=$?
test "$rc" -eq 1
grep -Fq 'prepare requires exactly one of --pr <number> or --identity <token>' "$TMP/t1b.err"
for bad in 0 -1 abc 1.5; do
  rc=0; scratch_prepare "$ROUNDS/t1c" --pr "$bad" > /dev/null 2> "$TMP/t1c.err" || rc=$?
  test "$rc" -eq 1
  grep -Fq -- '--pr must be a positive whole number' "$TMP/t1c.err"
done
rc=0; scratch_prepare "$ROUNDS/t1d" --identity 'bad token' > /dev/null 2> "$TMP/t1d.err" || rc=$?
test "$rc" -eq 1
grep -Fq -- '--identity token may contain only letters, numbers, dot, underscore, colon, slash and hyphen (1 to 120 characters)' "$TMP/t1d.err"


# 2. Round 1 on commit A: prepare prints the record status and the round, and
# nothing is recorded until the run's first valid result is accepted. A second
# accepted result on the same run appends nothing.
scratch_prepare "$ROUNDS/r-a1" --pr 7 > "$TMP/t2.out"
test "$(head -n 1 "$TMP/t2.out")" = "ROUND-RECORD: non-default $RECORD"
test "$(sed -n 2p "$TMP/t2.out")" = 'ROUND: 1 identity=pr:7 repo=rounds/repo'
test "$(tail -n 1 "$TMP/t2.out")" = "GAUNTLET_DIR=$ROUNDS/r-a1"
test "$(record_lines "$RECORD")" -eq 0
test "$(file_mode "$RECORD")" = 600
test "$(file_mode "$ROUNDS/record")" = 700
scratch_cli "$ROUNDS/r-a1" claude
test -d "$ROUNDS/r-a1/round-recorded"
test "$(record_lines "$RECORD")" -eq 1
python3 - "$RECORD" "$ROUNDS/r-a1" <<'PY'
import json, pathlib, sys
entry = json.loads(open(sys.argv[1]).read().splitlines()[0])
run = pathlib.Path(sys.argv[2])
assert entry["runner"] == "gauntlet", entry
assert entry["identity"] == "pr:7", entry
assert entry["round"] == 1 and entry["pre_review"] is None, entry
assert entry["digest"] == (run / "scope" / "digest").read_text().strip(), entry
assert entry["head"] == (run / "scope" / "head").read_text().strip(), entry
assert entry["repo"].endswith("/.git"), entry
assert entry["ts"].endswith("+00:00") and entry["ts"][10] == "T", entry
assert list(entry) == ["ts", "runner", "repo", "identity", "digest", "head", "round", "pre_review"], entry
PY
scratch_accept "$ROUNDS/r-a1" codex
test "$(record_lines "$RECORD")" -eq 1

# 3. The same content again is a retry: reported, and it records its own line.
# The line survives a HEAD that moves before collect; a run cleaned before any
# result records nothing and its content stays new.
scratch_prepare "$ROUNDS/r-a2" --pr 7 > "$TMP/t3.out"
grep -Fxq 'ROUND: 1 (retry of recorded round 1) identity=pr:7 repo=rounds/repo' "$TMP/t3.out"
scratch_accept "$ROUNDS/r-a2" claude
test "$(record_lines "$RECORD")" -eq 2
python3 -c 'import json,sys; assert json.loads(open(sys.argv[1]).read().splitlines()[1])["round"] == 1' "$RECORD"
printf 'B\n' > "$ROUNDS/repo/app.txt"
git -C "$ROUNDS/repo" commit -qam commit-b
test "$(record_lines "$RECORD")" -eq 2
rc=0; scratch_run "$ROUNDS/r-a2" collect > /dev/null 2> "$TMP/t3b.err" || rc=$?
test "$rc" -ne 0
grep -Fq 'prepared scope changed' "$TMP/t3b.err"
scratch_prepare "$ROUNDS/r-b0" --pr 7 > /dev/null
scratch_run "$ROUNDS/r-b0" clean --force
test ! -e "$ROUNDS/r-b0"
test "$(record_lines "$RECORD")" -eq 2

# 4. Commit B is round 2. The count survives clean.
scratch_prepare "$ROUNDS/r-b1" --pr 7 > "$TMP/t4.out"
grep -Fxq 'ROUND: 2 identity=pr:7 repo=rounds/repo' "$TMP/t4.out"
scratch_accept "$ROUNDS/r-b1" claude
test "$(record_lines "$RECORD")" -eq 3
scratch_run "$ROUNDS/r-a2" clean --force
scratch_run "$ROUNDS/r-b1" clean --force
test "$(record_lines "$RECORD")" -eq 3

# 5. Commit C is round 3 and is not refused. The retired flags are accepted and
# ignored, and --pre-reviewed-by is recorded on the line and in rows.json.
printf 'C\n' > "$ROUNDS/repo/app.txt"
printf 'extra\n' > "$ROUNDS/repo/extra.txt"
git -C "$ROUNDS/repo" add extra.txt
git -C "$ROUNDS/repo" commit -qam commit-c
scratch_prepare "$ROUNDS/r-c1" --pr 7 --override-round-budget "bounded: anything" --supersedes pr:1 --pre-reviewed-by gpt-5.6-terra > "$TMP/t5.out"
grep -Fxq 'ROUND: 3 identity=pr:7 repo=rounds/repo' "$TMP/t5.out"
refute grep -q '^OVERRIDE' "$TMP/t5.out"
scratch_accept "$ROUNDS/r-c1" claude
test "$(record_lines "$RECORD")" -eq 4
python3 - "$RECORD" "$ROUNDS/r-c1/rows.json" <<'PY'
import json, sys
entry = json.loads(open(sys.argv[1]).read().splitlines()[3])
assert entry["round"] == 3 and entry["pre_review"] == "gpt-5.6-terra", entry
assert "override" not in entry and "lineage" not in entry, entry
rows = json.load(open(sys.argv[2]))
for key in ("identity", "round", "retry", "pre_review", "digest", "head", "repo",
            "repo_short", "round_record", "round_record_default"):
    assert key in rows, key
assert rows["identity"] == "pr:7" and rows["round"] == 3 and rows["retry"] is False, rows
assert rows["pre_review"] == "gpt-5.6-terra" and rows["round_record_default"] is False, rows
assert rows["timeout_seconds"] == 1800 and rows["engines"] == ["claude", "codex"], rows
PY

# A malformed pre-review token is refused before anything is written.
rc=0; scratch_prepare "$ROUNDS/r-c2" --pr 7 --pre-reviewed-by 'bad model' > /dev/null 2> "$TMP/t5b.err" || rc=$?
test "$rc" -eq 1
grep -Fq 'invalid --pre-reviewed-by model token' "$TMP/t5b.err"
test ! -e "$ROUNDS/r-c2"

# 6. A different --exclude set over the same commit is a different reviewed
# content, so it is round 4; `none` is recorded as given.
scratch_prepare "$ROUNDS/r-c3" --pr 7 --exclude extra.txt --pre-reviewed-by none > "$TMP/t6.out"
grep -Fxq 'ROUND: 4 identity=pr:7 repo=rounds/repo' "$TMP/t6.out"
scratch_accept "$ROUNDS/r-c3" claude
test "$(record_lines "$RECORD")" -eq 5
python3 -c 'import json,sys; e=json.loads(open(sys.argv[1]).read().splitlines()[4]); assert e["round"]==4 and e["pre_review"]=="none", e' "$RECORD"

# 7. collect prints the record status and the round on RUNNING, FAILED and final
# output, with the record path shortened; a run prepared before rounds were
# recorded (no round keys in rows.json) prints none of them.
scratch_prepare "$ROUNDS/r-c5" --pr 7 > /dev/null
rc=0; scratch_run "$ROUNDS/r-c5" collect > "$TMP/t7-running.out" || rc=$?
test "$rc" -ne 0
grep -Fxq 'GAUNTLET: RUNNING' "$TMP/t7-running.out"
grep -Fxq 'ROUND-RECORD: non-default record/rounds.jsonl' "$TMP/t7-running.out"
refute grep -Fq "$RECORD" "$TMP/t7-running.out"
grep -Fxq 'ROUND: 3 (retry of recorded round 3) identity=pr:7 repo=rounds/repo' "$TMP/t7-running.out"
FAKE_CLAUDE_FAIL=yes scratch_cli "$ROUNDS/r-c5" claude
FAKE_CODEX_FAIL=yes scratch_cli "$ROUNDS/r-c5" codex
rc=0; scratch_run "$ROUNDS/r-c5" collect > "$TMP/t7-failed.out" || rc=$?
test "$rc" -ne 0
grep -Fxq 'GAUNTLET: FAILED' "$TMP/t7-failed.out"
grep -Fxq 'ROUND-RECORD: non-default record/rounds.jsonl' "$TMP/t7-failed.out"
grep -Fq 'ROUND: 3 (retry of recorded round 3)' "$TMP/t7-failed.out"
test "$(record_lines "$RECORD")" -eq 5
scratch_prepare "$ROUNDS/r-c6" --pr 7 > /dev/null
scratch_cli "$ROUNDS/r-c6" claude
scratch_cli "$ROUNDS/r-c6" codex
scratch_run "$ROUNDS/r-c6" collect > "$TMP/t7-final.out"
grep -Fxq 'GAUNTLET: APPROVE' "$TMP/t7-final.out"
grep -Fxq 'ROUND-RECORD: non-default record/rounds.jsonl' "$TMP/t7-final.out"
grep -Fq 'ROUND: 3 (retry of recorded round 3)' "$TMP/t7-final.out"
test "$(record_lines "$RECORD")" -eq 6
cp -a "$ROUNDS/r-c6" "$ROUNDS/r-legacy"
python3 - "$ROUNDS/r-legacy/rows.json" <<'PY'
import json, os, pathlib, sys
path = pathlib.Path(sys.argv[1])
rows = json.load(open(path))
for key in ("identity", "round", "retry", "pre_review", "digest", "head", "repo",
            "repo_short", "round_record", "round_record_default"):
    rows.pop(key, None)
path.write_text(json.dumps(rows) + "\n")
os.chmod(path, 0o600)
PY
scratch_run "$ROUNDS/r-legacy" collect > "$TMP/t7-legacy.out"
grep -Fxq 'GAUNTLET: APPROVE' "$TMP/t7-legacy.out"
refute grep -q '^ROUND' "$TMP/t7-legacy.out"

# 8. Rounds are counted per identity only: a branch cut from a reviewed head
# under a new PR number starts at round 1.
git -C "$ROUNDS/repo" checkout -qb successor work
printf 'D\n' > "$ROUNDS/repo/app.txt"
git -C "$ROUNDS/repo" commit -qam commit-d
scratch_prepare "$ROUNDS/r-s1" --pr 9 > "$TMP/t8.out"
grep -Fxq 'ROUND: 1 identity=pr:9 repo=rounds/repo' "$TMP/t8.out"
scratch_run "$ROUNDS/r-s1" clean --force
git -C "$ROUNDS/repo" checkout -q work

# 9. A second, unrelated repository keeps its own count: the two repository keys
# are different absolute common directories.
new_scratch_repo "$ROUNDS/repo2"
git -C "$ROUNDS/repo2" checkout -qb work
printf 'other\n' > "$ROUNDS/repo2/app.txt"
git -C "$ROUNDS/repo2" commit -qam other
SCRATCH_REPO="$ROUNDS/repo2"
scratch_prepare "$ROUNDS/r-h1" --pr 7 > "$TMP/t11.out"
grep -Fxq 'ROUND: 1 identity=pr:7 repo=rounds/repo2' "$TMP/t11.out"
SCRATCH_REPO="$ROUNDS/repo"
python3 - "$ROUNDS/r-h1/rows.json" "$ROUNDS/r-c6/rows.json" <<'PY'
import json, sys
one = json.load(open(sys.argv[1]))["repo"]
two = json.load(open(sys.argv[2]))["repo"]
assert one != two, (one, two)
assert one.startswith("/") and two.startswith("/"), (one, two)
PY

# 10. A second worktree of the same repository shares the key and continues the
# count.
git -C "$ROUNDS/repo" worktree add -q --detach "$ROUNDS/wt" work
GAUNTLET_REPO="$ROUNDS/wt" GAUNTLET_DIR="$ROUNDS/r-i1" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --pr 7 > "$TMP/t10.out"
grep -Fxq 'ROUND: 3 (retry of recorded round 3) identity=pr:7 repo=rounds/repo' "$TMP/t10.out"
git -C "$ROUNDS/repo" worktree remove --force "$ROUNDS/wt"

# 11. Record failure modes. A malformed line is skipped with a warning naming it.
mkdir -p "$ROUNDS/malformed"
printf 'not json at all\n' > "$ROUNDS/malformed/rounds.jsonl"
GAUNTLET_ROUND_RECORD="$ROUNDS/malformed/rounds.jsonl" scratch_prepare "$ROUNDS/r-j1" --identity malformed > "$TMP/t15a.out" 2> "$TMP/t15a.err"
grep -Fxq "round record: skipping malformed line 1 in $ROUNDS/malformed/rounds.jsonl" "$TMP/t15a.err"
grep -Fq 'ROUND: 1 identity=id:malformed' "$TMP/t15a.out"
scratch_run "$ROUNDS/r-j1" clean --force

# An unwritable record directory is fatal at prepare, with the path in the message.
mkdir -p "$ROUNDS/nowrite"
chmod 500 "$ROUNDS/nowrite"
rc=0; GAUNTLET_ROUND_RECORD="$ROUNDS/nowrite/rounds.jsonl" scratch_prepare "$ROUNDS/r-j2" --identity nowrite > /dev/null 2> "$TMP/t15b.err" || rc=$?
test "$rc" -ne 0
grep -Fq "$ROUNDS/nowrite" "$TMP/t15b.err"
test ! -e "$ROUNDS/r-j2"
chmod 700 "$ROUNDS/nowrite"

# A path made unwritable after prepare leaves the accepted result with its
# sentinel, collect reports the failed write and retries it once, and the line is
# appended exactly once when the path is writable again.
GAUNTLET_ROUND_RECORD="$ROUNDS/writefail/rounds.jsonl" scratch_prepare "$ROUNDS/r-j3" --identity writefail > /dev/null
chmod 400 "$ROUNDS/writefail/rounds.jsonl"
chmod 500 "$ROUNDS/writefail"
scratch_accept "$ROUNDS/r-j3" claude
test -f "$ROUNDS/r-j3/failures/round-record.txt"
test -f "$ROUNDS/r-j3/completion/claude.done"
test ! -d "$ROUNDS/r-j3/round-recorded"
test -f "$ROUNDS/r-j3/results/claude.json"
rc=0; scratch_run "$ROUNDS/r-j3" collect > "$TMP/t15c.out" || rc=$?
grep -q '^ROUND-RECORD: WRITE FAILED .' "$TMP/t15c.out"
test "$(record_lines "$ROUNDS/writefail/rounds.jsonl")" -eq 0
chmod 700 "$ROUNDS/writefail"
chmod 600 "$ROUNDS/writefail/rounds.jsonl"
rc=0; scratch_run "$ROUNDS/r-j3" collect > "$TMP/t15d.out" || rc=$?
grep -q '^ROUND-RECORD: WRITE FAILED .' "$TMP/t15d.out"
test "$(record_lines "$ROUNDS/writefail/rounds.jsonl")" -eq 1
test -d "$ROUNDS/r-j3/round-recorded"
test ! -e "$ROUNDS/r-j3/failures/round-record.txt"
rc=0; scratch_run "$ROUNDS/r-j3" collect > "$TMP/t15e.out" || rc=$?
refute grep -q 'WRITE FAILED' "$TMP/t15e.out"
test "$(record_lines "$ROUNDS/writefail/rounds.jsonl")" -eq 1
python3 - "$ROUNDS/writefail/rounds.jsonl" "$ROUNDS/r-j3/scope/digest" <<'PY'
import json, pathlib, sys
lines = open(sys.argv[1]).read().splitlines()
digest = pathlib.Path(sys.argv[2]).read_text().strip()
assert len([line for line in lines if json.loads(line)["digest"] == digest]) == 1, lines
PY
scratch_run "$ROUNDS/r-j3" clean --force

# A record path inside a git worktree that does not ignore it is fatal, the
# directory the probe created is removed again, and an ignored path is allowed.
rc=0; GAUNTLET_ROUND_RECORD="$ROUNDS/repo/.gauntlet-record/rounds.jsonl" scratch_prepare "$ROUNDS/r-j4" --identity tracked > /dev/null 2> "$TMP/t15f.err" || rc=$?
test "$rc" -ne 0
grep -Fq "round record $ROUNDS/repo/.gauntlet-record/rounds.jsonl lies inside a git worktree and is not ignored there" "$TMP/t15f.err"
test ! -e "$ROUNDS/repo/.gauntlet-record"
test ! -e "$ROUNDS/r-j4"
printf '.gauntlet-record/\n' >> "$ROUNDS/repo/.git/info/exclude"
GAUNTLET_ROUND_RECORD="$ROUNDS/repo/.gauntlet-record/rounds.jsonl" scratch_prepare "$ROUNDS/r-j5" --identity ignored > "$TMP/t15g.out"
grep -Fq 'ROUND: 1 identity=id:ignored' "$TMP/t15g.out"
scratch_run "$ROUNDS/r-j5" clean --force

# A prepare that dies on a secret-bearing path writes no record line.
git -C "$ROUNDS/repo" checkout -qb secretish main
printf 'secret\n' > "$ROUNDS/repo/.env.production"
git -C "$ROUNDS/repo" add .env.production
git -C "$ROUNDS/repo" commit -qm secretish
before_secret="$(record_lines "$RECORD")"
rc=0; scratch_prepare "$ROUNDS/r-j6" --identity secretish > /dev/null 2> "$TMP/t15h.err" || rc=$?
test "$rc" -eq 1
grep -Fq '.env.production' "$TMP/t15h.err"
test ! -e "$ROUNDS/r-j6"
test "$(record_lines "$RECORD")" -eq "$before_secret"
git -C "$ROUNDS/repo" checkout -q work

# 12. With GAUNTLET_ROUND_RECORD unset the record is the default under HOME, and
# the printed repository key is the short one, never the operator's full path.
mkdir -p "$TMP/fakehome"
env -u GAUNTLET_ROUND_RECORD HOME="$TMP/fakehome" GAUNTLET_REPO="$ROUNDS/repo" GAUNTLET_DIR="$ROUNDS/r-k1" \
  bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity defaultrecord > "$TMP/t16.out"
test "$(head -n 1 "$TMP/t16.out")" = 'ROUND-RECORD: default'
test -f "$TMP/fakehome/.gauntlet/rounds.jsonl"
test "$(file_mode "$TMP/fakehome/.gauntlet")" = 700
test "$(file_mode "$TMP/fakehome/.gauntlet/rounds.jsonl")" = 600
grep -Fq 'repo=rounds/repo' "$TMP/t16.out"
refute grep -Fq "repo=$ROUNDS/repo" "$TMP/t16.out"
scratch_run "$ROUNDS/r-k1" clean --force

# ---------------------------------------------------------------------------
# Record integrity in a second fresh repository and record: a symlinked record
# path, a crashed append, and lines written by other runners or by the retired
# round budget.
# ---------------------------------------------------------------------------
HOPS="$TMP/hops"
mkdir -p "$HOPS"
export GAUNTLET_ROUND_RECORD="$HOPS/record/rounds.jsonl"
RECORD="$HOPS/record/rounds.jsonl"
SCRATCH_REPO="$HOPS/repo"
new_scratch_repo "$HOPS/repo"
git -C "$HOPS/repo" checkout -qb hop-one main
printf 'hop-one\n' > "$HOPS/repo/app.txt"; git -C "$HOPS/repo" commit -qam hop-one
scratch_prepare "$HOPS/h1" --pr 1 > /dev/null
scratch_accept "$HOPS/h1" claude

# A symlinked record file is refused, and a record path under a symlinked
# directory is probed where the bytes would land: inside a non-ignored
# worktree it is refused, so an append can never follow a link into a repository.
before_symlink="$(record_lines "$RECORD")"
mkdir -p "$TMP/link-home"
printf 'do not touch\n' > "$TMP/link-home/target.txt"
ln -s "$TMP/link-home/target.txt" "$TMP/link-home/rounds.jsonl"
rc=0; GAUNTLET_ROUND_RECORD="$TMP/link-home/rounds.jsonl" scratch_prepare "$HOPS/sym1" --pr 5 > /dev/null 2> "$TMP/sym1.err" || rc=$?
test "$rc" -eq 1
grep -Fq 'is a symlink; point GAUNTLET_ROUND_RECORD at a regular file path' "$TMP/sym1.err"
test ! -e "$HOPS/sym1"
test "$(cat "$TMP/link-home/target.txt")" = 'do not touch'
mkdir -p "$HOPS/repo/record-target"
ln -s "$HOPS/repo/record-target" "$TMP/link-home/into-repo"
rc=0; GAUNTLET_ROUND_RECORD="$TMP/link-home/into-repo/rounds.jsonl" scratch_prepare "$HOPS/sym2" --pr 5 > /dev/null 2> "$TMP/sym2.err" || rc=$?
test "$rc" -eq 1
grep -Fq 'lies inside a git worktree and is not ignored there' "$TMP/sym2.err"
test ! -e "$HOPS/repo/record-target/rounds.jsonl"
test ! -e "$HOPS/sym2"
rmdir "$HOPS/repo/record-target"
test "$(record_lines "$RECORD")" -eq "$before_symlink"

# A claim left by a crashed append (round-recording with no round-recorded) is
# never mistaken for a completed record: the next acceptance leaves it alone
# and collect reports it, releases it and appends exactly once.
git -C "$HOPS/repo" checkout -qb crash main
printf 'crash\n' > "$HOPS/repo/app.txt"; git -C "$HOPS/repo" commit -qam crash
scratch_prepare "$HOPS/c1" --pr 6 > /dev/null
before_crash="$(record_lines "$RECORD")"
mkdir "$HOPS/c1/round-recording"
scratch_accept "$HOPS/c1" claude
test -f "$HOPS/c1/results/claude.json"
test ! -e "$HOPS/c1/round-recorded"
test "$(record_lines "$RECORD")" -eq "$before_crash"
scratch_run "$HOPS/c1" collect > "$TMP/crash1.out" || true
grep -Fxq 'ROUND-RECORD: WRITE FAILED the append was claimed and never completed' "$TMP/crash1.out"
test -d "$HOPS/c1/round-recorded"
test "$(record_lines "$RECORD")" -eq $((before_crash + 1))
scratch_run "$HOPS/c1" collect > "$TMP/crash2.out" || true
refute grep -Fq 'WRITE FAILED' "$TMP/crash2.out"
test "$(record_lines "$RECORD")" -eq $((before_crash + 1))
scratch_run "$HOPS/c1" clean --force

# Code gauntlet round 2 repairs (13 Sep 2026). A claim held by a live worker
# (its launch lock carries a PID that is alive) is an append in flight: collect
# neither reports it nor appends; once that PID is gone the claim is recovered.
scratch_prepare "$HOPS/c2" --pr 6 > /dev/null
before_live="$(record_lines "$RECORD")"
mkdir "$HOPS/c2/round-recording" "$HOPS/c2/locks/claude.lock"
sleep 120 & holder=$!
printf '%s\n' "$holder" > "$HOPS/c2/locks/claude.lock/pid"
scratch_run "$HOPS/c2" collect > "$TMP/live1.out" || true
refute grep -Fq 'WRITE FAILED' "$TMP/live1.out"
test ! -e "$HOPS/c2/round-recorded"
test "$(record_lines "$RECORD")" -eq "$before_live"
kill "$holder"; wait "$holder" 2>/dev/null || true
scratch_run "$HOPS/c2" collect > "$TMP/live2.out" || true
grep -Fxq 'ROUND-RECORD: WRITE FAILED the append was claimed and never completed' "$TMP/live2.out"
test -d "$HOPS/c2/round-recorded"
test "$(record_lines "$RECORD")" -eq $((before_live + 1))
scratch_run "$HOPS/c2" clean --force

# Lines from another runner never count, and lines in the retired budget's shape
# (override, lineage, supersedes) still count for their identity.
git -C "$HOPS/repo" checkout -qb doc-ancestor main
printf 'doc-ancestor\n' > "$HOPS/repo/app.txt"; git -C "$HOPS/repo" commit -qam doc-ancestor
doc_head="$(git -C "$HOPS/repo" rev-parse HEAD)"
repo_key="$(git -C "$HOPS/repo" rev-parse --path-format=absolute --git-common-dir)"
python3 - "$RECORD" "$repo_key" "$doc_head" <<'PY'
import json, sys
record, repo, head = sys.argv[1:]
with open(record, "a") as handle:
    for runner, number, digest in (("doc-gauntlet", 1, "a" * 64), ("doc-gauntlet", 2, "b" * 64), ("gauntlet", 1, "c" * 64)):
        handle.write(json.dumps({"ts": "2026-09-13T00:00:00+00:00", "runner": runner, "repo": repo, "identity": "pr:14", "digest": digest, "head": head, "round": number, "override": None, "lineage": [], "supersedes": []}, separators=(",", ":")) + "\n")
PY
scratch_prepare "$HOPS/d1" --pr 14 > "$TMP/doc-isolation.out"
grep -Fxq 'ROUND: 2 identity=pr:14 repo=hops/repo' "$TMP/doc-isolation.out"
scratch_run "$HOPS/d1" clean --force

# Lines written under the retired budget can carry lineage-inflated rounds (an
# identity numbered [1, 3], say). New content is numbered past the highest
# recorded round, so numbers never repeat or go backwards.
python3 - "$RECORD" "$repo_key" "$doc_head" <<'PY'
import json, sys
record, repo, head = sys.argv[1:]
with open(record, "a") as handle:
    for identity, number, digest in (("pr:15", 1, "d" * 64), ("pr:15", 3, "e" * 64), ("pr:16", 17, "f" * 64), ("pr:16", 18, "0" * 64)):
        handle.write(json.dumps({"ts": "2026-09-13T00:00:00+00:00", "runner": "gauntlet", "repo": repo, "identity": identity, "digest": digest, "head": head, "round": number, "override": None, "lineage": ["pr:7"], "supersedes": []}, separators=(",", ":")) + "\n")
PY
scratch_prepare "$HOPS/i1" --pr 15 > "$TMP/inflated15.out"
grep -Fxq 'ROUND: 4 identity=pr:15 repo=hops/repo' "$TMP/inflated15.out"
scratch_run "$HOPS/i1" clean --force
scratch_prepare "$HOPS/i2" --pr 16 > "$TMP/inflated16.out"
grep -Fxq 'ROUND: 19 identity=pr:16 repo=hops/repo' "$TMP/inflated16.out"
scratch_run "$HOPS/i2" clean --force

echo 'gauntlet-v2.test.sh: OK'
