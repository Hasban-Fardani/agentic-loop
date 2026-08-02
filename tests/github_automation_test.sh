#!/usr/bin/env bash
. "${BASH_SOURCE[0]%/*}/lib.sh"

assert "github command ada" test -f "$AL/core/cmd/github.sh"
assert_contains "help menyebut github" "$("$AL/bin/al" help)" "github <sub>"

R="$(new_dir github)"; git -C "$R" init -q
run_al() { AL_HOME="$AL" AL_REPO_ROOT="$R" "$AL/bin/al" "$@"; }
( cd "$R" && run_al init ) >/dev/null 2>&1
printf init > "$R/README.md"
git -C "$R" config user.email test@example.test
git -C "$R" config user.name test
git -C "$R" add -A && git -C "$R" commit -qm init
assert_eq "automation template valid" 0 "$(rc_of run_al github validate)"
assert "decisions directory dibuat" test -d "$R/.agent/decisions"

head=$(git -C "$R" rev-parse HEAD)
jq --arg sha "$head" '.event_id="EV-1" | .actor.id="owner" | .head_sha=$sha | .confirmation.confirmed=true' "$R/.agent/decision-event.json" > "$R/.agent/decisions/DEC-1.json"
assert_eq "confirmed decision current SHA" 0 "$(rc_of run_al github decision "$R/.agent/decisions/DEC-1.json")"

jq '.execution.allowed_actors=["owner"]' "$R/.agent/github-automation.json" > "$R/.agent/github-automation.json.tmp" && mv "$R/.agent/github-automation.json.tmp" "$R/.agent/github-automation.json"
assert_eq "RBAC allowlist wajib terisi" 0 "$(rc_of run_al github validate)"

jq --arg sha old '.head_sha=$sha' "$R/.agent/decisions/DEC-1.json" > "$R/.agent/decisions/DEC-1-stale.json"
assert_eq "stale decision UNKNOWN" 2 "$(rc_of run_al github decision "$R/.agent/decisions/DEC-1-stale.json")"

jq '.execution.confirmation_required=false' "$R/.agent/github-automation.json" > "$R/.agent/github-automation.json.tmp" && mv "$R/.agent/github-automation.json.tmp" "$R/.agent/github-automation.json"
assert_eq "confirmation disabled FAIL" 1 "$(rc_of run_al github validate)"

test_summary
