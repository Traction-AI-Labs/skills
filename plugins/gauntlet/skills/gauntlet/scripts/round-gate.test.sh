#!/usr/bin/env bash
# Round-1 gate tests: the size note (retro ruling O6), round 1 with no pre-review and no run-once (both retired
# 22 Nov 2026), the round's checklist, and the slot wrapper disposition tests run in.
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

# 1. A repo off the list: round 1 prepares with its size note and no pre-review warning.
new_repo plain https://github.com/example/plain.git
lines src.txt 700
prep --identity plain > "$TMP/plain.out" 2> "$TMP/plain.err"
grep -Fq 'GAUNTLET_DIR=' "$TMP/plain.out"
grep -Fq 'SIZE NOTE: over 600 changed non-test lines' "$TMP/plain.out"
refute grep -Fq 'round 1 is limited' "$TMP/plain.err"
refute grep -Fqi 'pre-review' "$TMP/plain.err"
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
refute grep -Fq 'REFUSED' "$TMP/off.err"
# The shipped list has no live lines: a repo is enforced only once its owner adds one.
test -z "$(grep -Ev '^(#|$)' "$SCRIPT_DIR/../enforce.tsv")"

# Enforced repo from here on.
printf '#example-org/example-infra\t-\tnone\nexample-org/example-dashboard\t-\tnone\n' > "$TMP/on.tsv"
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
# 11. Without --report the counter prints the raw count.
[[ "$(python3 "$SCRIPT_DIR/lib/nontest_lines.py" "$ONE_R" main feature)" == 1410 ]] || SIZE_FAILS+=("coverage: one is not 1410 raw")
if (( ${#SIZE_FAILS[@]} )); then printf 'round-1 size case failed: %s\n' "${SIZE_FAILS[@]}" >&2; exit 1; fi
new_repo solo https://github.com/example-org/example-dashboard.git

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

# 4. Round 1 on an enforced repo prepares with no pre-review and no run-once on record (both retired 22 Nov 2026).
lines src.txt 5
prep --identity solo1 > "$TMP/solo1.out" 2> "$TMP/solo1.err" \
  || { echo "an enforced round 1 with no pre-review was refused: $(cat "$TMP/solo1.err")" >&2; exit 1; }
grep -Fq 'ROUND: 1 identity=id:solo1' "$TMP/solo1.out"
grep -Fq 'ROUND-1 SIZE: 5 changed non-test lines' "$TMP/solo1.out"
test -e "$RUN_DIR/rows.json"
refute grep -Fq 'REFUSED' "$TMP/solo1.err"
refute grep -Fqi 'pre-review' "$TMP/solo1.err"
refute grep -Fq 'RUN-ONCE' "$TMP/solo1.out"

# 5. A round's brief carries the checklist the pre-review used, on every leg and both routes, before the focus.
for f in claude-cli claude-native codex-cli codex-native; do
  grep -Fq 'Checklist. Check every item across the whole change, not only the newest commit: (1) empty, null and duplicate cases; (2) what survives a restart; (3) every existing user of a changed value; (4) every check-then-write.' "$RUN_DIR/prompts/$f.md" \
    || { echo "the round's brief $f.md does not carry the checklist" >&2; exit 1; }
  test "$(grep -n '^Checklist\.' "$RUN_DIR/prompts/$f.md" | cut -d: -f1)" -lt "$(grep -n '^Focus:' "$RUN_DIR/prompts/$f.md" | cut -d: -f1)"
done
approve "$RUN_DIR" claude > /dev/null

# 6. Each retired flag stops prepare non-zero with its one line, before anything is written or any reviewer is
#    prepared, so a calling script fails loudly.
lines_before="$(wc -l < "$GAUNTLET_ROUND_RECORD")"
for flag in --pre-review --builder --run-once; do
  extra=(); [[ "$flag" != --builder ]] || extra=(deepseek)
  fresh
  rc=0; GAUNTLET_REPO="$R" GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" prepare --authorize-provider --base main --profile fast --identity retired "$flag" ${extra[@]+"${extra[@]}"} > "$TMP/retired.out" 2> "$TMP/retired.err" || rc=$?
  test "$rc" -eq 1 || { echo "prepare $flag was not stopped (exit $rc)" >&2; exit 1; }
  case "$flag" in
    --run-once) grep -Fxq 'RETIRED: the run-once was retired on 22 Nov 2026; prepare without --run-once' "$TMP/retired.err" ;;
    *) grep -Fq 'RETIRED: the pre-review was retired on 22 Nov 2026' "$TMP/retired.err" ;;
  esac
  test "$(wc -l < "$TMP/retired.err" | tr -d ' ')" -eq 1
  test ! -s "$TMP/retired.out"
  test ! -e "$RUN_DIR"
done
test "$(wc -l < "$GAUNTLET_ROUND_RECORD")" -eq "$lines_before"

# 7. Old pre-review and run-once lines in the record are read without error and never count as rounds: an
#    identity with only those lines prepares round 1.
python3 -c '
import json, sys
record, repo, head = sys.argv[1:]
with open(record, "a") as f:
    for identity in ("id:legacy", "id:solo1"):
        f.write(json.dumps({"ts": "2026-11-01T00:00:00+00:00", "runner": "gauntlet-pre-review", "repo": repo, "identity": identity, "digest": head,
                            "head": head, "round": 1, "base": head, "engine": "grok", "builder": "deepseek", "eligible": True}, separators=(",", ":")) + "\n")
        f.write(json.dumps({"ts": "2026-11-01T00:00:00+00:00", "runner": "gauntlet-run-once", "repo": repo, "identity": identity, "digest": head,
                            "head": head, "exit_code": 0, "seconds": 3, "command": "none", "archive": "/nonexistent", "round": 7}, separators=(",", ":")) + "\n")
' "$GAUNTLET_ROUND_RECORD" "$(git -C "$R" rev-parse --path-format=absolute --git-common-dir)" "$(git -C "$R" rev-parse HEAD)"
prep --identity legacy > "$TMP/legacy.out" 2> "$TMP/legacy.err"
grep -Fq 'ROUND: 1 identity=id:legacy' "$TMP/legacy.out"
refute grep -Fq 'skipping malformed line' "$TMP/legacy.err"

# 8. No second round (22 Nov 2026), on an enforced repo and an unlisted one alike. solo1's round 1 has a round
#    line and no verdict line (collect never ran): new content is refused with one line naming that round's head
#    only, nothing is prepared or recorded, and the old pre-review and run-once lines changed nothing.
H1="$(git -C "$R" rev-parse HEAD)"
lines big.txt 900
lines_before="$(wc -l < "$GAUNTLET_ROUND_RECORD")"
rc=0; prep --identity solo1 > "$TMP/r2.out" 2> "$TMP/r2.err" || rc=$?
test "$rc" -eq 1 || { echo "a second round on new content was prepared: $(cat "$TMP/r2.out")" >&2; exit 1; }
grep -Fxq "NO SECOND ROUND: id:solo1 already had round 1 at ${H1:0:12} (no verdict line on record, so its archive and files are unknown) on this machine. Check the fixes against its findings (FIXES CHECKED), fix forward in its own PR, or hold" "$TMP/r2.err"
test ! -s "$TMP/r2.out"
test ! -e "$RUN_DIR"
test "$(wc -l < "$GAUNTLET_ROUND_RECORD")" -eq "$lines_before"

# 8b. With a verdict line, the refusal names the round's head and archive. Repo off the list.
export GAUNTLET_ENFORCE_LIST=/dev/null
both() { approve "$1" claude > /dev/null; approve "$1" codex > /dev/null; GAUNTLET_DIR="$1" bash "$RUNNER" collect > "$TMP/collect.out"; }
new_repo second https://github.com/example/second.git
lines a.txt 3; lines b.txt 3
prep --identity second > /dev/null
# 8c. A retry on the same content prepares, a fresh prepare after a failed leg included: round 1's claude leg is
#     valid (the round is recorded), its codex leg fails, and a fresh prepare on the unchanged head is a retry.
approve "$RUN_DIR" claude > /dev/null
printf 'not a result\n' > "$TMP/bad.txt"
refute env GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" ingest --engine codex --text "$TMP/bad.txt" 2> /dev/null
prep --identity second > "$TMP/retry.out" 2> "$TMP/retry.err" \
  || { echo "a retry on the same content was refused: $(cat "$TMP/retry.err")" >&2; exit 1; }
grep -Fxq 'ROUND: 1 (retry of recorded round 1) identity=id:second repo=second/.git' "$TMP/retry.out" || grep -Fq 'ROUND: 1 (retry of recorded round 1) identity=id:second' "$TMP/retry.out"
test -e "$RUN_DIR/rows.json"
both "$RUN_DIR"
H2="$(git -C "$R" rev-parse HEAD)"; ARCH2="$(sed -n 's/^ARCHIVE: //p' "$TMP/collect.out")"; test -n "$ARCH2"
printf 'fix\n' >> "$R/a.txt"; git -C "$R" commit -qam fix
rc=0; prep --identity second > /dev/null 2> "$TMP/second.err" || rc=$?
test "$rc" -eq 1 || { echo 'a second round over covered files was prepared' >&2; exit 1; }
grep -Fxq "NO SECOND ROUND: id:second already had round 1 at ${H2:0:12} (archive $ARCH2) on this machine; this scope holds 2 file(s) it covered, first a.txt. Check the fixes against its findings (FIXES CHECKED), fix forward in its own PR, or hold. A retry of that round needs the same head and the same --exclude list, which is in $ARCH2/scope/excludes" "$TMP/second.err"
test -f "$ARCH2/scope/excludes"
test ! -e "$RUN_DIR"

# 8d. A round after one whose legs all failed prepares: that round was never recorded, so this is round 1.
new_repo allfail https://github.com/example/allfail.git
lines a.txt 3
prep --identity allfail > /dev/null
refute env GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" ingest --engine claude --text "$TMP/bad.txt" 2> /dev/null
refute env GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" ingest --engine codex --text "$TMP/bad.txt" 2> /dev/null
GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" collect > /dev/null 2>&1 || true
printf 'fix\n' >> "$R/a.txt"; git -C "$R" commit -qam fix
prep --identity allfail > "$TMP/allfail.out" 2> "$TMP/allfail.err" \
  || { echo "a round after an all-failed one was refused: $(cat "$TMP/allfail.err")" >&2; exit 1; }
grep -Fq 'ROUND: 1 identity=id:allfail' "$TMP/allfail.out"

# 8e. A round that covers only files no earlier round of the identity covered prepares: round 1 left b.txt out
#     with --exclude; a round on b.txt alone is round 2. Without round 1's verdict line it would be refused.
new_repo newfiles https://github.com/example/newfiles.git
lines a.txt 3; lines b.txt 3
prep --identity newfiles --exclude b.txt > /dev/null
both "$RUN_DIR"
prep --identity newfiles --exclude a.txt > "$TMP/newfiles.out" 2> "$TMP/newfiles.err" \
  || { echo "a round over never-covered files was refused: $(cat "$TMP/newfiles.err")" >&2; exit 1; }
grep -Fxq 'NEW FILES ONLY: no earlier round of id:newfiles covered any file in this scope, so this round prepares' "$TMP/newfiles.out"
grep -Fq 'ROUND: 2 identity=id:newfiles' "$TMP/newfiles.out"
grep -Fq 'b/b.txt' "$RUN_DIR/scope/diff.patch"; refute grep -Fq 'b/a.txt' "$RUN_DIR/scope/diff.patch"
# 8f. A scope with one covered file (a.txt) and one no round covered (c.txt) is refused, and the one line says how to
#     reach the round that is still allowed: the never-covered file, and --exclude for each covered file.
NF_ARCH="$(sed -n 's/^ARCHIVE: //p' "$TMP/collect.out")"
lines c.txt 3
rc=0; prep --identity newfiles --exclude b.txt > "$TMP/mixed.out" 2> "$TMP/mixed.err" || rc=$?
test "$rc" -eq 1 || { echo 'a mixed scope was prepared' >&2; exit 1; }
test ! -s "$TMP/mixed.out"
test "$(wc -l < "$TMP/mixed.err" | tr -d ' ')" -eq 1
grep -Fq '; this scope holds 1 file(s) it covered, first a.txt; 1 file(s) in this scope no round covered, first c.txt: to review only those, prepare again with --exclude <file> for each covered file.' "$TMP/mixed.err" \
  || { echo "the refusal does not say how to reach the allowed round: $(cat "$TMP/mixed.err")" >&2; exit 1; }
grep -Fq "A retry of that round needs the same head and the same --exclude list, which is in $NF_ARCH/scope/excludes" "$TMP/mixed.err"
prep --identity newfiles --exclude a.txt --exclude b.txt > "$TMP/mixed2.out"
grep -Fq 'ROUND: 2 identity=id:newfiles' "$TMP/mixed2.out"
new_repo noverdict https://github.com/example/noverdict.git
lines a.txt 3; lines b.txt 3
prep --identity noverdict --exclude b.txt > /dev/null; approve "$RUN_DIR" claude > /dev/null
rc=0; prep --identity noverdict --exclude a.txt > /dev/null 2> "$TMP/noverdict.err" || rc=$?
test "$rc" -eq 1
grep -Fq 'NO SECOND ROUND: id:noverdict already had round 1' "$TMP/noverdict.err"
grep -Fq '(no verdict line on record, so its archive and files are unknown)' "$TMP/noverdict.err"
export GAUNTLET_ENFORCE_LIST="$TMP/on.tsv"

# 9. Disposition tests run in the slot wrapper (these cases moved here from the retired run-once). A slot
#    wrapper missing on this machine refuses with the same-machine text, and a test that ignores TERM is still
#    bounded (killed after the grace period; the outer watchdog fires if the runner does not end it).
block_result() {
  local run="$1" engine="$2" model sha digest
  model="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]]["model"])' "$run/rows.json" "$engine")"
  sha="$(sed -n 's/^Scope SHA: //p' "$run/prompts/$engine-native.md")"; digest="$(sed -n 's/^Scope digest: //p' "$run/prompts/$engine-native.md")"
  printf '{"engine":"%s","model":"%s","transport":"%s-native","scope_sha":"%s","scope_digest":"%s","verdict":"BLOCK","findings":[{"severity":"P1","location":"src.txt:1","failure_mode":"f","evidence":"e","causal_relation":"introduced","verification":"v"}]}\n' "$engine" "$model" "$engine" "$sha" "$digest" > "$TMP/result.txt"
  GAUNTLET_DIR="$run" bash "$RUNNER" ingest --engine "$engine" --text "$TMP/result.txt"
}
new_repo box https://github.com/example-org/example-dashboard.git
lines src.txt 5
prep --identity box --timeout-seconds 1 > /dev/null
block_result "$RUN_DIR" codex > /dev/null
printf 'example-org/example-dashboard\t/nonexistent/box-test-slot.sh run\tnone\n' > "$TMP/missing.tsv"
if GAUNTLET_ENFORCE_LIST="$TMP/missing.tsv" GAUNTLET_DIR="$RUN_DIR" bash "$RUNNER" dispose --engine codex --finding 1 --action drop --reason r --test true > /dev/null 2> "$TMP/missing.err"; then exit 1; fi
grep -Fq 'is not on this machine' "$TMP/missing.err"
grep -Fq 'rounds and dispositions run on the same machine' "$TMP/missing.err"
term_rc=0
GAUNTLET_DIR="$RUN_DIR" timeout 60 bash "$RUNNER" dispose --engine codex --finding 1 --action drop --reason r --test 'trap "" TERM; while :; do sleep 1; done' > "$TMP/term.out" 2> "$TMP/term.err" || term_rc=$?
[[ "$term_rc" -ne 124 && "$term_rc" -ne 0 ]] || { echo "TERM-ignoring disposition test not bounded by the runner (rc $term_rc)" >&2; exit 1; }
grep -Fq 'exit 124, timed out' "$TMP/term.err"

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
