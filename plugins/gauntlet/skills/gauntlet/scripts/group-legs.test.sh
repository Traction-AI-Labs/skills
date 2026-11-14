#!/usr/bin/env bash
# One round split by file group (12 Nov 2026):
# prepare pins one whole-diff digest and makes one leg per engine per group, each leg's prompt names its group's
# files, collect merges every leg into one verdict, and the round is recorded once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/gauntlet.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export GAUNTLET_ROUND_RECORD="$TMP/rounds.jsonl"
export GAUNTLET_ARCHIVE="$TMP/archive"
refute() { if "$@"; then echo "expected to fail: $*" >&2; exit 1; fi; }

git init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.name test
git -C "$TMP/repo" config user.email test@example.invalid
mkdir -p "$TMP/repo/src/api" "$TMP/repo/src/ui" "$TMP/repo/docs"
printf 'base\n' > "$TMP/repo/src/api/handler.txt"
printf 'base\n' > "$TMP/repo/src/ui/page.txt"
printf 'base\n' > "$TMP/repo/top.txt"
printf 'legacy one\nlegacy two\nlegacy three\n' > "$TMP/repo/src/ui/legacy.txt"
git -C "$TMP/repo" add . && git -C "$TMP/repo" commit -qm base
git -C "$TMP/repo" checkout -qb feature
printf 'changed\n' > "$TMP/repo/src/api/handler.txt"
printf 'new\n' > "$TMP/repo/src/api/route.txt"
printf 'changed\n' > "$TMP/repo/src/ui/page.txt"
printf 'changed\n' > "$TMP/repo/top.txt"
git -C "$TMP/repo" mv src/ui/legacy.txt src/api/legacy.txt
git -C "$TMP/repo" add . && git -C "$TMP/repo" commit -qm change

run() { GAUNTLET_REPO="$TMP/repo" GAUNTLET_DIR="$1" bash "$RUNNER" "${@:2}"; }

# Refusals: a group that matches nothing, the reserved name, a bad name, a name given twice, no path, a pre-review.
refute run "$TMP/r1" prepare --authorize-provider --base main --identity g --group api=src/api --group nothing=no/such 2> "$TMP/e1"
grep -Fq 'matches no changed file in scope: nothing' "$TMP/e1"
refute run "$TMP/r2" prepare --authorize-provider --base main --identity g --group Bad_Name=src 2> "$TMP/e2"
grep -Fq 'with a lowercase name other than rest: Bad_Name=src' "$TMP/e2"
refute run "$TMP/r5" prepare --authorize-provider --base main --identity g --group api=src/api --group api=src/ui 2> "$TMP/e5a"
grep -Fq -- '--group api is given twice' "$TMP/e5a"
refute run "$TMP/r6" prepare --authorize-provider --base main --identity g --group api= 2> "$TMP/e6a"
grep -Fq -- '--group api names no path' "$TMP/e6a"
refute run "$TMP/r3" prepare --authorize-provider --base main --identity g --group rest=src 2> "$TMP/e3"
grep -Fq 'other than rest' "$TMP/e3"
refute run "$TMP/r4" prepare --authorize-provider --base main --identity g --pre-review --builder deepseek --engines codex --group api=src/api 2> "$TMP/e4"
grep -Fq 'drop --group' "$TMP/e4"
test ! -e "$TMP/r1" && test ! -e "$TMP/r2" && test ! -e "$TMP/r3" && test ! -e "$TMP/r5" && test ! -e "$TMP/r6"
# One group holding every file is allowed: one leg per engine, each on the whole diff.
run "$TMP/one" prepare --authorize-provider --base main --identity one --group all=src,top.txt > "$TMP/one.out"
grep -Fxq 'LEGS: claude@all codex@all' "$TMP/one.out"
run "$TMP/one" clean --force
test ! -s "$GAUNTLET_ROUND_RECORD" || refute grep -Fq '"identity":"id:g"' "$GAUNTLET_ROUND_RECORD"

# A split round: api and ui named, top.txt falls to rest; 3 groups x 2 engines = 6 legs.
RUN="$TMP/run"
run "$RUN" prepare --authorize-provider --base main --profile fast --identity grouped --group api=src/api --group ui=src/ui/ > "$TMP/prepare.out"
grep -Fxq 'GROUPS: api (3 files); ui (2 files); rest (1 file)' "$TMP/prepare.out"
grep -Fxq 'LEGS: claude@api claude@ui claude@rest codex@api codex@ui codex@rest' "$TMP/prepare.out"
grep -Fq 'ROUND: 1 identity=id:grouped' "$TMP/prepare.out"
python3 - "$RUN/rows.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
assert rows["engines"] == ["claude", "codex"], rows["engines"]
assert rows["legs"] == ["claude@api", "claude@ui", "claude@rest", "codex@api", "codex@ui", "codex@rest"], rows["legs"]
# A rename across groups is in both: the old path's group and the new path's.
mv = "src/ui/legacy.txt -> src/api/legacy.txt"
assert sorted(rows["groups"]["api"]) == sorted(["src/api/handler.txt", mv, "src/api/route.txt"]), rows["groups"]
assert sorted(rows["groups"]["ui"]) == sorted([mv, "src/ui/page.txt"]), rows["groups"]
assert rows["groups"]["rest"] == ["top.txt"], rows["groups"]
PY
# Every leg reviews the same whole pinned diff (one digest), and its prompt names only its own group's files.
digest="$(cat "$RUN/scope/digest")"
for leg in claude@api claude@ui claude@rest codex@api codex@ui codex@rest; do
  for route in cli native; do
    p="$RUN/prompts/$leg-$route.md"
    grep -Fxq "Scope digest: $digest" "$p"
    grep -Fq "You review group \"${leg#*@}\"" "$p"
    grep -Fq 'Read the whole pinned diff for context' "$p"
  done
done
grep -Fxq -- '- src/api/route.txt' "$RUN/prompts/codex@api-cli.md"
refute grep -Fq -- '- top.txt' "$RUN/prompts/codex@api-cli.md"
grep -Fxq -- '- top.txt' "$RUN/prompts/claude@rest-cli.md"
grep -Fq 'cover the groups "ui", "rest"' "$RUN/prompts/claude@api-cli.md"
grep -Fq '{"engine":"codex","group":"api","model"' "$RUN/prompts/codex@api-cli.md"
grep -Fq '"group":{"type":"string","enum":["api"]}' "$RUN/schemas/codex@api-cli.json"
grep -Fq '(1 file, listed below)' "$RUN/prompts/claude@rest-cli.md"
test ! -e "$RUN/prompts/claude-cli.md"

# A leg must be named by engine and group in a split round.
refute run "$RUN" run-cli --engine claude 2> "$TMP/e5"
grep -Fq 'claude is not in this run' "$TMP/e5"
refute run "$RUN" run-cli --engine claude --group nosuch 2> "$TMP/e6"
grep -Fq 'claude@nosuch is not in this run' "$TMP/e6"
refute run "$RUN" run-cli --engine claude --group ../x 2> "$TMP/e6b"
grep -Fq -- '--group name must be lowercase' "$TMP/e6b"

# Native results: a group leg accepts only a reply that names its own group, and never while its CLI leg runs.
NRUN="$TMP/native"
run "$NRUN" prepare --authorize-provider --base main --profile fast --identity native --group api=src/api > /dev/null
nsha="$(sed -n 's/^Scope SHA: //p' "$NRUN/prompts/claude@api-native.md")"; ndig="$(sed -n 's/^Scope digest: //p' "$NRUN/prompts/claude@api-native.md")"
nmodel="$(sed -n 's/^Requested model: //p' "$NRUN/prompts/claude@api-native.md")"
printf '{"engine":"claude","group":"rest","model":"%s","transport":"claude-native","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$nmodel" "$nsha" "$ndig" > "$TMP/native-rest.txt"
printf '{"engine":"claude","group":"api","model":"%s","transport":"claude-native","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$nmodel" "$nsha" "$ndig" > "$TMP/native-api.txt"
refute run "$NRUN" ingest --engine claude --group api --text "$TMP/native-rest.txt" 2> /dev/null
test ! -e "$NRUN/results/claude@api.json"
rm -f "$NRUN/completion/claude@api.done" "$NRUN/failures/claude@api.txt"
mkdir "$NRUN/locks/claude@api.lock"
refute run "$NRUN" ingest --engine claude --group api --text "$TMP/native-api.txt" 2> "$TMP/e8"
grep -Fq 'has a CLI leg running' "$TMP/e8"
rmdir "$NRUN/locks/claude@api.lock"
run "$NRUN" ingest --engine claude --group api --text "$TMP/native-api.txt"
test -f "$NRUN/results/claude@api.json"
# collect --started-only may skip legs, never a whole group.
refute run "$NRUN" collect --started-only 2> "$TMP/e9"
grep -Fq 'no started leg reviews group(s) rest' "$TMP/e9"
cmodel="$(sed -n 's/^Requested model: //p' "$NRUN/prompts/codex@rest-native.md")"
printf '{"engine":"codex","group":"rest","model":"%s","transport":"codex-native","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$cmodel" "$nsha" "$ndig" > "$TMP/native-codex-rest.txt"
run "$NRUN" ingest --engine codex --group rest --text "$TMP/native-codex-rest.txt"
run "$NRUN" collect --started-only > "$TMP/native-collect.out"
grep -Fxq 'GAUNTLET: APPROVE' "$TMP/native-collect.out"
grep -Fxq 'NOT RUN: claude@rest codex@api' "$TMP/native-collect.out"

# Fake reviewers: the codex leg for api finds one defect; every other leg approves.
mkdir "$TMP/bin"
cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
p="$(cat)"; model="$(sed -n 's/^Requested model: //p' <<<"$p")"
sha="$(sed -n 's/^Scope SHA: //p' <<<"$p")"; digest="$(sed -n 's/^Scope digest: //p' <<<"$p")"
group="$(grep -o '"group":"[a-z0-9-]*",' <<<"$p" | head -n 1)"
cmp -s diff.patch "$FAKE_SCOPE_DIFF" || { echo 'leg did not get the whole pinned diff' >&2; exit 9; }
printf '{"type":"result","subtype":"success","structured_output":{"engine":"claude",%s"model":"%s","transport":"claude-cli","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}}\n' "$group" "$model" "$sha" "$digest"
EOF
cat > "$TMP/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
workspace=""; out=""; prev=""
for arg in "$@"; do [[ "$prev" == -C ]] && workspace="$arg"; [[ "$prev" == --output-last-message ]] && out="$arg"; prev="$arg"; done
cmp -s "$workspace/diff.patch" "$FAKE_SCOPE_DIFF" || { echo 'leg did not get the whole pinned diff' >&2; exit 9; }
p="$(cat)"; model="$(sed -n 's/^Requested model: //p' <<<"$p")"
sha="$(sed -n 's/^Scope SHA: //p' <<<"$p")"; digest="$(sed -n 's/^Scope digest: //p' <<<"$p")"
group="$(grep -o '"group":"[a-z0-9-]*",' <<<"$p" | head -n 1)"
if grep -Fq 'You review group "api"' <<<"$p"; then
  printf '{"engine":"codex",%s"model":"%s","transport":"codex-cli","scope_sha":"%s","scope_digest":"%s","verdict":"BLOCK","findings":[{"severity":"P1","location":"src/api/route.txt:1","failure_mode":"f","evidence":"e","causal_relation":"introduced","verification":"v"}]}\n' "$group" "$model" "$sha" "$digest" > "$out"
else
  printf '{"engine":"codex",%s"model":"%s","transport":"codex-cli","scope_sha":"%s","scope_digest":"%s","verdict":"APPROVE","findings":[]}\n' "$group" "$model" "$sha" "$digest" > "$out"
fi
EOF
chmod +x "$TMP/bin/claude" "$TMP/bin/codex"
cp "$RUN/scope/diff.patch" "$TMP/scope.diff"
for engine in claude codex; do
  for group in api ui rest; do
    PATH="$TMP/bin:$PATH" FAKE_SCOPE_DIFF="$TMP/scope.diff" run "$RUN" run-cli --engine "$engine" --group "$group" > "$TMP/start-$engine-$group.out"
    grep -Fxq "STARTED: $engine@$group" "$TMP/start-$engine-$group.out"
  done
done
for leg in claude@api claude@ui claude@rest codex@api codex@ui codex@rest; do
  n=0; while [[ ! -f "$RUN/completion/$leg.done" && "$n" -lt 1200 ]]; do sleep 0.05; n=$((n + 1)); done
  grep -Fxq 'exit_code=0' "$RUN/completion/$leg.done" || { cat "$RUN/failures/$leg.txt" >&2 || true; exit 1; }
  test -f "$RUN/results/$leg.json"
done

# collect: one verdict over all six legs, the defect keyed by its leg, one archive.
run "$RUN" collect > "$TMP/collect.out" 2>&1 || true
grep -Fxq 'GAUNTLET: BLOCK' "$TMP/collect.out"
grep -Fq 'FINDINGS: 1 as written, 1 open' "$TMP/collect.out"
grep -Fq 'OPEN codex@api#1 P1 src/api/route.txt:1' "$TMP/collect.out"
test "$(grep -c '^ARCHIVE: ' "$TMP/collect.out")" = 1
archive="$(sed -n 's/^ARCHIVE: //p' "$TMP/collect.out")"
test "$(ls "$archive/results" | grep -c '@')" = 6
cp "$RUN/scope/groups.json" "$TMP/groups.check" && cmp "$TMP/groups.check" "$archive/scope/groups.json"

# The round is recorded once: one round line and one verdict line for the identity, however many legs ran.
test "$(grep -F '"identity":"id:grouped"' "$GAUNTLET_ROUND_RECORD" | grep -c '"runner":"gauntlet"')" = 1
test "$(grep -F '"identity":"id:grouped"' "$GAUNTLET_ROUND_RECORD" | grep -c '"runner":"gauntlet-verdict"')" = 1
grep -F '"identity":"id:grouped"' "$GAUNTLET_ROUND_RECORD" | grep -F '"runner":"gauntlet-verdict"' | grep -Fq '"verdict":"BLOCK"'

# A finding in a split round is disposed by its leg (engine and group).
refute run "$RUN" dispose --engine codex --finding 1 --action drop --reason r --test true 2> "$TMP/e7"
grep -Fq 'codex is not in this run' "$TMP/e7"
run "$RUN" dispose --engine codex --group api --finding 1 --action drop --reason 'reproduced as fixed' --test true > "$TMP/dispose.out"
grep -Fxq 'DISPOSED: codex@api#1 drop' "$TMP/dispose.out"

# The disposition is recorded under the leg, and the next round on the same identity is round 2.
grep -Fq '"engine": "codex@api"' "$RUN/dispositions.jsonl" || grep -Fq '"engine":"codex@api"' "$RUN/dispositions.jsonl"
printf 'more\n' >> "$TMP/repo/top.txt"; git -C "$TMP/repo" commit -qam more
run "$TMP/run2" prepare --authorize-provider --base main --profile fast --identity grouped --group api=src/api > "$TMP/prepare2.out" 2>&1
grep -Fq 'ROUND: 2 identity=id:grouped' "$TMP/prepare2.out"
run "$TMP/run2" clean --force
echo 'group-legs: all checks passed'
