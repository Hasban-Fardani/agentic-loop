#!/usr/bin/env bash
# al goals — validasi Goal -> Plan -> Tasklist.
# Markdown dibaca manusia; kontrak JSON menjadi input gate deterministik.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"
al_need git jq || exit 2

GOAL="$AL_REPO_ROOT/$AL_GOAL_CONTRACT"
PLAN="$AL_REPO_ROOT/$AL_PLAN_CONTRACT"
TASKLIST="$AL_REPO_ROOT/$AL_TASKLIST_CONTRACT"
GOALS_MD="$AL_REPO_ROOT/$AL_GOAL_FILE"
STATE="$AL_REPO_ROOT/$AL_GOAL_STATE"

usage() {
  cat <<'EOF'
al goals — Goal -> Plan -> Tasklist

  al goals validate   validasi kontrak Goal, Plan, Tasklist dan DAG
  al goals start      kunci hash kontrak sebelum coder mulai
  al goals show       tampilkan status/risk/approval
  al goals verify     validasi ulang hash, scope, DoD gate, approval
  al goals findings   tampilkan temuan out-of-scope
EOF
}

need_file() { [ -f "$1" ] || { al_err "kontrak tidak ada: ${1#$AL_REPO_ROOT/}"; return 2; }; }
json_field() { jq -r "$1 // empty" "$2"; }

validate_goal() {
  need_file "$GOAL" || return 2
  need_file "$GOALS_MD" || return 2
  jq -e 'type == "object" and .schema_version == "goal/v1" and (.id|type == "string") and (.title|type == "string") and (.intent.statement|type == "string") and (.scope.allowed_paths|type == "array") and (.scope.forbidden_paths|type == "array")' "$GOAL" >/dev/null || { al_err 'goal schema invalid'; return 1; }
  local missing
  missing=$(jq -r '[.readiness | to_entries[] | select(.value != true) | .key] | join(",")' "$GOAL")
  [ -z "$missing" ] || { al_err "goal belum siap: $missing"; return 1; }
  jq -e '[.acceptance[]?.id] as $x | ($x|length) == ($x|unique|length)' "$GOAL" >/dev/null || { al_err 'acceptance ID duplikat'; return 1; }
  return 0
}

validate_plan() {
  need_file "$PLAN" || return 2
  jq -e 'type == "object" and .schema_version == "plan/v1" and (.id|type == "string") and (.goal_id|type == "string") and (.decision.approach|type == "string") and (.tasklists|type == "array")' "$PLAN" >/dev/null || { al_err 'plan schema invalid'; return 1; }
  local gid pgid status tier approval
  gid=$(json_field '.id' "$GOAL"); pgid=$(json_field '.goal_id' "$PLAN")
  [ "$gid" = "$pgid" ] || { al_err "plan goal_id mismatch: $pgid != $gid"; return 1; }
  status=$(json_field '.status' "$PLAN")
  case "$status" in draft|validated|review_required|approved|executable|executing|completed) ;; *) al_err "plan status invalid: $status"; return 1 ;; esac
  tier=$(json_field '.risk.assessed_tier' "$PLAN")
  case "$tier" in low|medium|high) ;; *) al_err "plan risk invalid: $tier"; return 1 ;; esac
  approval=$(json_field '.risk.approval.required' "$PLAN")
  if [ "$tier" != low ] && [ "$approval" != true ]; then al_err 'medium/high wajib human approval'; return 1; fi
  return 0
}

validate_tasklist() {
  need_file "$TASKLIST" || return 2
  jq -e 'type == "object" and .schema_version == "tasklist/v1" and (.id|type == "string") and (.plan_id|type == "string") and (.tasks|type == "array")' "$TASKLIST" >/dev/null || { al_err 'tasklist schema invalid'; return 1; }
  local pid tpid ids mode max
  pid=$(json_field '.id' "$PLAN"); tpid=$(json_field '.plan_id' "$TASKLIST")
  [ "$pid" = "$tpid" ] || { al_err "tasklist plan_id mismatch: $tpid != $pid"; return 1; }
  jq -e '[.tasks[].id] as $x | ($x|length) == ($x|unique|length) and all(.tasks[]; (.id|type == "string") and (.depends_on|type == "array") and (.definition_of_done.checks|type == "array"))' "$TASKLIST" >/dev/null || { al_err 'task ID/DoD invalid atau duplikat'; return 1; }
  jq -e '([.tasks[].id] | unique) as $ids | all(.tasks[]; all(.depends_on[]; ($ids | index(.)) != null))' "$TASKLIST" >/dev/null || { al_err 'dependency task tidak dikenal'; return 1; }
  jq -e 'all(.tasks[]; . as $task | (($task.depends_on // []) | index($task.id)) == null)' "$TASKLIST" >/dev/null || { al_err 'task bergantung pada dirinya sendiri'; return 1; }
  # Cycle check: dependency DFS. Any edge that reaches its source is a cycle.
  jq -e '
    ([.tasks[] | {id, deps: .depends_on}]) as $nodes
    | ($nodes | map({key: .id, value: .}) | from_entries) as $by
    | def reaches($id; $target; $seen):
        if $id == $target then true
        elif ($seen | index($id)) != null then false
        else any(($by[$id].deps // [])[]; reaches(.; $target; ($seen + [$id])))
        end;
    (any($nodes[]; . as $node | any($node.deps[]; reaches(.; $node.id; []))) | not)
  ' "$TASKLIST" >/dev/null || { al_err 'tasklist dependency graph cycle'; return 1; }
  mode=$(json_field '.execution.mode' "$TASKLIST")
  max=$(json_field '.execution.max_active_tasks' "$TASKLIST")
  case "$mode" in
    serial)
      if [ "$max" != 1 ]; then al_err 'serial tasklist wajib max_active_tasks=1'; return 1; fi
      ;;
    dag)
      if [ "${max:-0}" -le 1 ]; then al_err 'DAG tasklist wajib max_active_tasks > 1'; return 1; fi
      ;;
    *) al_err "execution mode invalid: $mode"; return 1 ;;
  esac
  # Every DoD check must be executable or an explicit artifact/path assertion.
  jq -e 'all(.tasks[].definition_of_done.checks[]; (.id|type == "string") and (.type == "command" and (.command|type == "string") and (.expect_exit|type == "number") or (.type != "command")) )' "$TASKLIST" >/dev/null || { al_err 'DoD check tidak executable'; return 1; }
  return 0
}

validate_all() {
  local rc=0 current
  validate_goal || { current=$?; [ "$rc" -eq 0 ] && rc="$current"; }
  validate_plan || { current=$?; [ "$rc" -eq 0 ] && rc="$current"; }
  validate_tasklist || { current=$?; [ "$rc" -eq 0 ] && rc="$current"; }
  return "$rc"
}

start_goal() {
  validate_all || return $?
  local head gh ph th tmp
  head=$(git -C "$AL_REPO_ROOT" rev-parse HEAD 2>/dev/null) || { al_err 'HEAD tidak dapat dibuktikan'; return 2; }
  gh=$(al_sha256 "$GOAL"); ph=$(al_sha256 "$PLAN"); th=$(al_sha256 "$TASKLIST")
  mkdir -p "$(dirname "$STATE")"
  tmp=$(mktemp)
  jq -n --arg head "$head" --arg gh "$gh" --arg ph "$ph" --arg th "$th" --arg started "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{schema_version:"goal-state/v1", state:"started", head_sha:$head, goal_hash:$gh, plan_hash:$ph, tasklist_hash:$th, started_at:$started}' > "$tmp"
  mv "$tmp" "$STATE"
  al_ok 'goals: contract terkunci'
}

verify_goal() {
  validate_all || return $?
  need_file "$STATE" || return 2
  local old current f
  for f in goal plan tasklist; do
    old=$(jq -r ".${f}_hash" "$STATE")
    case "$f" in goal) current=$(al_sha256 "$GOAL");; plan) current=$(al_sha256 "$PLAN");; tasklist) current=$(al_sha256 "$TASKLIST");; esac
    [ "$old" = "$current" ] || { al_err "${f} contract berubah setelah start"; return 2; }
  done
  case "$(json_field '.risk.assessed_tier' "$PLAN")" in
    medium|high)
      [ "$(json_field '.risk.approval.approval_ref' "$PLAN")" != PENDING ] || { al_err 'human approval pending'; return 2; }
      [ -n "$(json_field '.risk.approval.approved_head_sha' "$PLAN")" ] || { al_err 'approved_head_sha hilang'; return 2; } ;;
  esac
  if [ -f "$AL_REPO_ROOT/$AL_SCOPE_FILE" ]; then
    bash "$AL_HOME/core/cmd/scope.sh" check || return $?
  fi
  al_ok 'goals: verified'
}

show_goal() {
  printf 'goal: %s\nplan: %s\ntasklist: %s\nrisk: %s\n' \
    "$(json_field '.id' "$GOAL" 2>/dev/null || echo missing)" \
    "$(json_field '.id' "$PLAN" 2>/dev/null || echo missing)" \
    "$(json_field '.id' "$TASKLIST" 2>/dev/null || echo missing)" \
    "$(json_field '.risk.assessed_tier' "$PLAN" 2>/dev/null || echo unknown)"
  [ -f "$STATE" ] && jq . "$STATE" || true
}

findings() {
  local dir="$AL_REPO_ROOT/$AL_AGENT_DIR/findings"
  [ -d "$dir" ] || { al_info 'belum ada out-of-scope findings'; return 0; }
  find "$dir" -type f -maxdepth 1 -print | sort
}

cmd="${1:-help}"; [ $# -gt 0 ] && shift || true
case "$cmd" in
  validate) validate_all ;;
  start) start_goal ;;
  verify) verify_goal ;;
  show) show_goal ;;
  findings) findings ;;
  help|--help|-h) usage ;;
  *) al_err "subcommand tidak dikenal: $cmd"; usage >&2; exit 64 ;;
esac
