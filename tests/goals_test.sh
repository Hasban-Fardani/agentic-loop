#!/usr/bin/env bash
# Kontrak Goal -> Plan -> Tasklist dan hash immutability.
. "${BASH_SOURCE[0]%/*}/lib.sh"

R="$(new_dir goals)"
git -C "$R" init -q
git -C "$R" config user.email ci@example.test
git -C "$R" config user.name ci
AL_HOME="$AL" AL_REPO_ROOT="$R" "$AL/bin/al" init >/dev/null 2>&1
git -C "$R" add -A
git -C "$R" commit -qm init

run_al() { AL_HOME="$AL" AL_REPO_ROOT="$R" AL_SCOPE_FILE=".agent/no-scope.yaml" "$AL/bin/al" "$@"; }

assert_contains "goals command terdaftar" "$("$AL/bin/al" help)" "goals <sub>"
assert_eq "template awal belum siap" 1 "$(run_al goals validate >/dev/null 2>&1; echo $?)"

jq '.id="G-001" | .title="Goal test" | .intent.statement="hasil terukur" | .readiness={context_complete:true,scope_clear:true,constraints_clear:true,acceptance_testable:true,risks_identified:true} | .scope.allowed_paths=["src/"] | .acceptance=[{"id":"AC-1","statement":"test lulus"}]' "$R/.agent/goal.json" > "$R/.agent/goal.json.tmp" && mv "$R/.agent/goal.json.tmp" "$R/.agent/goal.json"
jq '.id="P-001" | .goal_id="G-001" | .title="Plan test" | .decision.approach="satu pendekatan" | .status="approved" | .risk={inherited_tier:"low",assessed_tier:"low",reasons:[],approval:{required:false,approval_ref:"PENDING",approved_head_sha:""}} | .tasklists=[{"id":"TL-001","path":".agent/tasklist.json"}]' "$R/.agent/plan.json" > "$R/.agent/plan.json.tmp" && mv "$R/.agent/plan.json.tmp" "$R/.agent/plan.json"
jq '.id="TL-001" | .plan_id="P-001" | .tasks=[{"id":"T-001","title":"test","status":"pending","depends_on":[],"definition_of_done":{"checks":[{"id":"command","type":"command","command":"true","expect_exit":0}]}}]' "$R/.agent/tasklist.json" > "$R/.agent/tasklist.json.tmp" && mv "$R/.agent/tasklist.json.tmp" "$R/.agent/tasklist.json"
printf '%s\n' '# Goal test' > "$R/GOALS.md"

assert_eq "kontrak valid" 0 "$(rc_of run_al goals validate)"
assert_eq "start mengunci hash" 0 "$(rc_of run_al goals start)"
assert "state tersimpan" test -f "$R/.agent/goal-state.json"
assert_eq "verify hash valid" 0 "$(rc_of run_al goals verify)"
printf '\n' >> "$R/.agent/plan.json"
assert_eq "mutasi kontrak jadi UNKNOWN" 2 "$(rc_of run_al goals verify)"

# Siklus dependency harus ditolak sebagai FAIL.
jq '.tasks=[{"id":"T-1","depends_on":["T-2"],"definition_of_done":{"checks":[{"id":"c1","type":"command","command":"true","expect_exit":0}]}},{"id":"T-2","depends_on":["T-1"],"definition_of_done":{"checks":[{"id":"c2","type":"command","command":"true","expect_exit":0}]}}]' "$R/.agent/tasklist.json" > "$R/.agent/tasklist.json.tmp" && mv "$R/.agent/tasklist.json.tmp" "$R/.agent/tasklist.json"
assert_eq "DAG cycle FAIL" 1 "$(rc_of run_al goals validate)"

test_summary
