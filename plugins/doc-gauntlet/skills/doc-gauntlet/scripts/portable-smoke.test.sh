#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

for path in "$SKILL_DIR/SKILL.md" "$SKILL_DIR/LICENSE" "$SKILL_DIR/references/compatibility.md" "$SKILL_DIR/references/mcp-none.json" "$SCRIPT_DIR/doc-gauntlet.sh" "$SCRIPT_DIR/validate-review-kernel.py"; do test -f "$path"; done
test ! -e "$SCRIPT_DIR/review-git.sh"
test ! -e "$SCRIPT_DIR/lib/run-registry.sh"
test ! -e "$SKILL_DIR/REVIEW-LOG.md"
for command in prepare run-cli ingest collect clean; do "$SCRIPT_DIR/doc-gauntlet.sh" --help | grep -Fq "$command"; done
for forbidden in 'deadline_ns' 'completed_at_ns' 'prompt digest' 'reason code' 'run-registry'; do
  for path in "$SKILL_DIR/SKILL.md" "$SKILL_DIR/references/compatibility.md" "$SKILL_DIR/references/reviewer-contract.md" "$SKILL_DIR/references/review-kernel/subagent-template.md" "$SCRIPT_DIR/doc-gauntlet.sh" "$SCRIPT_DIR/validate-review-kernel.py"; do
    if grep -IqiF "$forbidden" "$path"; then echo "stale lifecycle contract found: $forbidden in $path" >&2; exit 1; else status=$?; [[ "$status" == 1 ]] || exit "$status"; fi
  done
done
grep -Fq 'concrete consequence' "$SKILL_DIR/SKILL.md"
grep -Fq 'complexity-budget exception from the reviewed work' "$SKILL_DIR/SKILL.md"
bash "$SCRIPT_DIR/doc-gauntlet-v2.test.sh"
bash "$SCRIPT_DIR/doc-gauntlet-lifecycle.test.sh"
echo 'doc-gauntlet portable smoke: OK'
