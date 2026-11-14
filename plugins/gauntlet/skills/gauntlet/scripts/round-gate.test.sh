#!/usr/bin/env bash
# Round-1 gate tests (retro rulings O6 and O19; six changes).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/gauntlet.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GAUNTLET_ROUND_RECORD="$TMP/rounds.jsonl" GAUNTLET_ARCHIVE="$TMP/archive"
refute() { if "$@"; then echo "expected to fail: $*" >&2; exit 1; fi; }
n=0
fresh() { n=$((n + 1)); RUN_DIR="$TMP/run-$n"; }
prep() { fresh; GAUNTLET_REPO="$R" GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" prepare --authorize-provider --base main --profile fast "$@"; }

new_repo() {
  R="$TMP/$1"; git init -q -b main "$R"
  git -C "$R" config user.name test; git -C "$R" config user.email test@example.invalid
  printf 'base\n' > "$R/app.txt"; git -C "$R" add . && git -C "$R" commit -qm base
  [[ -z "${2:-}" ]] || git -C "$R" remote add origin "$2"
  git -C "$R" checkout -qb feature
}
lines() { mkdir -p "$(dirname "$R/$1")"; python3 -c 'import sys; print("\n".join(f"line {i}" for i in range(int(sys.argv[1]))))' "$2" > "$R/$1"; git -C "$R" add "$1"; git -C "$R" commit -qm "add $1"; }

# Ingest a valid native result for the run's only (or named) engine.
approve() {
  local run="$1" engine="$2" model sha digest
  model="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["model"])' "$run/rows.json" "$engine")"
  sha="$(sed -n 's/^Scope SHA: //p' "$run/prompts/$engine-native.md")"; digest="$(sed -n 's/^Scope digest: //p' "$run/prompts/$engine-native.md")"
  printf '{"engine":"%s","model":"%s","transport":"%s-native","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$engine" "$model" "$engine" "$sha" "$digest" > "$TMP/result.txt"
  GAUNTLET_DIR="$run" bash "$RUNNER" ingest --engine "$engine" --text "$TMP/result.txt"
}

# 1. A repo off the list keeps today's behaviour: round 1 with no pre-review and
#    no run-once prepares, with warnings.
new_repo plain https://github.com/example/plain.git
lines src.txt 700
prep --identity plain > "$TMP/plain.out" 2> "$TMP/plain.err"
grep -Fq 'GAUNTLET_DIR=' "$TMP/plain.out"
grep -Fq 'SIZE NOTE: over 600 changed non-test lines' "$TMP/plain.out"
refute grep -Fq 'round 1 is limited' "$TMP/plain.err"
grep -Fq 'WARNING (not enforced for example/plain): no pre-review of id:plain' "$TMP/plain.err"
# 1b. A failing line counter is reported as not measured, never as a size note.
FAIL_GIT="$TMP/fail-git"; mkdir -p "$FAIL_GIT"
printf '#!/usr/bin/env bash\n[[ " $* " != *" --numstat -z "* ]] || exit 3\nexec %s "$@"\n' "$(command -v git)" > "$FAIL_GIT/git"
chmod +x "$FAIL_GIT/git"
new_repo countfail https://github.com/example/countfail.git
lines src.txt 700
PATH="$FAIL_GIT:$PATH" prep --identity countfail > "$TMP/countfail.out" 2> "$TMP/countfail.err"
grep -Fq 'ROUND-1 SIZE: not measured (the line counter failed)' "$TMP/countfail.out"
refute grep -Fq 'SIZE NOTE' "$TMP/countfail.out"
grep -Fq 'GAUNTLET_DIR=' "$TMP/countfail.out"

# 2. A list whose every line is commented out enforces nothing, and neither
#    crashes nor fails closed.
printf '# all off\n#example-org/example-dashboard\t-\ttrue\n\n' > "$TMP/off.tsv"
new_repo offlist git@github.com:example-org/example-dashboard.git
lines src.txt 700
GAUNTLET_ENFORCE_LIST="$TMP/off.tsv" prep --identity offlist > "$TMP/off.out" 2> "$TMP/off.err"
grep -Fq 'GAUNTLET_DIR=' "$TMP/off.out"
grep -Fq 'WARNING (not enforced for example-org/example-dashboard)' "$TMP/off.err"
refute grep -Fq 'REFUSED' "$TMP/off.err"
# The shipped list has no live lines: a repo is enforced only once its owner adds one.
test -z "$(grep -Ev '^(#|$)' "$SCRIPT_DIR/../enforce.tsv")"

# Enforced repo from here on.
printf '#example-org/example-infra\t-\ttrue\nexample-org/example-dashboard\t-\tbash run-once.sh\n' > "$TMP/on.tsv"
export GAUNTLET_ENFORCE_LIST="$TMP/on.tsv"

# 2b. lines git shows were moved unchanged do not count toward the
#     round-1 size; copied, edited and re-indented lines do. One case per
#     acceptance example; every
#     case runs and the failures are listed together.
SIZE_FAILS=()
mv_repo() { new_repo "mv-$1" https://github.com/example-org/example-dashboard.git; }
# block NAME N [INDENT]: N distinct long lines, with a lone } every 10th line.
block() { python3 -c 'import sys; p, n, ind = sys.argv[1], int(sys.argv[2]), sys.argv[3]; print("\n".join(f"{ind}}}" if i % 10 == 9 else f"{ind}const {p}_{i} = compute({i}, \"{p} payload\");" for i in range(n)))' "$1" "$2" "${3:-}"; }
on_main() { git -C "$R" add -A; git -C "$R" commit -qm base-files; git -C "$R" checkout -q main; git -C "$R" merge -q --ff-only feature; git -C "$R" checkout -q feature; }
change() { git -C "$R" add -A; git -C "$R" commit -qm change; }
mkf() { mkdir -p "$(dirname "$R/$1")"; cat > "$R/$1"; }
# size_case NAME 'ROUND-1 SIZE line' noted|passes [per-file line regex ...]
size_case() {
  local name="$1" want="$2" verdict="$3" out="$TMP/size-$1.out" err="$TMP/size-$1.err" re; shift 3
  prep --identity "size-$name" > "$out" 2> "$err" || true
  grep -Fqx "$want" "$out" || SIZE_FAILS+=("$name: wanted '$want'; got '$(grep '^ROUND-1 SIZE' "$out" || true)'")
  if [[ "$verdict" == noted ]]; then grep -Fq 'SIZE NOTE: over 600' "$out" || SIZE_FAILS+=("$name: no size note")
  elif grep -Fq 'SIZE NOTE' "$out"; then SIZE_FAILS+=("$name: size note under the threshold"); fi
  if grep -Fq 'round 1 is limited' "$err"; then SIZE_FAILS+=("$name: refused for size"); fi
  for re in "$@"; do grep -Eq "$re" "$out" || SIZE_FAILS+=("$name: no line matching $re"); done
}
ON='from --base (on main) (size note above 600'
# 1. 700 lines moved unchanged from a.ts to b.ts plus 10 new lines count 10.
mv_repo one; { block x 700; block k 5; } | mkf a.ts; block y 5 | mkf b.ts; on_main
block k 5 | mkf a.ts; { block y 5; block x 700; block new 10; } | mkf b.ts; change
size_case one "ROUND-1 SIZE: 10 changed non-test lines $ON; 1400 lines moved unchanged not counted)" passes
ONE_R="$R"
# 2. The same move with one character changed on one line counts that line twice plus the 10.
mv_repo edit; { block x 700; block k 5; } | mkf a.ts; block y 5 | mkf b.ts; on_main
block k 5 | mkf a.ts; { block y 5; block x 700 | sed '351s/compute(350/compute(351/'; block new 10; } | mkf b.ts; change
size_case edit "ROUND-1 SIZE: 12 changed non-test lines $ON; 1398 lines moved unchanged not counted)" passes
# 3. Two 400-line functions reordered inside one file count 0 (no line shared
#    between them, so git's diff is the two blocks; lone shared } lines would
#    leave git a scattered diff with short unmovable pieces).
mv_repo reorder; { block f 445 | grep -vx '}' | sed -n 1,400p; block g 445 | grep -vx '}' | sed -n 1,400p; } | mkf c.ts; on_main
{ block g 445 | grep -vx '}' | sed -n 1,400p; block f 445 | grep -vx '}' | sed -n 1,400p; } | mkf c.ts; change
size_case reorder "ROUND-1 SIZE: 0 changed non-test lines $ON; 800 lines moved unchanged not counted)" passes
# 4. A block removed once and added twice: the second copy counts in full.
mv_repo twice; { block x 700; block k 5; } | mkf a.ts; on_main
block k 5 | mkf a.ts; block x 700 | mkf b.ts; block x 700 | mkf c.ts; change
size_case twice "ROUND-1 SIZE: 700 changed non-test lines $ON; 1400 lines moved unchanged not counted)" noted \
  '^ +700 +0 moved  c\.ts$' '^ +0 +700 moved  a\.ts$' '^ +0 +700 moved  b\.ts$'
# 5. When the coloured diff fails or this machine's git fails the move check,
#    the count is the raw count with the reason, and over 600 gets the size note.
FAKE_GIT="$TMP/fake-git"; mkdir -p "$FAKE_GIT"
cat > "$FAKE_GIT/git" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *" --color-moved=blocks "* ]]; then
  case "\${FAKE_MOVED:-}" in
    fail) exit 3 ;;
    probe) [[ " \$* " != *" --no-index "* ]] || exit 1 ;;
  esac
fi
exec $(command -v git) "\$@"
EOF
chmod +x "$FAKE_GIT/git"
R="$ONE_R"
PATH="$FAKE_GIT:$PATH" FAKE_MOVED=fail size_case failed "ROUND-1 SIZE: 1410 changed non-test lines $ON; moved-line discount not applied: coloured diff failed)" noted
PATH="$FAKE_GIT:$PATH" FAKE_MOVED=probe size_case probe "ROUND-1 SIZE: 1410 changed non-test lines $ON; moved-line discount not applied: git move check failed on this machine)" noted
# 6a. diff.algorithm=histogram in the repo's config changes neither count
#     (on this input histogram and myers disagree).
mv_repo histogram; printf '%s\n' a b '}' '}' b c b b '}' | mkf h.ts; on_main
printf '%s\n' a '}' a b c a | mkf h.ts; change
hist="$(git -C "$R" diff --numstat --diff-algorithm=histogram main HEAD | awk '{print $1 + $2}')"
[[ "$hist" != 7 ]] || SIZE_FAILS+=("histogram: the input no longer separates histogram from myers")
git -C "$R" config diff.algorithm histogram
size_case histogram "ROUND-1 SIZE: 7 changed non-test lines $ON)" passes
[[ "$(python3 "$SCRIPT_DIR/lib/nontest_lines.py" "$R" main HEAD)" == 7 ]] || SIZE_FAILS+=("histogram: the coverage count followed diff.algorithm")
# 6. Moves between a test and a counted file count in full where they land or
#    leave; shared lines such as } earn no discount.
mv_repo cross; block t 700 | mkf tests/helpers.ts; { block s 700; block k 5; } | mkf src/a.ts; on_main
git -C "$R" rm -q tests/helpers.ts; block t 700 | mkf src/helpers.ts; block k 5 | mkf src/a.ts; block s 700 | mkf src/__tests__/a.test.ts; change
size_case cross "ROUND-1 SIZE: 1400 changed non-test lines $ON)" noted
# 6b. Each of those moves alone counts 700.
mv_repo intosrc; block t 700 | mkf tests/helpers.ts; on_main
git -C "$R" rm -q tests/helpers.ts; block t 700 | mkf src/helpers.ts; change
size_case intosrc "ROUND-1 SIZE: 700 changed non-test lines $ON)" noted
mv_repo intotest; { block s 700; block k 5; } | mkf src/a.ts; on_main
block k 5 | mkf src/a.ts; block s 700 | mkf src/__tests__/a.test.ts; change
size_case intotest "ROUND-1 SIZE: 700 changed non-test lines $ON)" noted
# 7. 601 new lines and none removed: today's report line.
mv_repo added; block n 601 | mkf new.ts; change
size_case added "ROUND-1 SIZE: 601 changed non-test lines $ON)" noted '^ +601 +0 moved  new\.ts$'
# 8. A block copied to a new file without removing it counts 700.
mv_repo copy; block x 700 | mkf a.ts; on_main
block x 700 | mkf b.ts; change
size_case copy "ROUND-1 SIZE: 700 changed non-test lines $ON)" noted
# 9. A moved block re-indented by one level counts in full, also with
#    diff.colorMovedWS=allow-indentation-change in the repo's config.
mv_repo indent; { block x 700; block k 5; } | mkf a.py; on_main
block k 5 | mkf a.py; block x 700 '    ' | mkf b.py; change
size_case indent "ROUND-1 SIZE: 1400 changed non-test lines $ON)" noted
git -C "$R" config diff.colorMovedWS allow-indentation-change
size_case indentws "ROUND-1 SIZE: 1400 changed non-test lines $ON)" noted
# 10. Moved blocks below git's threshold (a lone }, a one-word line) count.
mv_repo short; { block k 3; echo '}'; block l 3; echo end; block m 3; } | mkf a.ts; on_main
{ block k 3; block l 3; block m 3; } | mkf a.ts; { echo '}'; echo end; block n 598; } | mkf b.ts; change
size_case short "ROUND-1 SIZE: 602 changed non-test lines $ON)" noted
# 11. The pre-review coverage check still reads the raw count.
[[ "$(python3 "$SCRIPT_DIR/lib/nontest_lines.py" "$ONE_R" main feature)" == 1410 ]] || SIZE_FAILS+=("coverage: one is not 1410 raw")
if (( ${#SIZE_FAILS[@]} )); then printf 'round-1 size case failed: %s\n' "${SIZE_FAILS[@]}" >&2; exit 1; fi
new_repo solo https://github.com/example-org/example-dashboard.git
printf 'echo tests-ran; exit "${RUN_ONCE_EXIT:-0}"\n' > "$R/run-once.sh"; git -C "$R" add run-once.sh; git -C "$R" commit -qm runner
git -C "$R" checkout -q main; git -C "$R" merge -q --ff-only feature; git -C "$R" checkout -q feature

# 3. O6: 601 non-test lines get a size note with per-file counts, never a refusal (12 Nov 2026); test files,
#    snapshots, lockfiles and generated files do not count, nor fixtures under
#    __fixtures__/ (a common convention).
lines src.txt 601
lines src.test.ts 900; lines yarn.lock 900; lines __snapshots__/a.snap 50; lines dist/bundle.js 50
lines src/__fixtures__/feed.json 626
prep --identity size > "$TMP/size.out" 2> "$TMP/size.err" || true
grep -Fq 'ROUND-1 SIZE: 601 changed non-test lines from --base (on main) (size note above 600)' "$TMP/size.out"
grep -Eq '^ +601 +0 moved  src.txt$' "$TMP/size.out"
grep -Fq 'SIZE NOTE: over 600' "$TMP/size.out"
refute grep -Fq 'round 1 is limited' "$TMP/size.err"
git -C "$R" rm -q src.txt; git -C "$R" commit -qm shrink; lines src.txt 600
prep --identity size > "$TMP/size2.out" 2> "$TMP/size2.err" || true
grep -Fq 'ROUND-1 SIZE: 600 changed non-test lines' "$TMP/size2.out"
refute grep -Fq 'round 1 is limited' "$TMP/size2.err"
refute grep -Fq 'SIZE NOTE' "$TMP/size2.out"

# O6's base, one test per case. The first case (--base on the default branch)
# is the one above. The others use a stack repo.
SOLO_R="$R"
new_repo stack https://github.com/example-org/example-dashboard.git
reviewed() {  # record HEAD of $1 as a reviewed gauntlet head
  python3 -c 'import json,sys; print(json.dumps({"runner":"gauntlet","repo":"x","identity":"id:"+sys.argv[2],"digest":sys.argv[1],"round":1,"head":sys.argv[1]},separators=(",",":")))' "$(git -C "$R" rev-parse "$1")" "$1" >> "$GAUNTLET_ROUND_RECORD"
}
stack_prep() { fresh; GAUNTLET_REPO="$R" GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" prepare --authorize-provider --profile fast "$@"; }
# Base neither on main nor reviewed: the unreviewed parent counts (whole stack).
git -C "$R" checkout -q -b stack-parent main; lines parent.txt 700
git -C "$R" checkout -q -b stack-child; lines child.txt 10
stack_prep --base stack-parent --identity stacked > "$TMP/stack.out" 2> "$TMP/stack.err" || true
grep -Fq 'ROUND-1 SIZE: 710 changed non-test lines from the merge-base with main (--base is neither on main nor a reviewed head)' "$TMP/stack.out"
grep -Fq 'SIZE NOTE: over 600' "$TMP/stack.out"
refute grep -Fq 'round 1 is limited' "$TMP/stack.err"
# Base a recorded reviewed head: a stack on a converged parent passes at its own size.
reviewed stack-parent
# A long record (the parent's line early, thousands after) still finds it.
python3 -c 'import json; [print(json.dumps({"runner":"gauntlet","repo":"y","identity":f"id:fill{i}","digest":f"{i:040x}","round":1,"head":f"{i:040x}"},separators=(",",":"))) for i in range(5000)]' >> "$GAUNTLET_ROUND_RECORD"
stack_prep --base stack-parent --identity stacked > "$TMP/stack2.out" 2> "$TMP/stack2.err" || true
grep -Fq 'ROUND-1 SIZE: 10 changed non-test lines from --base (a reviewed head)' "$TMP/stack2.out"
refute grep -Fq 'round 1 is limited' "$TMP/stack2.err"
# Base the head of a parent squash-merged since: still its own size.
git -C "$R" checkout -q -b sq-parent main; lines sq-parent.txt 700; reviewed sq-parent
git -C "$R" checkout -q -b sq-child; lines sq-child.txt 12
git -C "$R" checkout -q main; git -C "$R" merge -q --squash sq-parent; git -C "$R" commit -qm 'squash sq-parent'; git -C "$R" checkout -q sq-child
stack_prep --base sq-parent --identity squashed > "$TMP/sq.out" 2> "$TMP/sq.err" || true
grep -Fq 'ROUND-1 SIZE: 12 changed non-test lines from --base (a reviewed head)' "$TMP/sq.out"
refute grep -Fq 'round 1 is limited' "$TMP/sq.err"
R="$SOLO_R"

# 4. O19(a): no pre-review refuses round 1, naming the same-machine rule.
if prep --identity solo1 > /dev/null 2> "$TMP/nopre.err"; then echo 'O19 did not refuse a missing pre-review' >&2; exit 1; fi
grep -Fq 'no pre-review of id:solo1' "$TMP/nopre.err"
grep -Fq 'pre-review, run-once and rounds run on the same machine' "$TMP/nopre.err"
# --pre-reviewed-by none is no longer an escape.
if prep --identity solo1 --pre-reviewed-by none > /dev/null 2>&1; then echo '--pre-reviewed-by none still escapes' >&2; exit 1; fi

# 5. The pre-review must run on an engine other than the builder's family.
if prep --identity solo1 --pre-review --builder gpt --engines codex > /dev/null 2> "$TMP/same.err"; then exit 1; fi
grep -Fq 'other than the builder' "$TMP/same.err"
# The builder's family is read by prefix from a model name.
refute prep --identity solo1 --pre-review --builder gpt-6-luna --engines codex > /dev/null 2>&1
refute prep --identity solo1 --pre-review --builder grok-4.7 --engines grok > /dev/null 2>&1
refute prep --identity solo1 --pre-review --engines grok > /dev/null 2>&1
refute prep --identity solo1 --pre-review --builder deepseek --engines grok,codex > /dev/null 2>&1
if prep --identity solo1 --pre-review --builder deepseek --engines grok --exclude app.txt > /dev/null 2> "$TMP/excl.err"; then exit 1; fi
grep -Fq 'a pre-review covers the whole change' "$TMP/excl.err"
if prep --identity solo1 --pre-review --builder deepseek --engines grok --run-once > /dev/null 2> "$TMP/preonce.err"; then exit 1; fi
grep -Fq 'belongs to the round-1 prepare' "$TMP/preonce.err"

# 6. A pre-review whose leg failed may be retried; a valid one is recorded once.
prep --identity solo1 --pre-review --builder deepseek --engines grok > "$TMP/pre1.out"
grep -Fq 'PRE-REVIEW: id:solo1 by grok (builder deepseek)' "$TMP/pre1.out"
grep -Fq 'Pre-review checklist.' "$RUN_DIR/prompts/grok-cli.md"
grep -Fq 'every check-then-write' "$RUN_DIR/prompts/grok-native.md"
printf 'not json\n' > "$TMP/bad.txt"
refute env GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" ingest --engine grok --text "$TMP/bad.txt" 2>/dev/null
refute grep -Fq 'gauntlet-pre-review' "$TMP/rounds.jsonl"
prep --identity solo1 --pre-review --builder deepseek --engines grok > /dev/null
approve "$RUN_DIR" grok
grep -Fq '"runner":"gauntlet-pre-review"' "$TMP/rounds.jsonl"
grep -Fq '"engine":"grok","builder":"deepseek"' "$TMP/rounds.jsonl"
if prep --identity solo1 --pre-review --builder deepseek --engines codex > /dev/null 2> "$TMP/second.err"; then exit 1; fi
grep -Fq 'already recorded' "$TMP/second.err"
# The pre-review is not a budget round.
python3 - "$TMP/rounds.jsonl" <<'PY'
import json, sys
assert not [e for e in map(json.loads, open(sys.argv[1])) if e["runner"] == "gauntlet" and e["identity"] == "id:solo1"]
PY

# The pre-review record is written under an flock: a lock file left behind by
# a dead holder does not block it; a live holder makes it wait, then fail with
# a reported failure that collect retries once the lock is free.
LOCK="$GAUNTLET_ROUND_RECORD.pre-review.lock"
: > "$LOCK"
prep --identity lock1 --pre-review --builder deepseek --engines grok > /dev/null; approve "$RUN_DIR" grok
grep -c '"runner":"gauntlet-pre-review".*"identity":"id:lock1"' "$TMP/rounds.jsonl" | grep -qx 1
python3 -c 'import fcntl,os,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[2],"w").close()
while not os.path.exists(sys.argv[3]): time.sleep(0.05)' "$LOCK" "$TMP/held" "$TMP/release" &
HOLDER=$!; until [[ -e "$TMP/held" ]]; do sleep 0.1; done
prep --identity lock2 --pre-review --builder deepseek --engines grok > /dev/null; GAUNTLET_PRE_REVIEW_LOCK_SECONDS=1 approve "$RUN_DIR" grok
refute grep -Fq '"identity":"id:lock2"' "$TMP/rounds.jsonl"
GAUNTLET_PRE_REVIEW_LOCK_SECONDS=1 GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" collect > "$TMP/lock.out" 2>&1 || true
grep -Fq 'lock is held by a live process' "$TMP/lock.out"
: > "$TMP/release"; wait "$HOLDER"
GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" collect > /dev/null 2>&1 || true
grep -c '"identity":"id:lock2"' "$TMP/rounds.jsonl" | grep -qx 1

# 7. O19(b): with a pre-review but no run-once, round 1 is refused; a failing
#    run-once is refused and recorded; a passing one lets round 1 prepare.
if prep --identity solo1 > /dev/null 2> "$TMP/noonce.err"; then exit 1; fi
grep -Fq 'no passing run-once is recorded for id:solo1' "$TMP/noonce.err"
if RUN_ONCE_EXIT=3 prep --identity solo1 --run-once > "$TMP/fail.out" 2> "$TMP/fail.err"; then exit 1; fi
grep -Fq 'RUN-ONCE: exit 3 after' "$TMP/fail.out"
grep -Fq 'the run-once command failed' "$TMP/fail.err"
grep -Fq '"runner":"gauntlet-run-once"' "$TMP/rounds.jsonl"
prep --identity solo1 --run-once > "$TMP/pass.out"
grep -Fq "RUN-ONCE: timeout --kill-after=10 1800 bash -c 'bash run-once.sh'" "$TMP/pass.out"
grep -Fq 'ROUND: 1 identity=id:solo1' "$TMP/pass.out"
record="$(sed -n 's/^RUN-ONCE: exit 0 after [0-9]*s; record //p' "$TMP/pass.out")"
python3 - "$record/run-once.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["command"] == "bash run-once.sh" and r["exit_code"] == 0 and isinstance(r["seconds"], int), r
assert "tests-ran" in r["output_tail"], r
PY
# A recorded pass at this head satisfies a plain prepare (a retry of round 1).
prep --identity solo1 > /dev/null
# --run-once at a head with a recorded pass reuses it rather than running again.
prep --identity solo1 --run-once > "$TMP/reuse.out"
grep -Fq 'already recorded at' "$TMP/reuse.out"
test "$(grep -c '"runner":"gauntlet-run-once".*"identity":"id:solo1".*"exit_code":0' "$TMP/rounds.jsonl")" -eq 1
ROUND_ONE="$RUN_DIR"
approve "$ROUND_ONE" claude
grep -Fq '"runner":"gauntlet","repo"' "$TMP/rounds.jsonl"

# 8. Later rounds are not size-checked or gated.
lines big.txt 900
prep --identity solo1 > "$TMP/r2.out" 2> "$TMP/r2.err"
grep -Fq 'ROUND: 2 identity=id:solo1' "$TMP/r2.out"
refute grep -Fq 'ROUND-1 SIZE' "$TMP/r2.out"

# A pre-review at an ancestor head still counts after a later commit; the
# run-once must be at the reviewed head.
git -C "$R" reset -q --hard HEAD~1
prep --identity anc --pre-review --builder claude --engines codex > /dev/null
approve "$RUN_DIR" codex
lines tests/more.txt 3
if prep --identity anc > /dev/null 2> "$TMP/anc.err"; then exit 1; fi
refute grep -Fq 'no pre-review' "$TMP/anc.err"
grep -Fq 'no passing run-once' "$TMP/anc.err"
prep --identity anc --run-once > /dev/null

# 8b. A rebase onto a moved main needs a fresh pre-review, which is allowed;
#     a pre-review from a later base does not cover an earlier one; two
#     concurrent pre-reviews record only one.
new_repo rebase https://github.com/example-org/example-dashboard.git
printf 'echo tests-ran\n' > "$R/run-once.sh"; git -C "$R" add run-once.sh; git -C "$R" commit -qm runner
git -C "$R" checkout -q main; git -C "$R" merge -q --ff-only feature; git -C "$R" checkout -q feature
lines a.txt 3; lines b.txt 3
prep --identity rb --pre-review --builder deepseek --engines grok > /dev/null; approve "$RUN_DIR" grok
git -C "$R" checkout -q main; lines main-moved.txt 2; git -C "$R" checkout -q feature; git -C "$R" rebase -q main
if prep --identity rb --run-once > /dev/null 2> "$TMP/rb.err"; then echo 'a pre-review of a pre-rebase head covered the rebased head' >&2; exit 1; fi
grep -Fq 'no pre-review of id:rb' "$TMP/rb.err"
prep --identity rb --pre-review --builder deepseek --engines grok > /dev/null; approve "$RUN_DIR" grok
prep --identity rb --run-once > "$TMP/rb.out"
grep -Fq 'ROUND: 1 identity=id:rb' "$TMP/rb.out"
prep --identity cov --pre-review --builder deepseek --engines grok --base HEAD~1 > /dev/null; approve "$RUN_DIR" grok
if prep --identity cov --run-once > /dev/null 2> "$TMP/cov.err"; then echo 'a smaller-scope pre-review covered the round' >&2; exit 1; fi
grep -Fq 'no pre-review of id:cov' "$TMP/cov.err"
# A pre-review of a small first commit does not cover a much larger round 1;
# a fresh pre-review at the new head is then allowed.
lines early.txt 20
prep --identity early --pre-review --builder deepseek --engines grok > /dev/null; approve "$RUN_DIR" grok
lines late.txt 300
if prep --identity early --run-once > /dev/null 2> "$TMP/early.err"; then echo 'a 20-line pre-review covered a 300-line round 1' >&2; exit 1; fi
grep -Fq 'no pre-review of id:early' "$TMP/early.err"
prep --identity early --pre-review --builder deepseek --engines grok > /dev/null; approve "$RUN_DIR" grok
prep --identity early --run-once > /dev/null
prep --identity dup --pre-review --builder deepseek --engines grok > /dev/null; DUP_A="$RUN_DIR"
prep --identity dup --pre-review --builder deepseek --engines grok > /dev/null; DUP_B="$RUN_DIR"
approve "$DUP_A" grok; approve "$DUP_B" grok
test "$(grep -c '"runner":"gauntlet-pre-review".*"identity":"id:dup"' "$TMP/rounds.jsonl")" -eq 1
test -f "$DUP_B/failures/pre-review-duplicate.txt"
GAUNTLET_DIR="$DUP_B" bash "$RUNNER" collect > "$TMP/dup.out" 2>&1 || true
grep -Fq 'PRE-REVIEW: NOT RECORDED' "$TMP/dup.out"

# 8c. A pre-review recorded while the repo was off the list counts only if it
#     was eligible: an engine of the builder's own family, or one with
#     --exclude, does not satisfy an enforced round 1.
GAUNTLET_ENFORCE_LIST=/dev/null prep --identity inel --pre-review --builder claude --engines claude > /dev/null 2>&1; approve "$RUN_DIR" claude
GAUNTLET_ENFORCE_LIST=/dev/null prep --identity inel2 --pre-review --builder deepseek --engines grok --exclude a.txt > /dev/null 2>&1; approve "$RUN_DIR" grok
grep -Fq '"identity":"id:inel","digest"' "$TMP/rounds.jsonl"
for id in inel inel2; do
  if prep --identity "$id" --run-once > /dev/null 2> "$TMP/inel.err"; then echo "an ineligible pre-review satisfied round 1 ($id)" >&2; exit 1; fi
  grep -Fq "no pre-review of id:$id" "$TMP/inel.err"
done

# 9. A slot wrapper missing on this machine refuses with the same-machine text;
#    a box slot wrapper prints the wait line.
new_repo box https://github.com/example-org/example-dashboard.git
lines src.txt 5
GAUNTLET_ENFORCE_LIST=/dev/null prep --identity box --pre-review --builder deepseek --engines grok > /dev/null 2>&1
printf 'example-org/example-dashboard\t/nonexistent/box-test-slot.sh run\ttrue\n' > "$TMP/missing.tsv"
GAUNTLET_ENFORCE_LIST="$TMP/missing.tsv" prep --identity box --pre-review --builder deepseek --engines grok > /dev/null
approve "$RUN_DIR" grok
if GAUNTLET_ENFORCE_LIST="$TMP/missing.tsv" prep --identity box --run-once > /dev/null 2> "$TMP/missing.err"; then exit 1; fi
grep -Fq 'is not on this machine' "$TMP/missing.err"
# A run-once that dirties the worktree is refused and never recorded as a pass.
printf 'example-org/example-dashboard\t-\techo dirt >> app.txt\n' > "$TMP/dirty.tsv"
if GAUNTLET_ENFORCE_LIST="$TMP/dirty.tsv" prep --identity box --run-once > /dev/null 2> "$TMP/dirty.err"; then exit 1; fi
grep -Fq 'left the review worktree dirty' "$TMP/dirty.err"
git -C "$R" checkout -q -- app.txt
printf 'example-org/example-dashboard\t-\ttrue\n' > "$TMP/plainonce.tsv"
if GAUNTLET_ENFORCE_LIST="$TMP/plainonce.tsv" prep --identity box > /dev/null 2> "$TMP/dirty2.err"; then echo 'a dirty run-once was reused as a pass' >&2; exit 1; fi
grep -Fq 'no passing run-once' "$TMP/dirty2.err"
# A command that ignores TERM is still bounded (killed after the grace period).
# The command never ends without SIGKILL; an outer watchdog proves the runner
# ends it (removing --kill-after makes the watchdog fire and this fail).
printf 'example-org/example-dashboard\t-\ttrap "" TERM; while :; do sleep 1; done\n' > "$TMP/term.tsv"
term_rc=0; GAUNTLET_ENFORCE_LIST="$TMP/term.tsv" timeout 60 bash -c 'source /dev/stdin' > "$TMP/term.out" 2> "$TMP/term.err" <<EOF2 || term_rc=$?
GAUNTLET_REPO="$R" GAUNTLET_DIR="$TMP/term-run" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity box --run-once --timeout-seconds 1
EOF2
[[ "$term_rc" -ne 124 && "$term_rc" -ne 0 ]] || { echo "TERM-ignoring run-once not bounded by the runner (rc $term_rc)" >&2; exit 1; }
grep -Fq 'run-once timed out after 1s' "$TMP/term.err"
tail -n 1 "$GAUNTLET_ROUND_RECORD" | grep -Fq '"exit_code":124'
# A run-once that commits (moves HEAD, worktree clean) is refused and its pass
# is not reused once HEAD is reset.
box_head="$(git -C "$R" rev-parse HEAD)"
printf 'example-org/example-dashboard\t-\tgit commit -q --allow-empty -m moved\n' > "$TMP/move.tsv"
if GAUNTLET_ENFORCE_LIST="$TMP/move.tsv" prep --identity box --run-once > /dev/null 2> "$TMP/move.err"; then exit 1; fi
grep -Fq 'moved HEAD' "$TMP/move.err"
git -C "$R" reset -q --hard "$box_head"
if GAUNTLET_ENFORCE_LIST="$TMP/plainonce.tsv" prep --identity box > /dev/null 2> "$TMP/move2.err"; then echo 'a HEAD-moving run-once was reused as a pass' >&2; exit 1; fi
grep -Fq 'no passing run-once' "$TMP/move2.err"
# The run-once archive is refused inside a worktree that does not ignore it.
printf 'example-org/example-dashboard\t-\ttrue\n' > "$TMP/plainonce.tsv"
if GAUNTLET_ARCHIVE="$R/arch" GAUNTLET_ENFORCE_LIST="$TMP/plainonce.tsv" prep --identity box --run-once > /dev/null 2> "$TMP/arch.err"; then exit 1; fi
grep -Fq 'lies inside a git worktree' "$TMP/arch.err"; rm -rf "$R/arch"
# The command is bounded; a run past the bound is refused as timed out.
printf 'example-org/example-dashboard\t-\tsleep 5\n' > "$TMP/sleep.tsv"
if GAUNTLET_ENFORCE_LIST="$TMP/sleep.tsv" prep --identity box --run-once --timeout-seconds 1 > "$TMP/sleep.out" 2> "$TMP/sleep.err"; then exit 1; fi
grep -Fq 'RUN-ONCE: timed out after 1s' "$TMP/sleep.out"
grep -Fq 'run-once timed out after 1s' "$TMP/sleep.err"
# The wrapper wraps the whole command: both parts of a compound command run in the slot.
mkdir -p "$TMP/slot"; printf '#!/usr/bin/env bash\n[[ "$1" == run ]] && shift; echo slot-ok; IN_SLOT=1 "$@"\n' > "$TMP/slot/box-test-slot.sh"; chmod +x "$TMP/slot/box-test-slot.sh"
printf 'example-org/example-dashboard\tbash %s run\techo first-$IN_SLOT; echo second-$IN_SLOT\n' "$TMP/slot/box-test-slot.sh" > "$TMP/slot.tsv"
GAUNTLET_ENFORCE_LIST="$TMP/slot.tsv" prep --identity box --run-once > "$TMP/slot.out"
grep -Fxq 'waiting for a box test slot' "$TMP/slot.out"
grep -Fq 'RUN-ONCE: exit 0' "$TMP/slot.out"
slot_record="$(sed -n 's/^RUN-ONCE: exit 0 after [0-9]*s; record //p' "$TMP/slot.out")"
grep -Fxq first-1 "$slot_record/output.log"; grep -Fxq second-1 "$slot_record/output.log"

# 9b. A `ci:` run-once dispatches the repo's CI at the reviewed head through
#     ci-run-once.sh, outside the slot, with at least an hour's bound, and
#     follows only the run its dispatch created. The fake gh applies each --jq
#     filter with jq; the fake sleep records its interval and returns at once.
FAKE="$TMP/fakegh"; mkdir -p "$FAKE"
cat > "$FAKE/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GH_LOG"
q=''; a=("$@"); for ((i = 0; i < ${#a[@]}; i++)); do [[ "${a[i]}" != --jq ]] || q="${a[i+1]}"; done
case "$1 $2" in
  "pr view") printf '%s' "$FAKE_GH_PR" | jq -r "$q"; exit "${FAKE_GH_PR_RC:-0}" ;;
  "workflow run") [[ -z "${FAKE_GH_RUN_ID:-}" ]] || echo "https://github.com/example-org/example-dashboard/actions/runs/$FAKE_GH_RUN_ID"
    exit "${FAKE_GH_DISPATCH_RC:-0}" ;;
  "run view") n=$(($(cat "$FAKE_GH_N" 2>/dev/null || echo 0) + 1)); echo "$n" > "$FAKE_GH_N"
    f="$FAKE_GH_RUNS.$n"; [[ -f "$f" ]] || f="$FAKE_GH_RUNS"
    run="$(jq -c --argjson id "$3" '.[] | select(.databaseId == $id)' < "$f")"
    [[ -n "$run" ]] || { echo "could not find any workflow run with ID $3" >&2; exit 1; }
    printf '%s' "$run" | jq -r "$q" ;;
  # The workflow's runs through the REST API: call k reads $FAKE_GH_LIST.k, else $FAKE_GH_LIST, else
  # none; FAIL fails the read. As GitHub does, head_sha keeps that commit's runs, newest first,
  # per_page (default 30) to a page, and only --paginate reads past the first page.
  "api "*) [[ " $* " == *" -X GET "* ]] || exit 9
    n=$(($(cat "$FAKE_GH_LN" 2>/dev/null || echo 0) + 1)); echo "$n" > "$FAKE_GH_LN"
    f="${FAKE_GH_LIST:-}.$n"; [[ -n "${FAKE_GH_LIST:-}" && -f "$f" ]] || f="${FAKE_GH_LIST:-}"
    c=''; per=30; all=false
    for ((i = 0; i < ${#a[@]}; i++)); do case "${a[i]}" in --paginate) all=true ;; -f) case "${a[i+1]}" in head_sha=*) c="${a[i+1]#*=}" ;; per_page=*) per="${a[i+1]#*=}" ;; esac ;; esac; done
    if [[ -z "$f" || ! -f "$f" ]]; then runs='[]'; elif [[ "$(cat "$f")" == FAIL ]]; then exit 1
    else runs="$(jq -c --arg c "$c" '[.[] | select($c == "" or .headSha == $c) | {id: .databaseId, head_sha: .headSha, status, conclusion: (.conclusion | if . == "" then null else . end)}] | sort_by(-.id)' < "$f")"; fi
    pages=$((($(jq length <<<"$runs") + per - 1) / per)); [[ "$all" == true && "$pages" -gt 0 ]] || pages=1
    for ((p = 0; p < pages; p++)); do jq -r --argjson p "$p" --argjson n "$per" "{workflow_runs: .[\$p * \$n:(\$p + 1) * \$n]} | $q" <<<"$runs"; done ;;
  *) exit 9 ;;
esac
GH
printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$*" >> "$FAKE_GH_LOG"\nexit "${FAKE_SLEEP_RC:-0}"\n' > "$FAKE/sleep"
chmod +x "$FAKE/gh" "$FAKE/sleep"
export FAKE_GH_LOG="$TMP/gh.log" FAKE_GH_N="$TMP/gh.n" FAKE_GH_RUNS="$TMP/runs.json" FAKE_GH_LN="$TMP/gh.ln" GAUNTLET_CI_DISPATCHES="$TMP/ci-dispatches.jsonl"
CI_RUN_ONCE="$SCRIPT_DIR/ci-run-once.sh"
new_repo ci https://github.com/example-org/example-dashboard.git
lines src.txt 5
H="$(git -C "$R" rev-parse HEAD)"
pr_json() { printf '{"headRefName":"feature","headRefOid":"%s","state":"%s"}' "$1" "${2:-OPEN}"; }
run_json() {  # id sha status conclusion createdAt
  printf '{"databaseId":%s,"headSha":"%s","status":"%s","conclusion":"%s","url":"https://example.invalid/runs/%s","createdAt":"%s","startedAt":"2099-01-01T00:00:00Z","updatedAt":"2099-01-01T00:09:30Z"}' "$1" "$2" "$3" "$4" "$1" "$5"
}
OLD="$(printf '%040d' 1)"
# Bounded, so a polling loop that never ends (the fake sleep returns at once) fails the case instead of hanging the suite.
ci_case() { rm -f "$FAKE_GH_N" "$FAKE_GH_LN"; : > "$FAKE_GH_LOG"; PATH="$FAKE:$PATH" timeout 60 bash "$CI_RUN_ONCE" example-org/example-dashboard "$H" "$@"; }
# ci_expect <exit code> <message> <ci_case args...>
ci_expect() {
  local want_rc="$1" want="$2" rc=0; shift 2
  ci_case "$@" > "$TMP/ci.out" 2>&1 || rc=$?
  [[ "$rc" -eq "$want_rc" ]] || { echo "ci-run-once $* gave exit $rc, not $want_rc: $(cat "$TMP/ci.out")" >&2; exit 1; }
  grep -Fq -- "$want" "$TMP/ci.out" || { echo "ci-run-once $*: no '$want' in: $(cat "$TMP/ci.out")" >&2; exit 1; }
}
# Refused before any dispatch.
ci_refused() { ci_expect 2 "$@"; refute grep -Fq 'workflow run' "$FAKE_GH_LOG"; }
export FAKE_GH_PR="$(pr_json "$H")" FAKE_GH_RUN_ID=11
# Passes on the dispatched run at the head, read every 600 seconds.
printf '[%s,%s]' "$(run_json 1 "$OLD" completed failure 2000-01-01T00:00:00Z)" "$(run_json 11 "$H" completed success 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS"
ci_expect 0 'CI RUN-ONCE: run 11 success in 9.5 min' pr:7 ci.yml boot=true
grep -Fq 'on feature at '"${H:0:12}"' as run 11' "$TMP/ci.out"
grep -Fxq 'workflow run ci.yml --repo example-org/example-dashboard --ref feature -f boot=true' "$FAKE_GH_LOG"
[[ "$(grep -c '^sleep' "$FAKE_GH_LOG")" -eq 1 && "$(grep -cx 'sleep 600' "$FAKE_GH_LOG")" -eq 1 ]]
# Waits through in-progress reads (an empty conclusion shifts no field), then reports the conclusion.
export FAKE_GH_RUN_ID=12
printf '[%s]' "$(run_json 12 "$H" in_progress '' 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS.1"
printf '[%s]' "$(run_json 12 "$H" completed failure 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS"
ci_expect 1 'run 12 failure' pr:7 ci.yml
grep -Fxq 'CI RUN-ONCE: run 12 in_progress' "$TMP/ci.out"
rm -f "$FAKE_GH_RUNS.1"
# With inputs asked for, a run it did not dispatch with those inputs never
# supplies the result (GitHub does not show a run's inputs): its run cancelled
# while an older and a newer dispatch at the same head succeeded fails.
export FAKE_GH_RUN_ID=13
printf '[%s,%s,%s]' "$(run_json 1 "$H" completed success 2000-01-01T00:00:00Z)" "$(run_json 13 "$H" completed cancelled 2099-01-01T00:00:00Z)" \
  "$(run_json 14 "$H" completed success 2099-01-01T00:01:00Z)" > "$FAKE_GH_RUNS"
cp "$FAKE_GH_RUNS" "$TMP/list.json"
FAKE_GH_LIST="$TMP/list.json" ci_expect 1 'run 13 was cancelled and no later run' pr:7 ci.yml boot=true
grep -Fq 'workflow run ci.yml' "$FAKE_GH_LOG"
refute grep -Fq 'run 14' "$TMP/ci.out"
refute grep -Fq 'run 1 ' "$TMP/ci.out"
# With no inputs, its run cancelled by a later dispatch at the same head
# follows that run: a pass passes. An older pass, and a later run at another
# commit, are never taken.
export FAKE_GH_RUN_ID=31
printf '[%s,%s,%s,%s]' "$(run_json 30 "$H" completed success 2099-01-01T00:00:00Z)" "$(run_json 31 "$H" completed cancelled 2099-01-01T00:00:00Z)" \
  "$(run_json 32 "$H" completed success 2099-01-01T00:01:00Z)" "$(run_json 33 "$OLD" completed success 2099-01-01T00:02:00Z)" > "$FAKE_GH_RUNS"
printf '[]' > "$TMP/list.json.1"; cp "$FAKE_GH_RUNS" "$TMP/list.json"
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'run 32 success' pr:7 ci.yml
grep -Fq 'run 31 was cancelled by a later run at the same head; following run 32' "$TMP/ci.out"
[[ "$(grep -c '^sleep' "$FAKE_GH_LOG")" -eq 1 ]]
# The same with no later run at the head (only the older pass and the other commit's): fails.
printf '[%s,%s,%s]' "$(run_json 30 "$H" completed success 2099-01-01T00:00:00Z)" "$(run_json 31 "$H" completed cancelled 2099-01-01T00:00:00Z)" \
  "$(run_json 33 "$OLD" completed success 2099-01-01T00:02:00Z)" > "$TMP/list.json"
FAKE_GH_LIST="$TMP/list.json" ci_expect 1 'run 31 was cancelled and no later run' pr:7 ci.yml
refute grep -Fq 'following run' "$TMP/ci.out"
# A failed listing after the cancel is retried at the next poll.
printf 'FAIL' > "$TMP/list.json.2"; printf '[%s,%s]' "$(run_json 31 "$H" completed cancelled 2099-01-01T00:00:00Z)" "$(run_json 32 "$H" completed success 2099-01-01T00:01:00Z)" > "$TMP/list.json"
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'run 32 success' pr:7 ci.yml
grep -Fq 'listing ci.yml runs on feature failed; trying again in 600s' "$TMP/ci.out"
rm -f "$TMP/list.json".*
# With inputs, a later run it dispatched itself with the same inputs (a second
# prepare) is followed. Run 42 is recorded by dispatching it first.
export FAKE_GH_RUN_ID=42
printf '[%s]' "$(run_json 42 "$H" completed success 2099-01-01T00:01:00Z)" > "$FAKE_GH_RUNS"
ci_expect 0 'run 42 success' pr:7 ci.yml boot=true
export FAKE_GH_RUN_ID=41
printf '[%s,%s]' "$(run_json 41 "$H" completed cancelled 2099-01-01T00:00:00Z)" "$(run_json 42 "$H" completed success 2099-01-01T00:01:00Z)" > "$FAKE_GH_RUNS"
printf '[]' > "$TMP/list.json.1"; cp "$FAKE_GH_RUNS" "$TMP/list.json"
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'following run 42' pr:7 ci.yml boot=true
# Its record is per input set: the same run does not count for other inputs.
FAKE_GH_LIST="$TMP/list.json" ci_expect 1 'run 41 was cancelled and no later run' pr:7 ci.yml boot=false
rm -f "$TMP/list.json".*
# Before dispatching: a run that counts and already passed at the head is
# reused, and nothing is dispatched or waited for.
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'run 42 of ci.yml (boot=true) already passed' pr:7 ci.yml boot=true
refute grep -Fq 'workflow run' "$FAKE_GH_LOG"; refute grep -q '^sleep' "$FAKE_GH_LOG"
# One in progress at the head is followed instead of dispatching a second run that would cancel it.
export FAKE_GH_RUN_ID=36
printf '[%s]' "$(run_json 35 "$H" in_progress '' 2099-01-01T00:00:00Z)" > "$TMP/list.json"
printf '[%s]' "$(run_json 35 "$H" completed success 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS"
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'run 35 success' pr:7 ci.yml
grep -Fq 'run 35 of ci.yml is already in_progress' "$TMP/ci.out"
refute grep -Fq 'workflow run' "$FAKE_GH_LOG"
# A pass at another commit is not reused: it dispatches.
printf '[%s]' "$(run_json 35 "$OLD" completed success 2099-01-01T00:00:00Z)" > "$TMP/list.json"
printf '[%s]' "$(run_json 36 "$H" completed success 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS"
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'run 36 success' pr:7 ci.yml
grep -Fq 'workflow run ci.yml' "$FAKE_GH_LOG"
# A newer cancelled run never hides a pass: before dispatching, the pass is reused.
printf '[%s,%s]' "$(run_json 101 "$H" completed success 2099-01-01T00:00:00Z)" "$(run_json 102 "$H" completed cancelled 2099-01-01T00:01:00Z)" > "$TMP/list.json"
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'run 101 of ci.yml already passed' pr:7 ci.yml
refute grep -Fq 'workflow run' "$FAKE_GH_LOG"
# And after its own run is cancelled, a later pass is followed past a newer cancelled run.
export FAKE_GH_RUN_ID=100
printf '[%s,%s]' "$(run_json 100 "$H" completed cancelled 2099-01-01T00:00:00Z)" "$(run_json 101 "$H" completed success 2099-01-01T00:01:00Z)" > "$FAKE_GH_RUNS"
printf '[]' > "$TMP/list.json.1"
printf '[%s,%s,%s]' "$(run_json 100 "$H" completed cancelled 2099-01-01T00:00:00Z)" "$(run_json 101 "$H" completed success 2099-01-01T00:01:00Z)" \
  "$(run_json 102 "$H" completed cancelled 2099-01-01T00:02:00Z)" > "$TMP/list.json"
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'run 101 success' pr:7 ci.yml
grep -Fq 'run 100 was cancelled by a later run at the same head; following run 101' "$TMP/ci.out"
# The same pass behind 25 later cancelled runs at the head and 150 later runs at another commit: still followed.
many() { local i; for i in $(seq "$1" "$2"); do printf ',%s' "$(run_json "$i" "$3" completed cancelled 2099-01-01T00:03:00Z)"; done; }
printf '[%s,%s%s%s]' "$(run_json 100 "$H" completed cancelled 2099-01-01T00:00:00Z)" "$(run_json 101 "$H" completed success 2099-01-01T00:01:00Z)" \
  "$(many 102 126 "$H")" "$(many 200 349 "$OLD")" > "$TMP/list.json"
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'run 101 success' pr:7 ci.yml
grep -Fq 'run 100 was cancelled by a later run at the same head; following run 101' "$TMP/ci.out"
# And behind 120 later cancelled runs at the head, past GitHub's first page of 100: still followed.
printf '[%s,%s%s]' "$(run_json 100 "$H" completed cancelled 2099-01-01T00:00:00Z)" "$(run_json 101 "$H" completed success 2099-01-01T00:01:00Z)" \
  "$(many 102 221 "$H")" > "$TMP/list.json"
FAKE_GH_LIST="$TMP/list.json" ci_expect 0 'run 101 success' pr:7 ci.yml
grep -Fq 'run 100 was cancelled by a later run at the same head; following run 101' "$TMP/ci.out"
rm -f "$TMP/list.json".*
# A repeated input is refused: gh would dispatch its last value, which the record cannot tell apart.
ci_refused 'input boot given twice' pr:7 ci.yml boot=true boot=false
# A failed read is retried at the next poll.
export FAKE_GH_RUN_ID=17
printf '[]' > "$FAKE_GH_RUNS.1"; printf '[%s]' "$(run_json 17 "$H" completed success 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS"
ci_expect 0 'run 17 success' pr:7 ci.yml
grep -Fq 'reading run 17 failed; trying again in 600s' "$TMP/ci.out"; [[ "$(grep -c '^sleep 600$' "$FAKE_GH_LOG")" -eq 2 ]]
rm -f "$FAKE_GH_RUNS.1"
# Its run at another commit means the branch moved before the dispatch: fail.
export FAKE_GH_RUN_ID=16
printf '[%s]' "$(run_json 16 "$OLD" in_progress '' 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS"
ci_expect 1 'the branch moved' pr:7 ci.yml
# Dispatched, but gh printed no run: cannot follow it.
printf '[%s]' "$(run_json 11 "$H" completed success 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS"
FAKE_GH_RUN_ID='' ci_expect 2 'gh did not print the run it created' pr:7 ci.yml
FAKE_GH_DISPATCH_RC=1 ci_expect 2 'dispatching ci.yml on feature failed' pr:7 ci.yml
FAKE_SLEEP_RC=1 ci_expect 2 'sleep 600 failed' pr:7 ci.yml
refute grep -q '^run view' "$FAKE_GH_LOG"
# Refusals before any dispatch, each with a passing run waiting to be found.
export FAKE_GH_RUN_ID=11
FAKE_GH_PR="$(pr_json "$OLD")" ci_refused 'push the reviewed head first' pr:7 ci.yml
FAKE_GH_PR="$(pr_json "$H" MERGED)" ci_refused 'PR #7 is MERGED' pr:7 ci.yml
ci_refused 'needs a pull request' id:branch ci.yml
# A failed PR read refuses even when gh printed a valid-looking PR.
FAKE_GH_PR_RC=1 ci_refused 'could not read PR #7 on example-org/example-dashboard' pr:7 ci.yml
ci_refused 'not an input=value pair: boot=true;rm' pr:7 ci.yml 'boot=true;rm'
ci_refused 'not a workflow file name: ../x.yml' pr:7 '../x.yml'
# Through the gate: the slot wrapper is not used, the bound is at least 3600,
# the pass is recorded with the CI run's line, and reused at the same head.
prep --pr 7 --pre-review --builder deepseek --engines grok > /dev/null; approve "$RUN_DIR" grok
printf 'example-org/example-dashboard\tbash %s run\tci:ci.yml boot=true\n' "$TMP/slot/box-test-slot.sh" > "$TMP/ci.tsv"
export FAKE_GH_RUN_ID=21; printf '[%s]' "$(run_json 21 "$H" completed success 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS"; rm -f "$FAKE_GH_N" "$FAKE_GH_RUNS".*
PATH="$FAKE:$PATH" GAUNTLET_ENFORCE_LIST="$TMP/ci.tsv" prep --pr 7 --run-once > "$TMP/ci-gate.out"
refute grep -Fq 'waiting for a box test slot' "$TMP/ci-gate.out"
grep -Fq 'RUN-ONCE: timeout --kill-after=10 3600 bash -c' "$TMP/ci-gate.out"
grep -Fq 'RUN-ONCE: exit 0' "$TMP/ci-gate.out"
ci_record="$(sed -n 's/^RUN-ONCE: exit 0 after [0-9]*s; record //p' "$TMP/ci-gate.out")"
grep -Fq 'CI RUN-ONCE: run 21 success' "$ci_record/output.log"
python3 - "$ci_record/run-once.json" <<'PY2'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["command"] == "ci:ci.yml boot=true" and r["wrapper"] is None and r["bound_seconds"] == 3600 and r["exit_code"] == 0, r
PY2
grep -Fq '"runner":"gauntlet-run-once","repo":' "$GAUNTLET_ROUND_RECORD"
PATH="$FAKE:$PATH" GAUNTLET_ENFORCE_LIST="$TMP/ci.tsv" prep --pr 7 --run-once > "$TMP/ci-reuse.out"
grep -Fq 'RUN-ONCE: a passing run-once is already recorded' "$TMP/ci-reuse.out"
# A failing CI run refuses round 1.
git -C "$R" commit -qm again --allow-empty; H="$(git -C "$R" rev-parse HEAD)"; export FAKE_GH_PR="$(pr_json "$H")"
export FAKE_GH_RUN_ID=22; printf '[%s]' "$(run_json 22 "$H" completed failure 2099-01-01T00:00:00Z)" > "$FAKE_GH_RUNS"; rm -f "$FAKE_GH_N"
if PATH="$FAKE:$PATH" GAUNTLET_ENFORCE_LIST="$TMP/ci.tsv" prep --pr 7 --run-once > /dev/null 2> "$TMP/ci-gate-fail.err"; then echo 'a failing CI run-once let round 1 prepare' >&2; exit 1; fi
grep -Fq 'the run-once command failed' "$TMP/ci-gate-fail.err"
# Enforcement-list tokens reach ci-run-once.sh as literal arguments: no command
# substitution and no glob expansion, and no dispatch for either.
mkdir -p "$TMP/glob"; : > "$TMP/glob/boot=true"
for bad in 'boot=$(id>'"$TMP"'/pwned)' "$TMP/glob/*"; do
  printf 'example-org/example-dashboard\tbash %s run\tci:ci.yml %s\n' "$TMP/slot/box-test-slot.sh" "$bad" > "$TMP/ci-bad.tsv"; : > "$FAKE_GH_LOG"
  if PATH="$FAKE:$PATH" GAUNTLET_ENFORCE_LIST="$TMP/ci-bad.tsv" prep --pr 7 --run-once > "$TMP/ci-bad.out" 2>&1; then echo "enforcement token $bad let round 1 prepare" >&2; exit 1; fi
  grep -Fq "not an input=value pair: $bad" "$TMP/ci-bad.out" || { echo "token $bad was not passed literally: $(cat "$TMP/ci-bad.out")" >&2; exit 1; }
  refute grep -Fq 'workflow run' "$FAKE_GH_LOG"
done
[[ ! -e "$TMP/pwned" ]]

# 9c. A run-once field `none` (a repo with no test workflow) still refuses round 1
#     without a pre-review, runs nothing, and lets round 1 prepare once a pre-review
#     is recorded, over 600 lines included (a size note, never a refusal).
printf 'example-org/example-infra\t-\tnone\n' > "$TMP/none.tsv"
new_repo infra https://github.com/example-org/example-infra.git
lines src.txt 5
if GAUNTLET_ENFORCE_LIST="$TMP/none.tsv" prep --identity infra1 > /dev/null 2> "$TMP/none-nopre.err"; then echo 'none skipped the pre-review' >&2; exit 1; fi
grep -Fq 'REFUSED (example-org/example-infra is on the enforcement list): no pre-review of id:infra1' "$TMP/none-nopre.err"
GAUNTLET_ENFORCE_LIST="$TMP/none.tsv" prep --identity infra1 --pre-review --builder deepseek --engines grok > /dev/null
approve "$RUN_DIR" grok
once_before="$(grep -c '"runner":"gauntlet-run-once"' "$GAUNTLET_ROUND_RECORD" || true)"
GAUNTLET_ENFORCE_LIST="$TMP/none.tsv" prep --identity infra1 --run-once > "$TMP/none.out"
grep -Fq 'RUN-ONCE: none for example-org/example-infra (enforcement list); nothing run' "$TMP/none.out"
grep -Fq 'ROUND: 1 identity=id:infra1' "$TMP/none.out"
test "$(grep -c '"runner":"gauntlet-run-once"' "$GAUNTLET_ROUND_RECORD" || true)" -eq "$once_before"
new_repo infrabig https://github.com/example-org/example-infra.git
lines src.txt 601
GAUNTLET_ENFORCE_LIST="$TMP/none.tsv" prep --identity infra2 --pre-review --builder deepseek --engines grok > /dev/null
approve "$RUN_DIR" grok
GAUNTLET_ENFORCE_LIST="$TMP/none.tsv" prep --identity infra2 > "$TMP/none-big.out" 2> "$TMP/none-big.err" \
  || { echo "an enforced 601-line round 1 with a pre-review did not prepare: $(cat "$TMP/none-big.err")" >&2; exit 1; }
grep -Fq 'SIZE NOTE: over 600' "$TMP/none-big.out"
grep -Fq 'ROUND: 1 identity=id:infra2' "$TMP/none-big.out"
test -e "$RUN_DIR/rows.json"
refute grep -Fq 'REFUSED' "$TMP/none-big.err"

# 10. Older readers of the round record skip the new lines quietly.
python3 - "$TMP/rounds.jsonl" <<'PY'
import json, sys
for raw in open(sys.argv[1]):
    e = json.loads(raw)
    assert all(isinstance(e.get(k), str) for k in ("runner", "repo", "identity", "digest")), e
    assert isinstance(e.get("round"), int) and e["round"] >= 1, e
PY
# The moved-line counter's own unit tests.
python3 "$SCRIPT_DIR/lib/nontest_lines_test.py"
echo 'round-gate.test.sh: OK'
