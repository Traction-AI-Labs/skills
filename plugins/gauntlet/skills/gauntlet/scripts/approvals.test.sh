#!/usr/bin/env bash
# Approvals that stand and findings kept as written (retro rulings O5 and O7).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/gauntlet.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GAUNTLET_ROUND_RECORD="$TMP/rounds.jsonl" GAUNTLET_ARCHIVE="$TMP/archive"
refute() { if "$@"; then echo "expected to fail: $*" >&2; exit 1; fi; }
n=0
fresh() { n=$((n + 1)); RUN_DIR="$TMP/run-$n"; }
prep() { fresh; GAUNTLET_REPO="$R" GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" prepare --authorize-provider --base main --profile fast "$@"; }
run() { GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" "$@"; }

new_repo() {
  R="$TMP/$1"; git init -q -b main "$R"
  git -C "$R" config user.name test; git -C "$R" config user.email test@example.invalid
  printf 'base\n' > "$R/app.txt"; printf 'echo ok\n' > "$R/run-once.sh"; git -C "$R" add . && git -C "$R" commit -qm base
  git -C "$R" remote add origin "$2"
  git -C "$R" checkout -qb feature
}
edit() { printf '%s\n' "$2" >> "$R/$1"; git -C "$R" add "$1"; git -C "$R" commit -qm "edit $1"; }

# Ingest a native result: engine, verdict, optional finding location.
result() {
  local run="$1" engine="$2" verdict="$3" loc="${4:-}" sev="${5:-P1}" model sha digest findings='[]'
  model="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["model"])' "$run/rows.json" "$engine")"
  sha="$(sed -n 's/^Scope SHA: //p' "$run/prompts/$engine-native.md")"; digest="$(sed -n 's/^Scope digest: //p' "$run/prompts/$engine-native.md")"
  [[ -z "$loc" ]] || findings="[{\"severity\":\"$sev\",\"location\":\"$loc\",\"failure_mode\":\"f\",\"evidence\":\"e\",\"causal_relation\":\"introduced\",\"verification\":\"v\"}]"
  printf '{"engine":"%s","model":"%s","transport":"%s-native","scope_sha":"%s","scope_digest":"%s","verdict":"%s","findings":%s}\n' "$engine" "$model" "$engine" "$sha" "$digest" "$verdict" "$findings" > "$TMP/result.txt"
  GAUNTLET_DIR="$run" bash "$RUNNER" ingest --engine "$engine" --text "$TMP/result.txt" > /dev/null
}
# Pre-review, run-once and an approved round 1 for identity $1.
converge() {
  prep --identity "$1" --pre-review --builder deepseek --engines grok > /dev/null; result "$RUN_DIR" grok APPROVE
  prep --identity "$1" --run-once > /dev/null
  result "$RUN_DIR" claude APPROVE; result "$RUN_DIR" codex APPROVE
  run collect > "$TMP/collect.out"
}
bring_main_in() {
  git -C "$R" checkout -q main; edit "main-$1.txt" moved; git -C "$R" checkout -q feature
  git -C "$R" merge -q --no-edit main
}

printf 'example-org/example-dashboard\t-\tbash run-once.sh\n' > "$TMP/on.tsv"
export GAUNTLET_ENFORCE_LIST="$TMP/on.tsv"

# 1. O5, enforced: converged, then main brought in with the PR's own diff
#    unchanged. The approval stands and no round is prepared.
new_repo solo https://github.com/example-org/example-dashboard.git
edit app.txt one; edit other.txt two
converge stand
grep -Fq 'GAUNTLET: APPROVE' "$TMP/collect.out"
grep -Fq '"runner":"gauntlet-verdict"' "$TMP/rounds.jsonl"
bring_main_in a
if prep --identity stand > "$TMP/stand.out" 2> "$TMP/stand.err"; then echo 'O5 prepared a round over a standing approval' >&2; exit 1; fi
grep -Fq "APPROVAL STANDS @ $(git -C "$R" rev-parse HEAD)" "$TMP/stand.out"
grep -Fq 'nothing merges automatically' "$TMP/stand.err"
test ! -e "$RUN_DIR/rows.json"

# 1b. O5, enforced: reviewers report every defect, so a round with only P2 and P3
#     findings is a BLOCK. It stands across main like an APPROVE; a round with
#     an open P1 does not.
for id in nits held; do
  new_repo "$id" https://github.com/example-org/example-dashboard.git
  edit app.txt one
  prep --identity "$id" --pre-review --builder deepseek --engines grok > /dev/null; result "$RUN_DIR" grok APPROVE
  prep --identity "$id" --run-once > /dev/null
  sev=P2; [[ "$id" == nits ]] || sev=P1
  result "$RUN_DIR" claude BLOCK app.txt:1 P3; result "$RUN_DIR" codex BLOCK app.txt:2 "$sev"; run collect > /dev/null || true
  bring_main_in "$id"
done
R="$TMP/nits"
if prep --identity nits > "$TMP/nits.out" 2> /dev/null; then echo 'O5 prepared a round over a nit-only round' >&2; exit 1; fi
grep -Fq "APPROVAL STANDS @ $(git -C "$R" rev-parse HEAD)" "$TMP/nits.out"
R="$TMP/held"
prep --identity held > "$TMP/held.out"
refute grep -Fq 'APPROVAL STANDS' "$TMP/held.out"
grep -Fq 'GAUNTLET_DIR=' "$TMP/held.out"
R="$TMP/solo"

# 2. O5, enforced: a merge fix changes one file of the PR's own diff. Only that
#    file is the review scope.
edit app.txt merge-fix
prep --identity stand > "$TMP/fix.out"
grep -Fq 'MERGE FIX' "$TMP/fix.out"
grep -Fxq '  app.txt' "$TMP/fix.out"
grep -Fxq 'other.txt' "$RUN_DIR/scope/excludes"
grep -Fq 'app.txt' "$RUN_DIR/scope/diff.patch"
refute grep -Fq 'other.txt' "$RUN_DIR/scope/diff.patch"

# 2b. A retried merge-fix round (one leg already recorded the round) is still
#     narrowed, so it is the same round, not a new one over the whole diff.
result "$RUN_DIR" claude APPROVE
prep --identity stand > "$TMP/fix-retry.out"
grep -Fq 'ROUND: 2 ' "$TMP/fix-retry.out"
grep -Fxq '  app.txt' "$TMP/fix-retry.out"
grep -Fxq 'other.txt' "$RUN_DIR/scope/excludes"

# 3. O5 off the list: the same standing approval is a warning and the round
#    prepares as today, unnarrowed.
export GAUNTLET_ENFORCE_LIST=/dev/null
new_repo plain https://github.com/example/plain.git
edit app.txt one; edit other.txt two
prep --identity plain > /dev/null; result "$RUN_DIR" claude APPROVE; result "$RUN_DIR" codex APPROVE; run collect > /dev/null
bring_main_in b
prep --identity plain > "$TMP/plain.out" 2> "$TMP/plain.err"
grep -Fq 'APPROVAL STANDS' "$TMP/plain.out"
grep -Fq 'WARNING (not enforced for example/plain): the approval stands' "$TMP/plain.err"
grep -Fq 'GAUNTLET_DIR=' "$TMP/plain.out"
edit app.txt merge-fix
prep --identity plain > "$TMP/plainfix.out" 2> "$TMP/plainfix.err"
grep -Fq 'scope would narrow to the merge fix' "$TMP/plainfix.err"
grep -Fq 'other.txt' "$RUN_DIR/scope/diff.patch"
export GAUNTLET_ENFORCE_LIST="$TMP/on.tsv"

# 4. O7, enforced: findings are kept as written. A disposition needs a test,
#    a failing test is refused and recorded, a passing one is accepted.
R="$TMP/solo"
edit third.txt three
prep --identity stand --timeout-seconds 2 > /dev/null
result "$RUN_DIR" claude APPROVE; result "$RUN_DIR" codex BLOCK third.txt:1
run collect > "$TMP/f.out"
grep -Fq 'FINDINGS: 1 as written, 1 open' "$TMP/f.out"
grep -Fq 'OPEN codex#1 P1 third.txt:1' "$TMP/f.out"
if run dispose --engine codex --finding 1 --action drop --reason 'not real' > /dev/null 2> "$TMP/d0.err"; then exit 1; fi
grep -Fq 'needs --test' "$TMP/d0.err"
if run dispose --engine codex --finding 1 --action drop --reason 'not real' --test 'echo checked; exit 4' > /dev/null 2> "$TMP/d1.err"; then exit 1; fi
grep -Fq 'the disposition test failed (exit 4)' "$TMP/d1.err"
grep -Fq '"accepted": false' "$RUN_DIR/dispositions.jsonl"
if run dispose --engine codex --finding 1 --action drop --reason 'slow' --test 'sleep 5' > /dev/null 2> "$TMP/d2.err" < /dev/null; then exit 1; fi
grep -Fq 'exit 124, timed out' "$TMP/d2.err"
run collect > "$TMP/f2.out" || true
grep -Fq 'FINDINGS: 1 as written, 1 open' "$TMP/f2.out"
run dispose --engine codex --finding 1 --action downgrade --to P2 --reason 'test shows the path is guarded' --test 'echo first; echo second' > "$TMP/d3.out"
grep -Fq 'DISPOSED: codex#1 downgrade to P2' "$TMP/d3.out"
python3 - "$RUN_DIR/dispositions.jsonl" <<'PY'
import json, sys
last = [json.loads(l) for l in open(sys.argv[1])][-1]
assert last["accepted"] and last["exit_code"] == 0 and "first" in last["output_tail"] and "second" in last["output_tail"], last
assert "timeout" in last["test"], last
PY
run collect > "$TMP/f3.out"
grep -Fq 'FINDINGS: 1 as written, 0 open' "$TMP/f3.out"
test -f "$(<"$RUN_DIR/archive-path")/dispositions.jsonl"

# 5. O7: the next round's prior findings are the runner's record, every finding
#    as written, overriding a file the orchestrator passes.
edit third.txt fixed
printf '{"findings":[]}\n' > "$TMP/empty.json"
prep --identity stand --prior-findings "$TMP/empty.json" > "$TMP/next.out"
grep -Fq 'PRIOR-FINDINGS: the runner' "$TMP/next.out"
grep -Fq 'third.txt:1' "$RUN_DIR/scope/prior-findings.snapshot"
grep -Fq 'disposed: downgrade to P2' "$RUN_DIR/scope/prior-findings.snapshot"
grep -Fq 'Only a settled prior-round finding (status disposed, or marked accepted or known) stays out.' "$RUN_DIR/prompts/codex-cli.md"

# 6. A disposition test runs inside the slot wrapper and is bounded by the run's timeout.
mkdir -p "$TMP/slot"; printf '#!/usr/bin/env bash\n[[ "$1" == run ]] && shift; IN_SLOT=1 "$@"\n' > "$TMP/slot/box-test-slot.sh"; chmod +x "$TMP/slot/box-test-slot.sh"
printf 'example-org/example-dashboard\tbash %s run\tbash run-once.sh\n' "$TMP/slot/box-test-slot.sh" > "$TMP/slot.tsv"
result "$RUN_DIR" claude APPROVE; result "$RUN_DIR" codex BLOCK third.txt:2; run collect > /dev/null || true
GAUNTLET_ENFORCE_LIST="$TMP/slot.tsv" run dispose --engine codex --finding 1 --action drop --reason r --test 'test "$IN_SLOT" = 1 && echo a; test "$IN_SLOT" = 1 && echo b' > "$TMP/slotd.out"
grep -Fxq 'waiting for a box test slot' "$TMP/slotd.out"
python3 - "$RUN_DIR/dispositions.jsonl" <<'PY'
import json, sys
last = [json.loads(l) for l in open(sys.argv[1])][-1]
assert last["accepted"] and last["output_tail"].split() == ["a", "b"], last
PY

# 6b. A disposition test that moves HEAD is refused and records nothing accepted.
lines_before="$(wc -l < "$RUN_DIR/dispositions.jsonl")"
if run dispose --engine codex --finding 1 --action drop --reason r --test 'git checkout -q HEAD~1' > /dev/null 2> "$TMP/moved.err"; then echo 'dispose accepted a test that moved HEAD' >&2; exit 1; fi
grep -Fq 'the disposition test moved HEAD' "$TMP/moved.err"
git -C "$R" checkout -q feature
test "$(wc -l < "$RUN_DIR/dispositions.jsonl")" -eq "$lines_before"
# So is one that leaves the worktree dirty without moving HEAD.
if run dispose --engine codex --finding 1 --action drop --reason r --test 'echo x >> app.txt' > /dev/null 2> "$TMP/dirty.err"; then echo 'dispose accepted a test that left the worktree dirty' >&2; exit 1; fi
grep -Fq 'the disposition test left the review worktree dirty' "$TMP/dirty.err"
git -C "$R" checkout -q -- app.txt
test "$(wc -l < "$RUN_DIR/dispositions.jsonl")" -eq "$lines_before"

# 6c. O5 with a non-ASCII file name (Git quotes it in diff headers): the merge
#     fix is still that one file, not a refusal over the whole diff.
new_repo uni https://github.com/example-org/example-dashboard.git
edit café.txt one; edit other.txt two
converge uni
bring_main_in u
edit café.txt merge-fix
prep --identity uni > "$TMP/uni.out"
grep -Fxq '  café.txt' "$TMP/uni.out"
grep -Fxq 'other.txt' "$RUN_DIR/scope/excludes"
refute grep -Fq 'other.txt' "$RUN_DIR/scope/diff.patch"

# 6d. O7: a retried round (its first leg already recorded the round) still gets
#     the round before it as prior findings, not the file passed.
new_repo retry https://github.com/example-org/example-dashboard.git
edit app.txt one
prep --identity retry --pre-review --builder deepseek --engines grok > /dev/null; result "$RUN_DIR" grok APPROVE
prep --identity retry --run-once > /dev/null
result "$RUN_DIR" claude APPROVE; result "$RUN_DIR" codex BLOCK app.txt:9; run collect > /dev/null
edit app.txt two
prep --identity retry > /dev/null; result "$RUN_DIR" claude APPROVE
prep --identity retry --prior-findings "$TMP/empty.json" > "$TMP/retry.out"
grep -Fq 'ROUND: 2' "$TMP/retry.out"
grep -Fq 'PRIOR-FINDINGS: the runner' "$TMP/retry.out"
grep -Fq 'app.txt:9' "$RUN_DIR/scope/prior-findings.snapshot"

# 6e. A verdict line that fails to write is reported and written by the next collect.
export GAUNTLET_ENFORCE_LIST=/dev/null
new_repo rec https://github.com/example/rec.git
edit app.txt one
prep --identity rec > /dev/null; result "$RUN_DIR" claude APPROVE; result "$RUN_DIR" codex APPROVE
chmod 400 "$TMP/rounds.jsonl"
run collect > "$TMP/rec1.out"
chmod 600 "$TMP/rounds.jsonl"
grep -Fq 'VERDICT-RECORD: WRITE FAILED' "$TMP/rec1.out"
verdicts() { python3 -c 'import json,sys; print(sum(1 for l in open(sys.argv[1]) if (e:=json.loads(l)).get("runner")=="gauntlet-verdict" and e.get("identity")==sys.argv[2]))' "$TMP/rounds.jsonl" "$1"; }
test "$(verdicts id:rec)" -eq 0
run collect > "$TMP/rec2.out"
refute grep -Fq 'VERDICT-RECORD' "$TMP/rec2.out"
test "$(verdicts id:rec)" -eq 1
run collect > /dev/null
test "$(verdicts id:rec)" -eq 1
export GAUNTLET_ENFORCE_LIST="$TMP/on.tsv"

# 6f. O5, enforced: main brings in the same change the PR made to app.txt, so
#     app.txt leaves the PR's own diff. With nothing else changed the whole
#     diff is reviewed (never an empty scope); with a real merge fix too, the
#     scope narrows to it.
new_repo gone https://github.com/example-org/example-dashboard.git
edit app.txt one; edit other.txt two; edit third.txt three
converge gone
git -C "$R" checkout -q main; edit app.txt one; git -C "$R" checkout -q feature; git -C "$R" merge -q --no-edit main
prep --identity gone > "$TMP/gone.out"
grep -Fxq '  gone: app.txt' "$TMP/gone.out"
grep -Fq 'the whole diff is reviewed' "$TMP/gone.out"
test ! -s "$RUN_DIR/scope/excludes"
grep -Fq 'other.txt' "$RUN_DIR/scope/diff.patch"; grep -Fq 'third.txt' "$RUN_DIR/scope/diff.patch"
edit other.txt merge-fix
prep --identity gone > "$TMP/gone2.out"
grep -Fxq '  other.txt' "$TMP/gone2.out"
grep -Fxq 'third.txt' "$RUN_DIR/scope/excludes"
refute grep -Fq 'app.txt' "$RUN_DIR/scope/excludes"
refute grep -Fq 'third.txt' "$RUN_DIR/scope/diff.patch"

# 6g. O5 excludes are literal paths: an unchanged [x].txt never hides the
#     changed x.txt (as a glob it would match it).
new_repo glob https://github.com/example-org/example-dashboard.git
edit '[x].txt' one; edit x.txt two
converge glob
bring_main_in g
edit x.txt merge-fix
prep --identity glob > "$TMP/glob.out"
grep -Fxq '  x.txt' "$TMP/glob.out"
grep -Fxq '[x].txt' "$RUN_DIR/scope/excludes"
grep -Fq 'b/x.txt' "$RUN_DIR/scope/diff.patch"
refute grep -Fq '[x].txt' "$RUN_DIR/scope/diff.patch"

# 6h. O7: a round whose other leg failed still hands its valid leg's findings
#     to the next round, as written and open.
new_repo partial https://github.com/example-org/example-dashboard.git
edit app.txt one
prep --identity partial --pre-review --builder deepseek --engines grok > /dev/null; result "$RUN_DIR" grok APPROVE
prep --identity partial --run-once > /dev/null
result "$RUN_DIR" codex BLOCK app.txt:5
printf 'not a result\n' > "$TMP/bad.txt"
GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" ingest --engine claude --text "$TMP/bad.txt" > /dev/null 2>&1 || true
if run collect > "$TMP/partial.out"; then echo 'a round with a failed leg collected as complete' >&2; exit 1; fi
grep -Fq 'GAUNTLET: FAILED' "$TMP/partial.out"
edit app.txt two
prep --identity partial --prior-findings "$TMP/empty.json" > "$TMP/partial2.out"
grep -Fq 'PRIOR-FINDINGS: the runner' "$TMP/partial2.out"
grep -Fq 'app.txt:5' "$RUN_DIR/scope/prior-findings.snapshot"
grep -Fq '"status": "open"' "$RUN_DIR/scope/prior-findings.snapshot"

# 6i. O5, enforced: an approval covers only what its round reviewed. A round
#     prepared with --exclude b.txt approves a.txt alone; once main is brought
#     in, a full-scope request must still review b.txt (no standing approval),
#     and a merge fix to a.txt must never exclude the never-reviewed b.txt.
new_repo partscope https://github.com/example-org/example-dashboard.git
edit a.txt one; edit b.txt two
prep --identity partscope --pre-review --builder deepseek --engines grok > /dev/null; result "$RUN_DIR" grok APPROVE
prep --identity partscope --run-once --exclude b.txt > /dev/null
refute grep -Fq 'b.txt' "$RUN_DIR/scope/diff.patch"
result "$RUN_DIR" claude APPROVE; result "$RUN_DIR" codex APPROVE; run collect > /dev/null
bring_main_in p
prep --identity partscope > "$TMP/part.out" 2> "$TMP/part.err" || true
refute grep -Fq 'APPROVAL STANDS' "$TMP/part.out"
grep -Fq 'b/b.txt' "$RUN_DIR/scope/diff.patch"
refute grep -Fxq 'b.txt' "$RUN_DIR/scope/excludes"
grep -Fxq '  b.txt' "$TMP/part.out"
# a.txt was reviewed and is unchanged, so it keeps its standing and is the exclude.
grep -Fxq 'a.txt' "$RUN_DIR/scope/excludes"
# The next approval, of b.txt alone, covers b.txt and inherits a.txt's standing.
result "$RUN_DIR" claude APPROVE; result "$RUN_DIR" codex APPROVE; run collect > /dev/null
bring_main_in p2
if prep --identity partscope > "$TMP/part2.out" 2> /dev/null; then echo 'O5 prepared a round over an approval that now covers the whole diff' >&2; exit 1; fi
grep -Fq "APPROVAL STANDS @ $(git -C "$R" rev-parse HEAD)" "$TMP/part2.out"
# A merge fix to the reviewed a.txt never excludes the unreviewed b.txt.
new_repo partfix https://github.com/example-org/example-dashboard.git
edit a.txt one; edit b.txt two
prep --identity partfix --pre-review --builder deepseek --engines grok > /dev/null; result "$RUN_DIR" grok APPROVE
prep --identity partfix --run-once --exclude b.txt > /dev/null
result "$RUN_DIR" claude APPROVE; result "$RUN_DIR" codex APPROVE; run collect > /dev/null
bring_main_in f
edit a.txt merge-fix
prep --identity partfix > "$TMP/partfix.out" 2> /dev/null || true
refute grep -Fxq 'b.txt' "$RUN_DIR/scope/excludes"
grep -Fq 'b/b.txt' "$RUN_DIR/scope/diff.patch"
grep -Fq 'b/a.txt' "$RUN_DIR/scope/diff.patch"

# 7. Older readers of the round record skip the verdict lines quietly.
python3 - "$TMP/rounds.jsonl" <<'PY'
import json, sys
for raw in open(sys.argv[1]):
    e = json.loads(raw)
    assert all(isinstance(e.get(k), str) for k in ("runner", "repo", "identity", "digest")), e
    assert isinstance(e.get("round"), int) and e["round"] >= 1, e
PY
echo 'approvals.test.sh: OK'
