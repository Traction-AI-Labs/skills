#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/doc-gauntlet.sh"
TMP="$(mktemp -d)"; trap 'touch "$TMP/release-lifecycle-lock" 2>/dev/null || true; rm -rf "$TMP"' EXIT
# The test owns its HOME: a fake Grok login for the legs that need one, and nothing of the real home is read or written.
unset GROK_HOME; export HOME="$TMP/home"; mkdir -p "$HOME/.grok"; printf '{}\n' > "$HOME/.grok/auth.json"
export GAUNTLET_ROUND_RECORD="$TMP/rounds.jsonl"
export GAUNTLET_ARCHIVE="$TMP/archive"
REPO="$TMP/repo"; mkdir -p "$REPO/docs"
git init -q -b main "$REPO"
git -C "$REPO" config user.name test
git -C "$REPO" config user.email test@example.invalid
printf '# Review target\n\n## Review dispositions\n\n- Existing decision: keep the scope.\n' > "$REPO/docs/plan.md"
printf '# Requirements\n\n## Acceptance\n\n- The result is reviewable.\n' > "$REPO/docs/requirements.md"
printf 'evidence\n' > "$REPO/evidence.txt"
git -C "$REPO" add . && git -C "$REPO" commit -qm initial
git -C "$REPO" checkout -qb feature
printf '\nChanged.\n' >> "$REPO/docs/plan.md"
git -C "$REPO" commit -am plan -q
repo_canonical="$(git -C "$REPO" rev-parse --show-toplevel)"
wait_for_leg() {
  local run_dir="$1" leg="$2" attempts=0
  while [[ ! -f "$run_dir/completion/$leg.done" && "$attempts" -lt 1200 ]]; do
    sleep 0.05
    attempts=$((attempts + 1))
  done
  [[ -f "$run_dir/completion/$leg.done" ]] || { printf 'timed out waiting for %s\n' "$leg" >&2; exit 1; }
}

RUN="$TMP/run"
printf '{"findings":[{"status":"accepted","section":"Old decision"}]}\n' > "$TMP/prior-findings.json"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$RUN" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture --prior-findings "$TMP/prior-findings.json" > "$TMP/prepare.out"
grep -Fx "WORKDIR=$RUN" "$TMP/prepare.out"
test "$(python3 -c 'import os,stat,sys; print(f"{stat.S_IMODE(os.lstat(sys.argv[1]).st_mode):o}")' "$RUN")" = 700
test "$(python3 -c 'import os,sys; print(os.lstat(sys.argv[1]).st_uid)' "$RUN")" = "$(id -u)"
grep -Fq 'Existing decision: keep the scope.' "$RUN/prompts/breadth-coherence.md"
grep -Fq 'technical editor reading for internal consistency' "$RUN/prompts/breadth-coherence.md"
grep -Fq 'Document Review Findings' "$RUN/prompts/breadth-coherence.md"
grep -Fq 'Document type: plan' "$RUN/prompts/breadth-coherence.md"
grep -Fq 'Existing decision: keep the scope.' "$RUN/prompts/adversarial-claude-native.md"
grep -Fq 'Do not re-raise a finding unless it persists in the current document;' "$RUN/prompts/breadth-coherence.md"
grep -Fq '"status":"accepted"' "$RUN/prompts/adversarial-codex-cli.md"
test -f "$RUN/schemas/breadth-coherence.json"
test -f "$RUN/schemas/adversarial-claude-cli.json"
test -f "$RUN/schemas/adversarial-codex-cli.json"
python3 - "$RUN/schemas/adversarial-codex-cli.json" <<'PY'
import json, sys
item = json.load(open(sys.argv[1]))["properties"]["findings"]["items"]
assert item["additionalProperties"] is False
assert set(item["required"]) == set(item["properties"])
assert "suggested_fix" in item["required"]
PY
grep -Fq 'Required transport: claude-native' "$RUN/prompts/adversarial-claude-native.md"
grep -Fq 'Required transport: claude-cli' "$RUN/prompts/adversarial-claude-cli.md"
grep -Fq 'Challenge the document by trying to falsify its premises' "$RUN/prompts/adversarial-claude-native.md"
grep -Fxq "Repository path: $repo_canonical" "$RUN/prompts/adversarial-claude-native.md"

TYPE_RUN="$TMP/type-run"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$TYPE_RUN" "$RUNNER" prepare --authorize-provider --doc docs/requirements.md --type requirements >/dev/null
grep -Fq 'Document type: requirements' "$TYPE_RUN/prompts/breadth-feasibility.md"
# With no --codex-model, the Codex default is gpt-6.1-sol.
python3 -c 'import json, sys; m = json.load(open(sys.argv[1]))["codex"]["model"]; assert m == "gpt-6.1-sol", m' "$TYPE_RUN/rows.json"
DOC_GAUNTLET_DIR="$TYPE_RUN" "$RUNNER" clean --force
if DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$TMP/missing-type" "$RUNNER" prepare --authorize-provider --doc docs/plan.md >/dev/null 2> "$TMP/missing-type.err"; then exit 1; fi
grep -Fq 'prepare requires --type requirements|plan' "$TMP/missing-type.err"

printf 'outside\n' > "$TMP/outside.md"
if DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$TMP/outside-run" "$RUNNER" prepare --authorize-provider --doc "$TMP/outside.md" --type plan >/dev/null 2> "$TMP/outside.err"; then exit 1; fi
grep -Fq 'must be inside the prepared repository' "$TMP/outside.err"

findings() { printf '{"reviewer":"%s","findings":[],"residual_risks":[],"deferred_questions":[]}\n' "$1"; }
blocking_findings() { printf '{"reviewer":"coherence","findings":[{"title":"Contradictory requirement","severity":"P0","section":"Acceptance","why_it_matters":"Implementers cannot satisfy both stated outcomes.","finding_type":"error","autofix_class":"manual","confidence":100,"evidence":["Acceptance requires incompatible outcomes."]}],"residual_risks":[],"deferred_questions":[]}\n'; }
findings coherence > "$TMP/coherence.txt"
if DOC_GAUNTLET_DIR="$RUN" "$RUNNER" ingest --lens coherence --transport codex-cli --text "$TMP/coherence.txt" >/dev/null 2>&1; then exit 1; fi
for lens in coherence feasibility scope-guardian product-lens security-lens design-lens; do
  if [[ "$lens" == coherence ]]; then blocking_findings > "$TMP/$lens.txt"; else findings "$lens" > "$TMP/$lens.txt"; fi
  DOC_GAUNTLET_DIR="$RUN" "$RUNNER" ingest --lens "$lens" --transport claude-native --text "$TMP/$lens.txt"
done

head="$(git -C "$REPO" rev-parse HEAD)"; digest="$(cat "$RUN/scope.digest")"
cat > "$TMP/claude.txt" <<EOF
prose before
\`\`\`json
{"engine":"claude","model":"fixture","transport":"claude-native","scope_sha":"$head","scope_digest":"$digest","verdict":"BLOCK","findings":[{"title":"old example"}]}
\`\`\`
\`\`\`json
{"engine":"claude","model":"fixture","transport":"claude-native","scope_sha":"$head","scope_digest":"$digest","verdict":"CONVERGED","findings":[]}
\`\`\`
EOF
DOC_GAUNTLET_DIR="$RUN" "$RUNNER" ingest --engine claude --transport claude-native --text "$TMP/claude.txt"
grep -Fq '"verdict": "CONVERGED"' "$RUN/results/adversarial-claude.json"
if DOC_GAUNTLET_DIR="$RUN" "$RUNNER" ingest --engine claude --transport claude-native --text "$TMP/claude.txt" >/dev/null 2> "$TMP/duplicate.err"; then exit 1; fi
grep -Fq 'already has an accepted result' "$TMP/duplicate.err"
grep -Fq '"verdict": "CONVERGED"' "$RUN/results/adversarial-claude.json"

cat > "$TMP/codex.txt" <<EOF
{"engine":"codex","model":"fixture","transport":"codex-cli","scope_sha":"$head","scope_digest":"$digest","verdict":"CONVERGED","findings":[]}
EOF
DOC_GAUNTLET_DIR="$RUN" "$RUNNER" ingest --engine codex --transport codex-cli --text "$TMP/codex.txt"
DOC_GAUNTLET_DIR="$RUN" "$RUNNER" collect > "$TMP/collect.out"
grep -Fx 'ADVERSARIAL: CONVERGED' "$TMP/collect.out"
! grep -Fxq 'GAUNTLET: CONVERGED' "$TMP/collect.out"
grep -Fq 'Contradictory requirement' "$TMP/collect.out"

RUN2="$TMP/run2"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture >/dev/null
printf '{"reviewer":"coherence","findings":[{}],"residual_risks":[],"deferred_questions":[]}\n' > "$TMP/malformed-breadth.txt"
if DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" ingest --lens coherence --transport claude-native --text "$TMP/malformed-breadth.txt" >/dev/null 2>&1; then exit 1; fi
grep -Fq 'no schema-valid object matches the prepared row' "$RUN2/failures/breadth-coherence.txt"
printf '{"reviewer":"coherence","findings":[{"title":"Boolean confidence","severity":"P1","section":"Scope","why_it_matters":"A malformed result bypasses fallback.","finding_type":"error","autofix_class":"manual","confidence":false,"evidence":["confidence is Boolean"]}],"residual_risks":[],"deferred_questions":[]}\n' > "$TMP/boolean-breadth.txt"
if DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" ingest --lens coherence --transport claude-native --text "$TMP/boolean-breadth.txt" >/dev/null 2>&1; then exit 1; fi
if DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" ingest --engine codex --transport codex-cli --text "$TMP/claude.txt" >/dev/null 2>&1; then exit 1; fi
if DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" ingest --engine claude --transport codex-native --text "$TMP/claude.txt" >/dev/null 2> "$TMP/cross-engine.err"; then exit 1; fi
grep -Fq 'adversarial transport must match its engine' "$TMP/cross-engine.err"
cat > "$TMP/malformed-adversarial.txt" <<EOF
{"engine":"codex","model":"fixture","transport":"codex-cli","scope_sha":"$head","scope_digest":"$digest","verdict":"BLOCK","findings":[{}]}
EOF
if DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" ingest --engine codex --transport codex-cli --text "$TMP/malformed-adversarial.txt" >/dev/null 2>&1; then exit 1; fi
cat > "$TMP/boolean-adversarial.txt" <<EOF
{"engine":"codex","model":"fixture","transport":"codex-cli","scope_sha":"$head","scope_digest":"$digest","verdict":"BLOCK","findings":[{"title":"Boolean confidence","severity":"P1","section":"Scope","why_it_matters":"A malformed result bypasses fallback.","finding_type":"error","autofix_class":"manual","confidence":false,"evidence":["confidence is Boolean"]}]}
EOF
if DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" ingest --engine codex --transport codex-cli --text "$TMP/boolean-adversarial.txt" >/dev/null 2>&1; then exit 1; fi
DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" collect > "$TMP/incomplete.out" || true
grep -Fx 'GAUNTLET: RUNNING' "$TMP/incomplete.out"

bad_model="$TMP/bad-model.txt"
sed 's/"model":"fixture"/"model":"wrong"/' "$TMP/codex.txt" > "$bad_model"
if DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" ingest --engine codex --transport codex-cli --text "$bad_model" >/dev/null 2>&1; then exit 1; fi
if DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$RUN2" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan >/dev/null 2>&1; then exit 1; fi

# Two outputs: sparring points ride alongside errors. BLOCK needs an error or
# omission; CONVERGED may carry sparring points and nothing else.
RUNSP="$TMP/run-sparring"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$RUNSP" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture >/dev/null
grep -Fq 'name, for yourself, the decision this document supports and who reads it' "$RUNSP/prompts/adversarial-codex-cli.md"
grep -Fq 'name, for yourself, the decision this document supports and who reads it' "$RUNSP/prompts/breadth-product-lens.md"
grep -Fq 'a fix never adds a hedge' "$RUNSP/prompts/adversarial-claude-cli.md"
! grep -Fq 'Report only defects' "$RUNSP/prompts/adversarial-claude-cli.md"
python3 - "$RUNSP/schemas" <<'PY2'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
for name in ("adversarial-codex-cli.json", "adversarial-claude-cli.json"):
    item = json.load(open(out / name))["properties"]["findings"]["items"]
    assert item["properties"]["finding_type"]["enum"] == ["error", "omission", "sparring"], name
breadth = json.load(open(out / "breadth-coherence.json"))
assert breadth["properties"]["findings"]["items"]["properties"]["finding_type"]["enum"] == ["error", "omission", "sparring"]
PY2
# The vendored upstream schema stays byte-for-byte; only the prepared copy widens.
python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["properties"]["findings"]["items"]["properties"]["finding_type"]["enum"] == ["error","omission"]' "$SCRIPT_DIR/../references/review-kernel/findings-schema.json"
sp_head="$(cat "$RUNSP/head.commit")"; sp_digest="$(cat "$RUNSP/scope.digest")"
sparring_point='{"title":"Problem is not sized","severity":"P2","section":"Problem","why_it_matters":"The committee cannot weigh cost against benefit.","finding_type":"sparring","autofix_class":"manual","confidence":75,"evidence":["no volume is stated"],"suggested_fix":"State volume, e.g. 40 tenders a year at 2 days each."}'
error_point='{"title":"Contradictory deadline","severity":"P1","section":"Plan","why_it_matters":"Readers will schedule against the wrong date.","finding_type":"error","autofix_class":"manual","confidence":100,"evidence":["1 Oct and 8 Oct both given"]}'
printf '{"engine":"codex","model":"fixture","transport":"codex-cli","scope_sha":"%s","scope_digest":"%s","verdict":"BLOCK","findings":[%s]}\n' "$sp_head" "$sp_digest" "$sparring_point" > "$TMP/sp-block.txt"
if DOC_GAUNTLET_DIR="$RUNSP" "$RUNNER" ingest --engine codex --transport codex-cli --text "$TMP/sp-block.txt" >/dev/null 2>&1; then exit 1; fi
test ! -e "$RUNSP/results/adversarial-codex.json"
printf '{"engine":"codex","model":"fixture","transport":"codex-cli","scope_sha":"%s","scope_digest":"%s","verdict":"CONVERGED","findings":[%s]}\n' "$sp_head" "$sp_digest" "$error_point" > "$TMP/sp-converged-error.txt"
if DOC_GAUNTLET_DIR="$RUNSP" "$RUNNER" ingest --engine codex --transport codex-cli --text "$TMP/sp-converged-error.txt" >/dev/null 2>&1; then exit 1; fi
test ! -e "$RUNSP/results/adversarial-codex.json"
printf '{"engine":"codex","model":"fixture","transport":"codex-cli","scope_sha":"%s","scope_digest":"%s","verdict":"CONVERGED","findings":[%s]}\n' "$sp_head" "$sp_digest" "$sparring_point" > "$TMP/sp-converged.txt"
DOC_GAUNTLET_DIR="$RUNSP" "$RUNNER" ingest --engine codex --transport codex-cli --text "$TMP/sp-converged.txt"
grep -Fq '"finding_type": "sparring"' "$RUNSP/results/adversarial-codex.json"
printf '{"engine":"claude","model":"fixture","transport":"claude-native","scope_sha":"%s","scope_digest":"%s","verdict":"BLOCK","findings":[%s,%s]}\n' "$sp_head" "$sp_digest" "$sparring_point" "$error_point" > "$TMP/sp-claude.txt"
DOC_GAUNTLET_DIR="$RUNSP" "$RUNNER" ingest --engine claude --transport claude-native --text "$TMP/sp-claude.txt"
printf '{"reviewer":"coherence","findings":[%s],"residual_risks":[],"deferred_questions":[]}\n' "$sparring_point" > "$TMP/sp-breadth.txt"
DOC_GAUNTLET_DIR="$RUNSP" "$RUNNER" ingest --lens coherence --transport claude-native --text "$TMP/sp-breadth.txt"
DOC_GAUNTLET_DIR="$RUNSP" "$RUNNER" clean --force

RUN3="$TMP/run3"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$RUN3" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture >/dev/null
pushd "$TMP" >/dev/null
DOC_GAUNTLET_DIR="$RUN3" "$RUNNER" collect > "$TMP/other-cwd.out" || true
popd >/dev/null
grep -Fx 'GAUNTLET: RUNNING' "$TMP/other-cwd.out"

# CLI rows use the prepared model/effort and read-only provider boundaries.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$FAKE_CLAUDE_ARGS"
[[ -n "${FAKE_CLAUDE_CWD:-}" ]] && pwd > "$FAKE_CLAUDE_CWD"
[[ -n "${FAKE_CLAUDE_ENV:-}" ]] && printf '%s\n' "${DOC_GAUNTLET_DIR-unset}" > "$FAKE_CLAUDE_ENV"
# The sk- literal is split so the repo secret scan does not flag this fixture; bash rejoins it.
if [[ "${FAKE_CLAUDE_FAIL:-}" == yes ]]; then for i in $(seq 1 100); do echo "provider diagnostic $i" >&2; done; echo "provider failed: token=sk-test""secret123456" >&2; exit 7; fi
prompt="$(cat)"; lens="$(sed -n 's/^You are the \([a-z-]*\) document-review lens.*/\1/p' <<< "$prompt")"
printf '{"reviewer":"%s","findings":[],"residual_risks":[],"deferred_questions":[]}\n' "$lens"
EOF
cat > "$TMP/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$FAKE_CODEX_ARGS"
[[ -n "${FAKE_CODEX_ENV:-}" ]] && printf '%s\n' "${DOC_GAUNTLET_DIR-unset}" > "$FAKE_CODEX_ENV"
out=""; for ((i=1;i<=$#;i++)); do [[ "${!i}" == --output-last-message ]] && { j=$((i+1)); out="${!j}"; }; done
prompt="$(cat)"; head="$(sed -n 's/^Pinned HEAD SHA: //p' <<< "$prompt")"; digest="$(sed -n 's/^Pinned scope digest: //p' <<< "$prompt")"
printf '{"engine":"codex","model":"fixture","transport":"codex-cli","scope_sha":"%s","scope_digest":"%s","verdict":"CONVERGED","findings":[]}\n' "$head" "$digest" > "$out"
EOF
REAL_TIMEOUT="$(command -v timeout)"
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
chmod +x "$TMP/bin/claude" "$TMP/bin/codex" "$TMP/bin/timeout"
RUN4="$TMP/run4"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$RUN4" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture --effort high >/dev/null
run4_lines_before="$(wc -l < "$GAUNTLET_ROUND_RECORD" | tr -d ' ')"
env PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/codex.timeout" GAUNTLET_PROVIDER_TIMEOUT_SECONDS=77 GAUNTLET_TIMEOUT_CLAUDE_SECONDS=19 FAKE_CLAUDE_ARGS="$TMP/claude.args" FAKE_CLAUDE_CWD="$TMP/claude.cwd" FAKE_CLAUDE_ENV="$TMP/claude.env" DOC_GAUNTLET_DIR="$RUN4" "$RUNNER" run-cli --lens coherence
wait_for_leg "$RUN4" breadth-coherence
# The CLI path records before it publishes its sentinel, so the moment the
# sentinel is visible the round line is on disk; the launch lock goes last.
test -d "$RUN4/round-recorded"
attempts=0; while [[ -d "$RUN4/locks/breadth-coherence.lock" && "$attempts" -lt 1200 ]]; do sleep 0.05; attempts=$((attempts + 1)); done
test ! -d "$RUN4/locks/breadth-coherence.lock"
test ! -e "$RUN4/failures/round-record.txt"
test "$(wc -l < "$GAUNTLET_ROUND_RECORD" | tr -d ' ')" = "$((run4_lines_before + 1))"
grep -Fq -- '--safe-mode --model fixture --effort high --add-dir' "$TMP/claude.args"
grep -Fq -- '--permission-mode dontAsk --tools Read,Grep,Glob' "$TMP/claude.args"
grep -Fq -- '--json-schema' "$TMP/claude.args"
test "$(cat "$TMP/claude.timeout")" = 19
claude_cwd="$(cat "$TMP/claude.cwd")"
[[ "$claude_cwd" != "$RUN4"* ]]
test "$(cat "$TMP/claude.env")" = unset
test ! -e "$claude_cwd"
env PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/codex.timeout" GAUNTLET_PROVIDER_TIMEOUT_SECONDS=77 GAUNTLET_TIMEOUT_CODEX_SECONDS=29 FAKE_CODEX_ARGS="$TMP/codex.args" FAKE_CODEX_ENV="$TMP/codex.env" DOC_GAUNTLET_DIR="$RUN4" "$RUNNER" run-cli --engine codex
wait_for_leg "$RUN4" adversarial-codex
grep -Fq -- '--ignore-user-config --strict-config' "$TMP/codex.args"
grep -Fq -- '--sandbox read-only --ephemeral' "$TMP/codex.args"
grep -Fq -- 'model_reasoning_effort=high -m fixture' "$TMP/codex.args"
grep -Fq -- '--output-schema' "$TMP/codex.args"
test "$(cat "$TMP/codex.timeout")" = 29
codex_cwd="$(sed -n 's/.*-C \([^ ]*\).*/\1/p' "$TMP/codex.args")"
[[ "$codex_cwd" != "$RUN4"* ]]
test "$(cat "$TMP/codex.env")" = unset
test ! -e "$codex_cwd"

# --timeout-seconds is pinned into the run's config at prepare and honoured
# at run-cli with no env override (source: config); a per-engine env
# override still wins over the pinned config value (source: env); both are
# visible on run-cli's stdout and on collect.
RUN_PIN="$TMP/run-pin"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$RUN_PIN" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture --timeout-seconds 63 >/dev/null
grep -Fq '"timeout_seconds": 63' "$RUN_PIN/rows.json"
env PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/pin-claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/pin-codex.timeout" FAKE_CLAUDE_ARGS="$TMP/pin-claude.args" DOC_GAUNTLET_DIR="$RUN_PIN" "$RUNNER" run-cli --lens coherence > "$TMP/pin.launch"
grep -Fx 'leg coherence started: bound 63s (source: config)' "$TMP/pin.launch"
wait_for_leg "$RUN_PIN" breadth-coherence
test "$(cat "$TMP/pin-claude.timeout")" = 63
DOC_GAUNTLET_DIR="$RUN_PIN" "$RUNNER" collect > "$TMP/pin.collect" || true
grep -Fx 'GAUNTLET: RUNNING' "$TMP/pin.collect"
grep -Fq 'BOUND: breadth-coherence 63s (source: config)' "$TMP/pin.collect"
env PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/pin-claude-env.timeout" FAKE_CODEX_TIMEOUT="$TMP/pin-codex-env.timeout" FAKE_CODEX_ARGS="$TMP/pin-codex.args" GAUNTLET_TIMEOUT_CODEX_SECONDS=9 DOC_GAUNTLET_DIR="$RUN_PIN" "$RUNNER" run-cli --engine codex > "$TMP/pin-codex.launch"
grep -Fx 'leg codex started: bound 9s (source: env)' "$TMP/pin-codex.launch"
wait_for_leg "$RUN_PIN" adversarial-codex
test "$(cat "$TMP/pin-codex-env.timeout")" = 9
DOC_GAUNTLET_DIR="$RUN_PIN" "$RUNNER" collect > "$TMP/pin-both.collect" || true
grep -Fq 'BOUND: breadth-coherence 63s (source: config)' "$TMP/pin-both.collect"
grep -Fq 'BOUND: adversarial-codex 9s (source: env)' "$TMP/pin-both.collect"

# A leg that dies on timeout (exit 124) is reported as a timeout, not a
# generic diagnostic dump, so a truncated verdict can never be mistaken for
# a reviewer result.
RUN_TIMEOUT="$TMP/run-timeout"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$RUN_TIMEOUT" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture --timeout-seconds 5 >/dev/null
mkdir "$TMP/timeout-bin"
cat > "$TMP/timeout-bin/timeout" <<'EOF'
#!/usr/bin/env bash
exit 124
EOF
chmod +x "$TMP/timeout-bin/timeout"
PATH="$TMP/timeout-bin:$PATH" DOC_GAUNTLET_DIR="$RUN_TIMEOUT" "$RUNNER" run-cli --lens coherence > "$TMP/timeout.launch"
grep -Fx 'leg coherence started: bound 5s (source: config)' "$TMP/timeout.launch"
wait_for_leg "$RUN_TIMEOUT" breadth-coherence
DOC_GAUNTLET_DIR="$RUN_TIMEOUT" "$RUNNER" collect > "$TMP/timeout.collect" || true
grep -Fx 'GAUNTLET: RUNNING' "$TMP/timeout.collect"
grep -Fq 'BOUND: breadth-coherence 5s (source: config)' "$TMP/timeout.collect"
grep -Fq 'coherence: timed out after 5s' "$TMP/timeout.collect"
test "$(cat "$RUN_TIMEOUT/completion/breadth-coherence.bound")" = '5 config'

RUN5="$TMP/run5"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$RUN5" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture >/dev/null
env PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_CLAUDE_TIMEOUT="$TMP/failed-claude.timeout" FAKE_CODEX_TIMEOUT="$TMP/failed-codex.timeout" FAKE_CLAUDE_ARGS="$TMP/failed-claude.args" FAKE_CLAUDE_FAIL=yes DOC_GAUNTLET_DIR="$RUN5" "$RUNNER" run-cli --lens coherence >/dev/null
wait_for_leg "$RUN5" breadth-coherence
DOC_GAUNTLET_DIR="$RUN5" "$RUNNER" collect > "$TMP/failed-collect.out" || true
grep -Fq 'provider failed: token=<redacted>' "$TMP/failed-collect.out"
grep -Fq '<diagnostic truncated>' "$TMP/failed-collect.out"
! grep -Fq 'sk-testsecret' "$TMP/failed-collect.out"

ALL_FAILED="$TMP/all-failed"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$ALL_FAILED" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --claude-model fixture --codex-model fixture >/dev/null
for leg in breadth-coherence breadth-feasibility breadth-scope-guardian breadth-product-lens breadth-security-lens breadth-design-lens adversarial-claude adversarial-codex; do
  printf 'exit_code=7\n' > "$ALL_FAILED/completion/$leg.done"
  printf 'fixture failure for %s\n' "$leg" > "$ALL_FAILED/failures/$leg.txt"
done
DOC_GAUNTLET_DIR="$ALL_FAILED" "$RUNNER" collect > "$TMP/all-failed.out" || true
grep -Fx 'GAUNTLET: FAILED' "$TMP/all-failed.out"
test -f "$ALL_FAILED/results/gauntlet-failed.json"
python3 - "$ALL_FAILED/results/gauntlet-failed.json" <<'PY'
import json, sys
data=json.load(open(sys.argv[1]))
assert data['outcome'] == 'all-legs-failed'
assert len(data['legs']) == 8
assert all('exit_code' in leg and 'failure' in leg for leg in data['legs'])
PY
( mkdir "$ALL_FAILED/locks/lifecycle.lock"; while [[ ! -f "$TMP/release-lifecycle-lock" ]]; do sleep 0.01; done; rmdir "$ALL_FAILED/locks/lifecycle.lock" ) & lifecycle_holder=$!
while [[ ! -d "$ALL_FAILED/locks/lifecycle.lock" ]]; do sleep 0.01; done
if DOC_GAUNTLET_DIR="$ALL_FAILED" "$RUNNER" run-cli --lens coherence > /dev/null 2> "$TMP/concurrent-retry.err"; then exit 1; fi
grep -Fq 'run state is being collected or updated' "$TMP/concurrent-retry.err"
test -f "$ALL_FAILED/completion/breadth-coherence.done"
test -f "$ALL_FAILED/results/gauntlet-failed.json"
touch "$TMP/release-lifecycle-lock"
wait "$lifecycle_holder"

# Pair substitution: Grok replaces Claude, including breadth.
if DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$TMP/three-engines" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --engines claude,codex,grok >/dev/null 2> "$TMP/doc-three.err"; then exit 1; fi
grep -Fq 'prepare requires exactly two engines' "$TMP/doc-three.err"
GROK_PAIR="$TMP/grok-pair"
DOC_GAUNTLET_REPO="$REPO" DOC_GAUNTLET_DIR="$GROK_PAIR" "$RUNNER" prepare --authorize-provider --doc docs/plan.md --type plan --engines grok,codex --grok-model fixture --codex-model fixture >/dev/null
test -f "$GROK_PAIR/prompts/adversarial-grok-cli.md"
test -f "$GROK_PAIR/prompts/adversarial-grok-native.md"
test ! -e "$GROK_PAIR/prompts/adversarial-claude-cli.md"
grep -Fq '"breadth_engine": "grok"' "$GROK_PAIR/rows.json"
grep -Fq 'Required transport: grok-native' "$GROK_PAIR/prompts/adversarial-grok-native.md"
if DOC_GAUNTLET_DIR="$GROK_PAIR" "$RUNNER" ingest --lens coherence --transport claude-native --text "$TMP/coherence.txt" >/dev/null 2> "$TMP/wrong-breadth.err"; then exit 1; fi
grep -Fq 'breadth transport must be grok-cli or grok-native' "$TMP/wrong-breadth.err"
if DOC_GAUNTLET_DIR="$GROK_PAIR" "$RUNNER" run-cli --engine claude >/dev/null 2> "$TMP/doc-unprepared.err"; then exit 1; fi
grep -Fq 'claude is not in this run' "$TMP/doc-unprepared.err"
cat > "$TMP/bin/grok" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$FAKE_GROK_ARGS"
[[ -n "${FAKE_GROK_CWD:-}" ]] && pwd > "$FAKE_GROK_CWD"
[[ -f .grok/sandbox.toml ]] || { echo 'missing grok sandbox profile' >&2; exit 1; }
grep -Fq 'extends = "strict"' .grok/sandbox.toml
grep -Eq '^read_only = \["[^"]+"\]$' .grok/sandbox.toml
grep -Eq '^deny = \[' .grok/sandbox.toml
# Instruction files are listed one by one, never by a ** pattern (a pattern can
# match a symlink, and Grok refuses to start on a symlinked deny entry).
if grep -Fq '*' .grok/sandbox.toml; then echo 'sandbox carries a pattern' >&2; exit 1; fi
# ~/.gauntlet is denied only where it exists, so the check needs no particular home.
[[ ! -e "$HOME/.gauntlet" ]] || grep -Fq "\"$HOME/.gauntlet\"" .grok/sandbox.toml
! grep -Fq '/sessions' .grok/sandbox.toml
# Real Grok creates a denied literal path that does not exist, empty, and
# leaves it there (18 Oct 2026); the fake does the same in the repo,
# and under $FAKE_GROK_HOME_ROOT when a case points HOME at a scratch home.
python3 - .grok/sandbox.toml <<'PY'
import json, os, re, sys
t = open(sys.argv[1]).read()
repo = json.loads(re.search(r"^read_only = \[(.*)\]$", t, re.M).group(1))
roots = (repo + "/", os.path.realpath(repo) + "/")
if os.environ.get("FAKE_GROK_HOME_ROOT"):
    roots += (os.environ["FAKE_GROK_HOME_ROOT"].rstrip("/") + "/",)
for p in json.loads("[" + re.search(r"^deny = \[(.*)\]$", t, re.M).group(1) + "]"):
    # Real Grok refuses to start when a deny entry is a symlink (19 Oct 2026).
    if os.path.islink(p):
        sys.exit(f"grok: sandbox deny entry is a symlink: {p}")
    if "*" not in p and p.startswith(roots) and not os.path.lexists(p):
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").close()
PY
[[ -z "${FAKE_GROK_SANDBOX:-}" ]] || cp .grok/sandbox.toml "$FAKE_GROK_SANDBOX"
prompt=""
prev=""
for arg in "$@"; do
  [[ "$prev" == --prompt-file ]] && prompt="$arg"
  prev="$arg"
done
p="$(cat "$prompt")"
lens="$(sed -n 's/^You are the \([a-z-]*\) document-review lens.*/\1/p' <<< "$p")"
if [[ -n "$lens" ]]; then
  reply="$(printf 'Read the plan and its sources.\n{"reviewer":"%s","findings":[],"residual_risks":[],"deferred_questions":[]}' "$lens")"
else
  head="$(sed -n 's/^Pinned HEAD SHA: //p' <<< "$p")"; digest="$(sed -n 's/^Pinned scope digest: //p' <<< "$p")"
  reply="$(printf '{"engine":"grok","model":"fixture","transport":"grok-cli","scope_sha":"%s","scope_digest":"%s","verdict":"CONVERGED","findings":[]}' "$head" "$digest")"
fi
# Grok's --output-format json wrapper: the reply is a string, num_turns counts tool rounds.
python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1], "num_turns": int(sys.argv[2])}))' "$reply" "${FAKE_GROK_TURNS:-4}"
EOF
chmod +x "$TMP/bin/grok"
env PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_GROK_TIMEOUT="$TMP/doc-grok.timeout" GAUNTLET_TIMEOUT_GROK_SECONDS=27 FAKE_GROK_ARGS="$TMP/doc-grok.args" FAKE_GROK_CWD="$TMP/doc-grok.cwd" DOC_GAUNTLET_DIR="$GROK_PAIR" "$RUNNER" run-cli --lens coherence
wait_for_leg "$GROK_PAIR" breadth-coherence
grep -Fq -- '--prompt-file' "$TMP/doc-grok.args"
grep -Eq -- '--sandbox g[0-9a-f]{16}' "$TMP/doc-grok.args"
! grep -Fq -- '--sandbox read-only' "$TMP/doc-grok.args"
grep -Fq -- '--tools read_file,grep,list_dir' "$TMP/doc-grok.args"
! grep -Fq -- '--cwd' "$TMP/doc-grok.args"
# Forced structured output let Grok answer without reading (15 Oct 2026); the
# runner asks for the JSON wrapper instead and keeps it beside the reply.
grep -Fq -- '--output-format json' "$TMP/doc-grok.args"
! grep -Fq -- '--json-schema' "$TMP/doc-grok.args"
test "$(cat "$TMP/doc-grok.timeout")" = 27
test -f "$GROK_PAIR/results/breadth-coherence.json"
grep -Fq '"num_turns": 4' "$GROK_PAIR/raw-breadth-coherence.grok.txt"
# A one-turn Grok answer opened no file: the leg fails and records no result.
env PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_GROK_TIMEOUT="$TMP/doc-grok.timeout" FAKE_GROK_TURNS=1 FAKE_GROK_ARGS="$TMP/doc-grok-one.args" DOC_GAUNTLET_DIR="$GROK_PAIR" "$RUNNER" run-cli --lens feasibility
wait_for_leg "$GROK_PAIR" breadth-feasibility
test ! -e "$GROK_PAIR/results/breadth-feasibility.json"
grep -Fq 'answered in one turn without opening a file' "$GROK_PAIR/failures/breadth-feasibility.txt"
# The home side: under a home holding .claude and .gauntlet but no .agents or .cursor, only the existing two
# are denied, and the leg leaves that home as it found it.
mkdir -p "$TMP/dochome/.grok" "$TMP/dochome/.claude" "$TMP/dochome/.gauntlet"; printf '{}' > "$TMP/dochome/.grok/auth.json"
# The reviewed repo carries an ignored AGENTS.md linking to an ignored CLAUDE.md: the real Grok refuses a
# symlinked deny entry, and so does the fake, so this run fails if the runner denies the link itself.
printf 'AGENTS.md\nCLAUDE.md\n' >> "$REPO/.git/info/exclude"; printf 'instructions\n' > "$REPO/CLAUDE.md"; ln -s CLAUDE.md "$REPO/AGENTS.md"
env HOME="$TMP/dochome" PATH="$TMP/bin:$PATH" REAL_TIMEOUT="$REAL_TIMEOUT" FAKE_GROK_TIMEOUT="$TMP/doc-grok.timeout" FAKE_GROK_ARGS="$TMP/doc-grok-home.args" \
  FAKE_GROK_SANDBOX="$TMP/doc-grok.sandbox" FAKE_GROK_HOME_ROOT="$TMP/dochome" DOC_GAUNTLET_DIR="$GROK_PAIR" "$RUNNER" run-cli --lens scope-guardian
wait_for_leg "$GROK_PAIR" breadth-scope-guardian
test -f "$GROK_PAIR/results/breadth-scope-guardian.json"
grep -Fq "\"$TMP/dochome/.claude\"" "$TMP/doc-grok.sandbox"
grep -Fq "\"$TMP/dochome/.gauntlet\"" "$TMP/doc-grok.sandbox"
if grep -Fq "\"$TMP/dochome/.agents\"" "$TMP/doc-grok.sandbox" || grep -Fq "\"$TMP/dochome/.cursor\"" "$TMP/doc-grok.sandbox"; then exit 1; fi
grep -Fq "/CLAUDE.md\"" "$TMP/doc-grok.sandbox"
rm "$REPO/AGENTS.md" "$REPO/CLAUDE.md"
test ! -e "$TMP/dochome/.agents"
test ! -e "$TMP/dochome/.cursor"
# A repo whose AGENTS.md is a symlink to CLAUDE.md (19 Oct 2026):
# Grok refuses to start when a deny entry is a symlink, so the profile denies the
# link's target and never the link, lists every instruction file it finds, top
# level and nested, uses no ** pattern, and skips a dangling link without
# creating anything. The writer is run straight from the runner script.
SYM="$TMP/symlink-agents"
mkdir -p "$SYM/repo/docs/sub/.claude/rules" "$SYM/repo/.cursor/rules" "$SYM/cwd" "$SYM/run" "$SYM/home"
printf 'instructions\n' > "$SYM/repo/CLAUDE.md"
ln -s CLAUDE.md "$SYM/repo/AGENTS.md"
printf 'nested\n' > "$SYM/repo/docs/sub/CLAUDE.md"
printf 'nested\n' > "$SYM/repo/docs/AGENTS.md"
ln -s ../missing.md "$SYM/repo/docs/sub/AGENTS.md"
printf 'rule\n' > "$SYM/repo/docs/sub/.claude/rules/r.md"
printf 'readme\n' > "$SYM/repo/README.md"
# A symlinked .claude directory pointing outside the repo, holding CLAUDE.md and rules/.
mkdir -p "$SYM/outside/rules"; printf 'linked\n' > "$SYM/outside/CLAUDE.md"; printf 'rule\n' > "$SYM/outside/rules/r.md"
ln -s ../../outside "$SYM/repo/docs/.claude"
(
  eval "$(awk '/^write_grok_sandbox\(\) \{/,/^}$/' "$RUNNER")"
  HOME="$SYM/home" write_grok_sandbox "$SYM/cwd" "$SYM/repo" "$SYM/run" > /dev/null
)
python3 - "$SYM/cwd/.grok/sandbox.toml" "$SYM/repo" <<'PY'
import os, sys, tomllib
profile, repo = sys.argv[1:]
data = tomllib.load(open(profile, "rb"))
(body,) = data["profiles"].values()
deny = body["deny"]
real = os.path.realpath(repo)
for entry in deny:
    assert not os.path.islink(entry), f"deny entry is a symlink: {entry}"
    assert "*" not in entry, f"deny entry is a pattern: {entry}"
    assert os.path.lexists(entry), f"deny entry does not exist: {entry}"
must = ["CLAUDE.md", "docs/AGENTS.md", "docs/sub/CLAUDE.md", "docs/sub/.claude/rules", ".cursor/rules"]
for rel in must:
    assert any(os.path.realpath(e) == os.path.join(real, rel) for e in deny), f"not denied: {rel}"
assert f"{repo}/CLAUDE.md" in deny, "AGENTS.md's target is not denied by path"
assert not any(e.endswith("AGENTS.md") and os.path.realpath(e) == os.path.join(real, "AGENTS.md") for e in deny)
assert not any(e.endswith("README.md") for e in deny), "README.md is denied"
outside = os.path.realpath(os.path.join(repo, "..", "outside"))
for rel in ("CLAUDE.md", "rules"):
    assert os.path.join(outside, rel) in deny, f"not denied inside the linked .claude: {rel}"
assert not os.path.lexists(os.path.join(repo, "docs/missing.md")), "dangling target created"
PY
test ! -e "$SYM/repo/docs/missing.md"
# The adversarial prompt shows the shape of one finding. On 15 Oct 2026 it showed
# the per-reviewer breadth envelope, and Grok, with no schema flag to hold it,
# nested its findings inside that envelope and the leg failed validation.
python3 - "$GROK_PAIR/prompts/adversarial-grok-cli.md" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
at = text.index('Every finding matches this schema:')
schema = json.JSONDecoder().raw_decode(text, text.index('{', at))[0]
assert 'reviewer' not in schema.get('properties', {}), 'adversarial prompt shows the breadth envelope'
assert {'title', 'finding_type', 'severity'} <= set(schema['required']), schema.get('required')
PY

# ---------------------------------------------------------------------------
# Round numbering (plan tests 21 and 22). Own scratch repository, own round
# record, so the absolute counts below are isolated from the scenarios above.
# ---------------------------------------------------------------------------
BUDGET_RECORD="$TMP/record-home/rounds.jsonl"
export GAUNTLET_ROUND_RECORD="$BUDGET_RECORD"
BREPO="$TMP/budget-repo"; mkdir -p "$BREPO/docs"
git init -q -b main "$BREPO"
git -C "$BREPO" config user.name test
git -C "$BREPO" config user.email test@example.invalid
printf '# Spec v1\n' > "$BREPO/docs/spec.md"
printf '# Other v1\n' > "$BREPO/docs/other.md"
printf 'origin v1\n' > "$BREPO/docs/origin.md"
git -C "$BREPO" add . && git -C "$BREPO" commit -qm initial
budget_common="$(git -C "$BREPO" rev-parse --path-format=absolute --git-common-dir)"
budget_short="$(python3 -c 'import os,sys; parts=[p for p in os.path.dirname(sys.argv[1]).split(os.sep) if p]; print("/".join(parts[-2:]))' "$budget_common")"
mode_of() { python3 -c 'import os,stat,sys; print(f"{stat.S_IMODE(os.lstat(sys.argv[1]).st_mode):o}")' "$1"; }
budget_prepare() {
  local run="$1"; shift
  DOC_GAUNTLET_REPO="$BREPO" DOC_GAUNTLET_DIR="$run" "$RUNNER" prepare --authorize-provider --type plan --claude-model fixture --codex-model fixture "$@"
}
accept_breadth() {
  local run="$1" text
  text="$TMP/accept-$(basename "$run").txt"
  printf '{"reviewer":"coherence","findings":[],"residual_risks":[],"deferred_questions":[]}\n' > "$text"
  DOC_GAUNTLET_DIR="$run" "$RUNNER" ingest --lens coherence --transport claude-native --text "$text"
}
accept_pair() {
  local run="$1" head digest engine text
  head="$(cat "$run/head.commit")"; digest="$(cat "$run/scope.digest")"
  for engine in claude codex; do
    text="$TMP/accept-$(basename "$run")-$engine.txt"
    printf '{"engine":"%s","model":"fixture","transport":"%s-native","scope_sha":"%s","scope_digest":"%s","verdict":"CONVERGED","findings":[]}\n' "$engine" "$engine" "$head" "$digest" > "$text"
    DOC_GAUNTLET_DIR="$run" "$RUNNER" ingest --engine "$engine" --transport "$engine-native" --text "$text"
  done
}
record_lines() { if [[ -f "$1" ]]; then wc -l < "$1" | tr -d ' '; else echo 0; fi; }

# Round 1: the identity is doc:<path relative to the repository root>, no line
# is written until a result is accepted, and the modes are 700/600.
B1="$TMP/budget-r1"
budget_prepare "$B1" --doc docs/spec.md > "$TMP/b1.out"
grep -Fx "ROUND-RECORD: non-default $BUDGET_RECORD" "$TMP/b1.out"
grep -Fx "ROUND: 1 identity=doc:docs/spec.md repo=$budget_short" "$TMP/b1.out"
grep -Fx "WORKDIR=$B1" "$TMP/b1.out"
test "$(tail -1 "$TMP/b1.out")" = "WORKDIR=$B1"
test "$(mode_of "$TMP/record-home")" = 700
test "$(record_lines "$BUDGET_RECORD")" = 0
accept_breadth "$B1"
test "$(record_lines "$BUDGET_RECORD")" = 1
test "$(mode_of "$BUDGET_RECORD")" = 600
test -d "$B1/round-recorded"
python3 - "$BUDGET_RECORD" "$budget_common" "$BREPO/docs/spec.md" <<'PY'
import hashlib, json, sys
line = open(sys.argv[1]).readlines()[0].rstrip("\n")
pairs = json.loads(line, object_pairs_hook=list)
assert [k for k, _ in pairs] == ["ts","runner","repo","identity","digest","head","round"], pairs
obj = dict(pairs)
assert line == json.dumps(obj, separators=(",", ":")), line
assert obj["runner"] == "doc-gauntlet", obj
assert obj["repo"] == sys.argv[2], obj
assert obj["identity"] == "doc:docs/spec.md", obj
assert obj["round"] == 1, obj
assert obj["ts"].endswith("+00:00") and len(obj["ts"]) == 25, obj
assert obj["digest"] == hashlib.sha256(open(sys.argv[3], "rb").read()).hexdigest(), obj
PY
# A second accepted result on the same run appends nothing (the marker).
accept_pair "$B1"
test "$(record_lines "$BUDGET_RECORD")" = 1
DOC_GAUNTLET_DIR="$B1" "$RUNNER" collect > "$TMP/b1.collect" || true
grep -Fx 'ROUND-RECORD: non-default record-home/rounds.jsonl' "$TMP/b1.collect"
grep -Fx "ROUND: 1 identity=doc:docs/spec.md repo=$budget_short" "$TMP/b1.collect"
grep -Fx 'GAUNTLET: RUNNING' "$TMP/b1.collect"

# --- One round on every document (23 Nov 2026) -------------------------------
# Each case has its own scratch repository and its own record. A round is
# reviewed on a branch; what happens to the branch decides whether a changed
# document prepares.
rr_new() {
  local base="${2:-main}"
  RR="$TMP/rr-$1"; RRREC="$TMP/rr-$1.jsonl"; mkdir -p "$RR/docs"
  git init -q -b "$base" "$RR"
  git -C "$RR" config user.name test
  git -C "$RR" config user.email test@example.invalid
  printf '# Spec v1\n' > "$RR/docs/spec.md"
  git -C "$RR" add . && git -C "$RR" commit -qm initial
  git -C "$RR" checkout -qb feature
}
rr_prepare() {
  local run="$1"; shift
  GAUNTLET_ROUND_RECORD="$RRREC" DOC_GAUNTLET_REPO="$RR" DOC_GAUNTLET_DIR="$run" "$RUNNER" prepare --authorize-provider --type plan --claude-model fixture --codex-model fixture --doc docs/spec.md "$@"
}
rr_edit() { printf '%s\n' "$1" > "$RR/docs/spec.md"; git -C "$RR" commit -qam "$1"; }
# One reviewed round on the current content: prepare, accept a result (which
# writes the record line), clean the scratch run.
rr_review() {
  local run="$TMP/rr-run-$1"
  rr_prepare "$run" > "$TMP/rr-run-$1.out"
  accept_breadth "$run"
  DOC_GAUNTLET_DIR="$run" "$RUNNER" clean --force
}
rr_refused() {
  local run="$1" status=0; shift
  rr_prepare "$run" "$@" > "$run.out" 2> "$run.err" || status=$?
  test "$status" = 2
  test ! -e "$run"
}

# The refusal: a changed document on the branch whose round has not merged.
rr_new refuse
rr_edit '# Spec v2'
rr_review refuse-r1
refuse_head="$(git -C "$RR" rev-parse HEAD)"
rr_edit '# Spec v3'
rr_refused "$TMP/rr-refuse-2"
# The date in the refusal is the recorded round's own, read from its record
# line, never today's.
refuse_date="$(python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).readlines()[0])["ts"][:10])' "$RRREC")"
grep -Fq "REFUSED: doc:docs/spec.md already had its one round on this branch: round 1 at ${refuse_head:0:12}, $refuse_date (23 Nov 2026" "$TMP/rr-refuse-2.err"
grep -Fq 'apply the verified errors and check the fixes against the findings, after which the document goes to its owner' "$TMP/rr-refuse-2.err"
grep -Fq 'when the reviewed change has merged, run git fetch and start the new work on a new branch from the default branch' "$TMP/rr-refuse-2.err"
if grep -q 'WORKDIR=' "$TMP/rr-refuse-2.out"; then exit 1; fi
test "$(record_lines "$RRREC")" = 1
# --override-round-budget is accepted, ignored, and does not lift the refusal.
rr_refused "$TMP/rr-refuse-override" --override-round-budget 'an old go'
grep -Fq 'REFUSED: doc:docs/spec.md' "$TMP/rr-refuse-override.err"
# An unknown label stops with one line naming the two.
rr_refused "$TMP/rr-refuse-label" --second-review again
test "$(cat "$TMP/rr-refuse-label.err")" = "--second-review takes proposal (a client proposal's second fact-check round) or asked (a second review the requester asked for)"
# So does an empty label: it is not the same as leaving the flag out.
rr_refused "$TMP/rr-refuse-empty" --second-review ''
test "$(cat "$TMP/rr-refuse-empty.err")" = "--second-review takes proposal (a client proposal's second fact-check round) or asked (a second review the requester asked for)"
# Unchanged content is a retry of its recorded round, never refused, even with
# a later commit on the branch.
rr_edit '# Spec v2'
RRRETRY="$TMP/rr-refuse-retry"
rr_prepare "$RRRETRY" > "$TMP/rr-refuse-retry.out"
grep -Fq 'ROUND: 1 (retry of recorded round 1) identity=doc:docs/spec.md' "$TMP/rr-refuse-retry.out"
DOC_GAUNTLET_DIR="$RRRETRY" "$RUNNER" clean --force

# A labelled second review prepares, shows its label, and records it; a retry of
# that second content then prepares with no flag.
rr_edit '# Spec v3'
RRLAB="$TMP/rr-label"
rr_prepare "$RRLAB" --second-review proposal > "$TMP/rr-label.out"
grep -Fq 'ROUND: 2 (second review: proposal) identity=doc:docs/spec.md' "$TMP/rr-label.out"
grep -Fq '"second_review": "proposal"' "$RRLAB/rows.json"
accept_breadth "$RRLAB"
test "$(record_lines "$RRREC")" = 2
python3 - "$RRREC" <<'PY'
import json, sys
obj = json.loads(open(sys.argv[1]).readlines()[1])
assert obj["round"] == 2 and obj["second_review"] == "proposal", obj
first = json.loads(open(sys.argv[1]).readlines()[0])
assert "second_review" not in first, first
PY
DOC_GAUNTLET_DIR="$RRLAB" "$RUNNER" collect > "$TMP/rr-label.collect" || true
grep -Fq 'ROUND: 2 (second review: proposal) identity=doc:docs/spec.md' "$TMP/rr-label.collect"
DOC_GAUNTLET_DIR="$RRLAB" "$RUNNER" clean --force
git -C "$RR" commit -q --allow-empty -m later
RRLABR="$TMP/rr-label-retry"
rr_prepare "$RRLABR" > "$TMP/rr-label-retry.out"
grep -Fq 'ROUND: 2 (retry of recorded round 2) identity=doc:docs/spec.md' "$TMP/rr-label-retry.out"
DOC_GAUNTLET_DIR="$RRLABR" "$RUNNER" clean --force
# A third content is refused whatever the label: without one as the one round,
# with one as the second review already run.
label_head="$(git -C "$RR" log -1 --format=%H --grep='^# Spec v3$')"
rr_edit '# Spec v4'
rr_refused "$TMP/rr-label-third"
grep -Fq 'REFUSED: doc:docs/spec.md already had its one round on this branch' "$TMP/rr-label-third.err"
for third in proposal asked; do
  rr_refused "$TMP/rr-label-third-$third" --second-review "$third"
  grep -Fq "REFUSED: doc:docs/spec.md already had its second review on this branch: round 2 at ${label_head:0:12}, " "$TMP/rr-label-third-$third.err"
  grep -Fq '(proposal). No third round runs, whatever the label.' "$TMP/rr-label-third-$third.err"
done
# A refusal writes nothing: the record still holds the round and its second review.
test "$(record_lines "$RRREC")" = 2

# The other label, asked, runs the one second review and records it. A label
# where no second review runs (a first round, a retry of recorded content)
# records nothing, so a labelled line is always a second review that ran.
rr_new asked
rr_edit '# Spec v2'
RRA1="$TMP/rr-asked-1"
rr_prepare "$RRA1" --second-review asked > "$TMP/rr-asked-1.out"
grep -Fq 'ROUND: 1 identity=doc:docs/spec.md' "$TMP/rr-asked-1.out"
accept_breadth "$RRA1"
DOC_GAUNTLET_DIR="$RRA1" "$RUNNER" clean --force
git -C "$RR" commit -q --allow-empty -m later
RRA1R="$TMP/rr-asked-1-retry"
rr_prepare "$RRA1R" --second-review asked > "$TMP/rr-asked-1-retry.out"
grep -Fq 'ROUND: 1 (retry of recorded round 1) identity=doc:docs/spec.md' "$TMP/rr-asked-1-retry.out"
accept_breadth "$RRA1R"
DOC_GAUNTLET_DIR="$RRA1R" "$RUNNER" clean --force
test "$(record_lines "$RRREC")" = 2
python3 - "$RRREC" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    assert "second_review" not in json.loads(line), line
PY
rr_edit '# Spec v3'
asked_head="$(git -C "$RR" rev-parse HEAD)"
RRA2="$TMP/rr-asked-2"
rr_prepare "$RRA2" --second-review asked > "$TMP/rr-asked-2.out"
grep -Fq 'ROUND: 2 (second review: asked) identity=doc:docs/spec.md' "$TMP/rr-asked-2.out"
accept_breadth "$RRA2"
DOC_GAUNTLET_DIR="$RRA2" "$RUNNER" clean --force
python3 - "$RRREC" <<'PY'
import json, sys
lines = [json.loads(line) for line in open(sys.argv[1])]
assert len(lines) == 3 and lines[2]["round"] == 2 and lines[2]["second_review"] == "asked", lines
assert [("second_review" in line) for line in lines] == [False, False, True], lines
PY
rr_edit '# Spec v4'
rr_refused "$TMP/rr-asked-third" --second-review asked
grep -Fq "REFUSED: doc:docs/spec.md already had its second review on this branch: round 2 at ${asked_head:0:12}, " "$TMP/rr-asked-third.err"

# A recorded round whose commit this repository does not have never blocks.
rr_new foreign
rr_edit '# Spec v2'
printf '{"ts":"2026-11-01T00:00:00+00:00","runner":"doc-gauntlet","repo":"%s","identity":"doc:docs/spec.md","digest":"%s","head":"0123456789abcdef0123456789abcdef01234567","round":1}\n' "$(git -C "$RR" rev-parse --path-format=absolute --git-common-dir)" "$(printf 'elsewhere' | shasum -a 256 | cut -d' ' -f1)" > "$RRREC"
RRFH="$TMP/rr-foreign-2"
rr_prepare "$RRFH" > "$TMP/rr-foreign-2.out"
grep -Fq 'ROUND: 2 identity=doc:docs/spec.md' "$TMP/rr-foreign-2.out"
DOC_GAUNTLET_DIR="$RRFH" "$RUNNER" clean --force

# The reviewed commit merged into the default branch by a merge commit: the
# same branch carries on and a changed document is a new review.
rr_new merged
rr_edit '# Spec v2'
rr_review merged-r1
git -C "$RR" checkout -q main
git -C "$RR" merge -q --no-ff -m merge feature
git -C "$RR" checkout -q feature
rr_edit '# Spec v3'
RRM="$TMP/rr-merged-2"
rr_prepare "$RRM" > "$TMP/rr-merged-2.out"
grep -Fq 'ROUND: 2 identity=doc:docs/spec.md' "$TMP/rr-merged-2.out"
DOC_GAUNTLET_DIR="$RRM" "$RUNNER" clean --force

# Squash-merged: a new branch from the default branch is a new review; the
# squashed branch itself, still in use, is refused.
rr_new squash
rr_edit '# Spec v2'
rr_review squash-r1
git -C "$RR" checkout -q main
git -C "$RR" merge -q --squash feature
git -C "$RR" commit -qm squash
git -C "$RR" checkout -qb next
rr_edit '# Spec v3'
RRS="$TMP/rr-squash-2"
rr_prepare "$RRS" > "$TMP/rr-squash-2.out"
grep -Fq 'ROUND: 2 identity=doc:docs/spec.md' "$TMP/rr-squash-2.out"
DOC_GAUNTLET_DIR="$RRS" "$RUNNER" clean --force
git -C "$RR" checkout -q feature
rr_edit '# Spec v4'
rr_refused "$TMP/rr-squash-stale"
grep -Fq 'REFUSED: doc:docs/spec.md' "$TMP/rr-squash-stale.err"

# A second branch from the same base does not contain the reviewed commit.
rr_new sibling
rr_edit '# Spec v2'
rr_review sibling-r1
git -C "$RR" checkout -q main
git -C "$RR" checkout -qb other
rr_edit '# Spec v3'
RRB="$TMP/rr-sibling-2"
rr_prepare "$RRB" > "$TMP/rr-sibling-2.out"
grep -Fq 'ROUND: 2 identity=doc:docs/spec.md' "$TMP/rr-sibling-2.out"
DOC_GAUNTLET_DIR="$RRB" "$RUNNER" clean --force

# No default branch resolves (no origin, no main, no master): nothing is refused.
rr_new nodefault trunk
rr_edit '# Spec v2'
rr_review nodefault-r1
rr_edit '# Spec v3'
RRN="$TMP/rr-nodefault-2"
rr_prepare "$RRN" > "$TMP/rr-nodefault-2.out"
grep -Fq 'ROUND: 2 identity=doc:docs/spec.md' "$TMP/rr-nodefault-2.out"
DOC_GAUNTLET_DIR="$RRN" "$RUNNER" clean --force

# A record written under the retired budget (override, lineage, supersedes keys,
# a lineage round above the distinct count) still parses and never numbers backwards.
LEGACY_RECORD="$TMP/legacy-record/rounds.jsonl"; mkdir -p "$(dirname "$LEGACY_RECORD")"
printf '{"ts":"2026-09-14T00:00:00+00:00","runner":"doc-gauntlet","repo":"%s","identity":"doc:docs/other.md","digest":"%s","head":"x","round":5,"override":"old go","lineage":[],"supersedes":[]}\n' "$budget_common" "$(printf 'z' | shasum -a 256 | cut -d' ' -f1)" > "$LEGACY_RECORD"
GAUNTLET_ROUND_RECORD="$LEGACY_RECORD" budget_prepare "$TMP/budget-legacy-record" --doc docs/other.md > "$TMP/legrec.out"
grep -Fx "ROUND: 6 identity=doc:docs/other.md repo=$budget_short" "$TMP/legrec.out"
DOC_GAUNTLET_DIR="$TMP/budget-legacy-record" "$RUNNER" clean --force

# A second document on the same HEAD is round 1.
BO="$TMP/budget-other"
budget_prepare "$BO" --doc docs/other.md > "$TMP/bo.out"
grep -Fx "ROUND: 1 identity=doc:docs/other.md repo=$budget_short" "$TMP/bo.out"
accept_breadth "$BO"
test "$(record_lines "$BUDGET_RECORD")" = 2

# An unrelated commit moves HEAD; the unchanged document is a retry.
printf 'origin v2\n' > "$BREPO/docs/origin.md"; git -C "$BREPO" commit -qam origin2
BO2="$TMP/budget-other-2"
budget_prepare "$BO2" --doc docs/other.md > "$TMP/bo2.out"
grep -Fx "ROUND: 1 (retry of recorded round 1) identity=doc:docs/other.md repo=$budget_short" "$TMP/bo2.out"
test "$(cat "$BO2/head.commit")" != "$(cat "$BO/head.commit")"

# A changed origin with an unchanged document is a retry: the round key is the
# document's own bytes, never the combined scope digest.
BO3="$TMP/budget-other-3"
budget_prepare "$BO3" --doc docs/other.md --origin docs/origin.md > "$TMP/bo3.out"
grep -Fq 'ROUND: 1 (retry of recorded round 1)' "$TMP/bo3.out"
printf 'origin v3\n' > "$BREPO/docs/origin.md"; git -C "$BREPO" commit -qam origin3
BO4="$TMP/budget-other-4"
budget_prepare "$BO4" --doc docs/other.md --origin docs/origin.md > "$TMP/bo4.out"
grep -Fq 'ROUND: 1 (retry of recorded round 1)' "$TMP/bo4.out"
test "$(cat "$BO4/scope.digest")" != "$(cat "$BO3/scope.digest")"

# A changed document reviewed on the default branch itself is a new round: its
# earlier round is already in the default branch, so it counts as merged.
printf '# Other v2\n' > "$BREPO/docs/other.md"; git -C "$BREPO" commit -qam other2
BO5="$TMP/budget-other-5"
budget_prepare "$BO5" --doc docs/other.md > "$TMP/bo5.out"
grep -Fx "ROUND: 2 identity=doc:docs/other.md repo=$budget_short" "$TMP/bo5.out"

# No lineage anywhere in document output.
cat "$TMP/b1.out" "$TMP/b1.collect" "$TMP/rr-refuse-retry.out" "$TMP/rr-label.out" "$TMP/rr-label.collect" "$TMP/bo.out" "$TMP/bo2.out" "$TMP/bo5.out" > "$TMP/doc-round-output.txt"
! grep -Fq 'lineage=' "$TMP/doc-round-output.txt"
! grep -Fq 'LINEAGE:' "$TMP/doc-round-output.txt"

# A rows.json without identity collects exactly as before.
BLEG="$TMP/budget-legacy"
budget_prepare "$BLEG" --doc docs/other.md >/dev/null
python3 - "$BLEG/rows.json" <<'PY'
import json, sys
path = sys.argv[1]; rows = json.load(open(path))
for key in ("identity","round","retry","digest","head","repo","repo_short","round_record","round_record_default"):
    rows.pop(key, None)
open(path, "w").write(json.dumps(rows) + "\n")
PY
DOC_GAUNTLET_DIR="$BLEG" "$RUNNER" collect > "$TMP/legacy.collect" || true
grep -Fx 'GAUNTLET: RUNNING' "$TMP/legacy.collect"
! grep -q 'ROUND' "$TMP/legacy.collect"
DOC_GAUNTLET_DIR="$BLEG" "$RUNNER" clean --force

# --- Test 22: breadth once, then --pair-only rounds -------------------------
PAIR_RECORD="$TMP/pair-record/rounds.jsonl"
export GAUNTLET_ROUND_RECORD="$PAIR_RECORD"
printf '# Pair doc v1\n' > "$BREPO/docs/pairdoc.md"
git -C "$BREPO" add docs/pairdoc.md && git -C "$BREPO" commit -qm pairdoc
printf '{"findings":[{"status":"accepted","section":"Round one"}]}\n' > "$TMP/pair-prior.json"

status=0; budget_prepare "$TMP/pair-no-prior" --doc docs/pairdoc.md --pair-only >/dev/null 2> "$TMP/pair-no-prior.err" || status=$?
test "$status" = 2
test ! -e "$TMP/pair-no-prior"
grep -Fq -- '--pair-only requires --prior-findings: without the earlier rounds'"'"' findings the pair is a discovery pass' "$TMP/pair-no-prior.err"
status=0; budget_prepare "$TMP/pair-no-round" --doc docs/pairdoc.md --pair-only --prior-findings "$TMP/pair-prior.json" >/dev/null 2> "$TMP/pair-no-round.err" || status=$?
test "$status" = 2
test ! -e "$TMP/pair-no-round"
grep -Fq -- '--pair-only needs a recorded round on doc:docs/pairdoc.md; the first round runs breadth' "$TMP/pair-no-round.err"

P1="$TMP/pair-r1"
budget_prepare "$P1" --doc docs/pairdoc.md > "$TMP/p1.out"
grep -Fq 'ROUND: 1 identity=doc:docs/pairdoc.md' "$TMP/p1.out"
test -f "$P1/prompts/breadth-coherence.md"
accept_breadth "$P1"
test "$(record_lines "$PAIR_RECORD")" = 1

# A plain run on the same content is a retry with breadth; --pair-only retries
# the pair alone on that content.
PPLAIN="$TMP/pair-r2-plain"
budget_prepare "$PPLAIN" --doc docs/pairdoc.md > "$TMP/pplain.out"
grep -Fq 'ROUND: 1 (retry of recorded round 1) identity=doc:docs/pairdoc.md' "$TMP/pplain.out"
test -f "$PPLAIN/prompts/breadth-coherence.md"
DOC_GAUNTLET_DIR="$PPLAIN" "$RUNNER" clean --force

P2="$TMP/pair-r2"
budget_prepare "$P2" --doc docs/pairdoc.md --pair-only --prior-findings "$TMP/pair-prior.json" > "$TMP/p2.out"
grep -Fq 'ROUND: 1 (retry of recorded round 1) identity=doc:docs/pairdoc.md' "$TMP/p2.out"
grep -Fq '"pair_only": true' "$P2/rows.json"
test ! -e "$P2/prompts/breadth-coherence.md"
test ! -e "$P2/schemas/breadth-coherence.json"
test -f "$P2/prompts/adversarial-claude-cli.md"
test -f "$P2/schemas/adversarial-codex-cli.json"
grep -Fq 'Round one' "$P2/prompts/adversarial-claude-cli.md"
status=0; DOC_GAUNTLET_DIR="$P2" "$RUNNER" run-cli --lens coherence >/dev/null 2> "$TMP/p2-run-lens.err" || status=$?
test "$status" = 2
grep -Fq 'prepared with --pair-only' "$TMP/p2-run-lens.err"
status=0; DOC_GAUNTLET_DIR="$P2" "$RUNNER" ingest --lens coherence --transport claude-native --text "$TMP/accept-pair-r1.txt" >/dev/null 2> "$TMP/p2-ingest-lens.err" || status=$?
test "$status" = 2
grep -Fq 'prepared with --pair-only' "$TMP/p2-ingest-lens.err"
DOC_GAUNTLET_DIR="$P2" "$RUNNER" collect > "$TMP/p2-running.out" || true
grep -Fx 'GAUNTLET: RUNNING' "$TMP/p2-running.out"
grep -Fx 'RUNNING: claude codex' "$TMP/p2-running.out"
accept_pair "$P2"
DOC_GAUNTLET_DIR="$P2" "$RUNNER" collect > "$TMP/p2.collect"
grep -Fx 'ADVERSARIAL: CONVERGED' "$TMP/p2.collect"
grep -Fq 'ROUND: 1 (retry of recorded round 1) identity=doc:docs/pairdoc.md' "$TMP/p2.collect"
! grep -q 'RUNNING' "$TMP/p2.collect"
test "$(record_lines "$PAIR_RECORD")" = 2
python3 - "$PAIR_RECORD" <<'PY'
import json, sys
obj = json.loads(open(sys.argv[1]).readlines()[1])
assert obj["round"] == 1 and obj["identity"] == "doc:docs/pairdoc.md", obj
PY
DOC_GAUNTLET_DIR="$P2" "$RUNNER" clean
test ! -e "$P2"

# A pair retry after the lenses are in has several results files, one
# --prior-findings each: prepare snapshots every one, in order, never only the
# last (27 Oct 2026, the pair saw only the security lens's findings). A file
# with no final newline does not run into the next one.
printf '{"reviewer":"coherence","findings":[{"status":"accepted","section":"Coherence marker"}]}\n' > "$TMP/prior-coherence.json"
printf '{"reviewer":"security-lens","findings":[{"status":"accepted","section":"Security marker"}]}' > "$TMP/prior-security.json"
printf '{"engine":"codex","findings":[{"status":"accepted","section":"Codex marker"}]}\n' > "$TMP/prior-codex.json"
PMULTI="$TMP/pair-r2-multi"
budget_prepare "$PMULTI" --doc docs/pairdoc.md --pair-only --prior-findings "$TMP/prior-coherence.json" --prior-findings "$TMP/prior-security.json" --prior-findings "$TMP/prior-codex.json" >/dev/null
test "$(grep -c '^{' "$PMULTI/scope/prior-findings.snapshot")" = 3
test "$(sed -n 2p "$PMULTI/scope/prior-findings.snapshot")" = "$(cat "$TMP/prior-security.json")"
for marker in 'Coherence marker' 'Security marker' 'Codex marker'; do
  grep -Fq "$marker" "$PMULTI/prompts/adversarial-claude-cli.md"
  grep -Fq "$marker" "$PMULTI/prompts/adversarial-codex-native.md"
done
DOC_GAUNTLET_DIR="$PMULTI" "$RUNNER" clean --force
# Every file is checked, not only the last one given.
status=0; budget_prepare "$TMP/pair-r2-missing" --doc docs/pairdoc.md --pair-only --prior-findings "$TMP/no-such-findings.json" --prior-findings "$TMP/prior-codex.json" >/dev/null 2> "$TMP/pair-r2-missing.err" || status=$?
test "$status" = 2
test ! -e "$TMP/pair-r2-missing"
grep -Fq 'prior findings must be a non-symlink regular file' "$TMP/pair-r2-missing.err"

# A record made unwritable after prepare keeps the accepted result and its
# sentinel; collect reports the failed write and retries it exactly once.
FAIL_RECORD="$TMP/fail-record/rounds.jsonl"
export GAUNTLET_ROUND_RECORD="$FAIL_RECORD"
printf '# Write failure doc\n' > "$BREPO/docs/failrec.md"
git -C "$BREPO" add docs/failrec.md && git -C "$BREPO" commit -qm failrec
FR="$TMP/fail-run"
budget_prepare "$FR" --doc docs/failrec.md >/dev/null
chmod 400 "$FAIL_RECORD"
accept_breadth "$FR"
test -f "$FR/results/breadth-coherence.json"
test -f "$FR/completion/breadth-coherence.done"
test -f "$FR/failures/round-record.txt"
test ! -e "$FR/round-recorded"
test "$(record_lines "$FAIL_RECORD")" = 0
DOC_GAUNTLET_DIR="$FR" "$RUNNER" collect > "$TMP/fr1.collect" || true
grep -Fq 'ROUND-RECORD: WRITE FAILED' "$TMP/fr1.collect"
test "$(record_lines "$FAIL_RECORD")" = 0
chmod 600 "$FAIL_RECORD"
DOC_GAUNTLET_DIR="$FR" "$RUNNER" collect > "$TMP/fr2.collect" || true
grep -Fq 'ROUND-RECORD: WRITE FAILED' "$TMP/fr2.collect"
test "$(record_lines "$FAIL_RECORD")" = 1
test -d "$FR/round-recorded"
test ! -e "$FR/failures/round-record.txt"
DOC_GAUNTLET_DIR="$FR" "$RUNNER" collect > "$TMP/fr3.collect" || true
! grep -Fq 'WRITE FAILED' "$TMP/fr3.collect"
test "$(record_lines "$FAIL_RECORD")" = 1
DOC_GAUNTLET_DIR="$FR" "$RUNNER" clean --force

# Code gauntlet round 1 repairs (13 Sep 2026): a symlinked record path is
# refused, a record under a symlinked directory is probed where the bytes would
# land, and a crashed append (a claim with no completion) is released and
# retried by collect exactly once.
mkdir -p "$TMP/doc-link-home"
printf 'do not touch\n' > "$TMP/doc-link-home/target.txt"
ln -s "$TMP/doc-link-home/target.txt" "$TMP/doc-link-home/rounds.jsonl"
status=0; GAUNTLET_ROUND_RECORD="$TMP/doc-link-home/rounds.jsonl" budget_prepare "$TMP/doc-sym1" --doc docs/failrec.md >/dev/null 2> "$TMP/doc-sym1.err" || status=$?
test "$status" -eq 2
grep -Fq 'is a symlink; point GAUNTLET_ROUND_RECORD at a regular file path' "$TMP/doc-sym1.err"
test ! -e "$TMP/doc-sym1"
test "$(cat "$TMP/doc-link-home/target.txt")" = 'do not touch'
mkdir -p "$BREPO/record-target"
ln -s "$BREPO/record-target" "$TMP/doc-link-home/into-repo"
status=0; GAUNTLET_ROUND_RECORD="$TMP/doc-link-home/into-repo/rounds.jsonl" budget_prepare "$TMP/doc-sym2" --doc docs/failrec.md >/dev/null 2> "$TMP/doc-sym2.err" || status=$?
test "$status" -eq 2
grep -Fq 'lies inside a git worktree and is not ignored there' "$TMP/doc-sym2.err"
test ! -e "$BREPO/record-target/rounds.jsonl"
test ! -e "$TMP/doc-sym2"
rmdir "$BREPO/record-target"

CRASH_RECORD="$TMP/crash-record/rounds.jsonl"
export GAUNTLET_ROUND_RECORD="$CRASH_RECORD"
CR="$TMP/crash-run"
budget_prepare "$CR" --doc docs/failrec.md >/dev/null
mkdir "$CR/round-recording"
accept_breadth "$CR"
test -f "$CR/results/breadth-coherence.json"
test ! -e "$CR/round-recorded"
test "$(record_lines "$CRASH_RECORD")" = 0
DOC_GAUNTLET_DIR="$CR" "$RUNNER" collect > "$TMP/cr1.collect" || true
grep -Fx 'ROUND-RECORD: WRITE FAILED the append was claimed and never completed' "$TMP/cr1.collect"
test -d "$CR/round-recorded"
test "$(record_lines "$CRASH_RECORD")" = 1
DOC_GAUNTLET_DIR="$CR" "$RUNNER" collect > "$TMP/cr2.collect" || true
! grep -Fq 'WRITE FAILED' "$TMP/cr2.collect"
test "$(record_lines "$CRASH_RECORD")" = 1
DOC_GAUNTLET_DIR="$CR" "$RUNNER" clean --force

# Code gauntlet round 2 repairs (13 Sep 2026). A claim held by a live worker
# (its launch lock carries a PID that is alive) is an append in flight: collect
# neither reports it nor appends; once that PID is gone the claim is recovered.
LIVE="$TMP/live-run"
budget_prepare "$LIVE" --doc docs/failrec.md >/dev/null
mkdir "$LIVE/round-recording" "$LIVE/locks/breadth-coherence.lock"
sleep 120 & holder=$!
printf '%s\n' "$holder" > "$LIVE/locks/breadth-coherence.lock/pid"
DOC_GAUNTLET_DIR="$LIVE" "$RUNNER" collect > "$TMP/live1.collect" || true
! grep -Fq 'WRITE FAILED' "$TMP/live1.collect"
test ! -e "$LIVE/round-recorded"
test "$(record_lines "$CRASH_RECORD")" = 1
kill "$holder"; wait "$holder" 2>/dev/null || true
DOC_GAUNTLET_DIR="$LIVE" "$RUNNER" collect > "$TMP/live2.collect" || true
grep -Fx 'ROUND-RECORD: WRITE FAILED the append was claimed and never completed' "$TMP/live2.collect"
test -d "$LIVE/round-recorded"
test "$(record_lines "$CRASH_RECORD")" = 2
DOC_GAUNTLET_DIR="$LIVE" "$RUNNER" clean --force

# Record lines that parse as JSON but carry the wrong types are skipped with
# the malformed-line warning, never counted and never formatted into a refusal;
# code-runner lines for the same repository never count as document rounds.
TYPED_RECORD="$TMP/typed-record/rounds.jsonl"
mkdir -p "$TMP/typed-record"
export GAUNTLET_ROUND_RECORD="$TYPED_RECORD"
printf '# Typed doc\n' > "$BREPO/docs/typed.md"
git -C "$BREPO" add docs/typed.md && git -C "$BREPO" commit -qm typed
typed_head="$(git -C "$BREPO" rev-parse HEAD)"
python3 - "$TYPED_RECORD" "$budget_common" "$typed_head" <<'PY'
import json, sys
record, repo, head = sys.argv[1:]
rows = [
    {"ts": "2026-09-13T00:00:00+00:00", "runner": "doc-gauntlet", "repo": repo, "identity": "doc:docs/typed.md", "digest": 1111, "head": head, "round": 1, "override": None, "lineage": [], "supersedes": []},
    {"ts": "2026-09-13T00:00:00+00:00", "runner": "doc-gauntlet", "repo": repo, "identity": 2222, "digest": "c" * 64, "head": head, "round": 2, "override": None, "lineage": [], "supersedes": []},
    {"ts": "2026-09-13T00:00:00+00:00", "runner": "doc-gauntlet", "repo": repo, "identity": "doc:docs/typed.md", "digest": "d" * 64, "head": head, "round": True, "override": None, "lineage": [], "supersedes": []},
    {"ts": "2026-09-13T00:00:00+00:00", "runner": "gauntlet", "repo": repo, "identity": "doc:docs/typed.md", "digest": "e" * 64, "head": head, "round": 1, "override": None, "lineage": [], "supersedes": []},
    {"ts": "2026-09-13T00:00:00+00:00", "runner": "gauntlet", "repo": repo, "identity": "doc:docs/typed.md", "digest": "f" * 64, "head": head, "round": 2, "override": None, "lineage": [], "supersedes": []},
]
with open(record, "w") as handle:
    for row in rows:
        handle.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
TYPED="$TMP/typed-run"
budget_prepare "$TYPED" --doc docs/typed.md > "$TMP/typed.out" 2> "$TMP/typed.err"
grep -Fx "ROUND: 1 identity=doc:docs/typed.md repo=$budget_short" "$TMP/typed.out"
test "$(grep -c 'round record: skipping malformed line' "$TMP/typed.err")" = 3
grep -Fq "round record: skipping malformed line 1 in $TYPED_RECORD" "$TMP/typed.err"
! grep -Fq 'Traceback' "$TMP/typed.err"
DOC_GAUNTLET_DIR="$TYPED" "$RUNNER" clean --force

DOC_GAUNTLET_DIR="$RUN" "$RUNNER" clean
test ! -e "$RUN"
echo 'doc-gauntlet outcomes: OK'
