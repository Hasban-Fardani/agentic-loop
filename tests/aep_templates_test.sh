#!/usr/bin/env bash
. "${BASH_SOURCE[0]%/*}/lib.sh"

for f in AGENTS.md WORKFLOW.md TASK_TEMPLATE.md CHECKLIST.md METRICS.md README.md CONVENTIONS.md COMPLEXITY.md; do
  assert "template AEP $f ada" test -f "$AL/core/templates/aep/$f"
done
assert "AGENTS menunjuk workflow" grep -q 'WORKFLOW.md' "$AL/core/templates/aep/AGENTS.md"
assert "AGENTS context terbatas" test "$(wc -l < "$AL/core/templates/aep/AGENTS.md")" -le 150

R="$(new_dir aep)"; git -C "$R" init -q
( cd "$R" && AL_HOME="$AL" "$AL/bin/al" init --aep ) >/dev/null 2>&1
for f in AGENTS.md WORKFLOW.md TASK_TEMPLATE.md CHECKLIST.md METRICS.md README.md CONVENTIONS.md COMPLEXITY.md; do
  assert "init --aep menulis $f" test -f "$R/$f"
done

test_summary
