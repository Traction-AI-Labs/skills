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
