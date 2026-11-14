#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

for file in SKILL.md LICENSE references/compatibility.md references/reviewer-contract.md references/mcp-none.json scripts/gauntlet.sh; do
  test -f "$SKILL_DIR/$file"
done
test -x "$SCRIPT_DIR/gauntlet.sh"
bash -n "$SCRIPT_DIR/gauntlet.sh"
bash "$SCRIPT_DIR/gauntlet-v2.test.sh"
bash "$SCRIPT_DIR/round-gate.test.sh"
bash "$SCRIPT_DIR/approvals.test.sh"
bash "$SCRIPT_DIR/gauntlet-lifecycle.test.sh"

# The portable package has no registry or host lifecycle contract.
if grep -En 'deadline_ns|completed_at_ns|transport-selection|begin-native|order_started_at' "$SCRIPT_DIR/gauntlet.sh"; then
  echo 'stale lifecycle contract found' >&2; exit 1
else status=$?; [[ "$status" == 1 ]] || exit "$status"
fi
test ! -e "$SCRIPT_DIR/lib/run-registry.sh"
grep -Fq 'untrusted review data' "$SCRIPT_DIR/gauntlet.sh"
grep -Fq 'explicit complexity-budget exception from the reviewed work' "$SKILL_DIR/SKILL.md"
echo 'gauntlet portable smoke: OK'
# Retro ruling O1 (17 Oct 2026): the budget lives in the skill and the open-ended repair sentence is gone.
if grep -Fq 'whatever the fix needs' "$SKILL_DIR/SKILL.md"; then echo 'O1: open-ended repair sentence is back' >&2; exit 1; fi
grep -Fq '## Review budget' "$SKILL_DIR/SKILL.md"
grep -Fq '| Code that can move money or touch credentials | 3 |' "$SKILL_DIR/SKILL.md"
grep -Fq '`FIXES CHECKED @ <sha>`' "$SKILL_DIR/SKILL.md"
grep -Fq '**The recurrence ladder.**' "$SKILL_DIR/SKILL.md"
