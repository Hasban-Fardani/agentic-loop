#!/usr/bin/env bash
. "${BASH_SOURCE[0]%/*}/lib.sh"

assert "project-init script ada" test -x "$AL/project-init.sh"
assert_contains "project-init help membedakan installer" "$("$AL/project-init.sh" --help)" "install.sh"
assert_contains "al help membedakan init" "$("$AL/bin/al" help)" "init --aep"

R="$(new_dir project-init)"; ( cd "$R" && git init -q )
( cd "$R" && AL_HOME="$AL" "$AL/project-init.sh" --aep ) >/dev/null 2>&1
for f in GOALS.md .agent/goal.json .agent/plan.json .agent/tasklist.json \
         AGENTS.md WORKFLOW.md TASK_TEMPLATE.md CHECKLIST.md CONVENTIONS.md COMPLEXITY.md; do
  assert "project init menulis $f" test -f "$R/$f"
done
refute "project init tidak memasang harness skill" test -d "$R/.hermes/skills"

# Idempotence: existing Goal tidak berubah tanpa force.
printf 'human goal\n' > "$R/GOALS.md"
( cd "$R" && AL_HOME="$AL" "$AL/project-init.sh" ) >/dev/null 2>&1
assert_contains "GOALS existing dipertahankan" "$(cat "$R/GOALS.md")" "human goal"

# Dry-run tidak menulis project contract baru.
D="$(new_dir project-init-dry)"; ( cd "$D" && git init -q )
( cd "$D" && AL_HOME="$AL" "$AL/project-init.sh" --dry-run ) >/dev/null 2>&1
refute "project init dry-run tidak menulis" test -e "$D/.agent/goal.json"

# Installer dry-run hanya menampilkan harness install; target project tetap bersih.
I="$(new_dir install-separation)"; mkdir -p "$I/project"
( cd "$I" && AL_HOME="$AL" AL_BIN_DIR=- AL_CLAUDE_HOME="$I/claude" "$AL/install.sh" --dry-run claude ) >/dev/null 2>&1
refute "install tidak menulis project contract" test -e "$I/project/.agent/goal.json"


test_summary
