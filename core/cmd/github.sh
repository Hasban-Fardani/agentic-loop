#!/usr/bin/env bash
# al github — validasi Hermes GitHub event contract dan decision artifacts.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"
al_need jq || exit 2

AUTO="$AL_REPO_ROOT/$AL_AGENT_DIR/github-automation.json"
DECISIONS="$AL_REPO_ROOT/$AL_AGENT_DIR/decisions"
INDEX="$AL_REPO_ROOT/$AL_EVENT_LOG"

usage() {
  cat <<'EOF'
al github
  validate     validasi automation contract
  decision FILE validasi decision artifact terhadap current HEAD
  list-decisions tampilkan decision artifacts
EOF
}

need_auto() { [ -f "$AUTO" ] || { al_err "automation contract hilang: ${AUTO#$AL_REPO_ROOT/}"; return 2; }; }

validate() {
  need_auto || return 2
  jq -e '
    .schema_version == "github-automation/v1"
    and .environment != "production"
    and .production_allowed == false
    and .hermes.mode == "dynamic_subscription"
    and (.hermes.events | length > 0)
    and (.execution.allowed_actors | length > 0)
    and .execution.confirmation_required == true
    and .execution.draft_patch_first == true
    and .execution.worktree_required == true
    and .execution.production_secrets == false
    and .execution.merge_allowed == false
    and .execution.approve_allowed == false
    and .execution.force_push_allowed == false
    and .execution.deploy_allowed == false
    and .decisions.bind_to_head_sha == true
    and .decisions.invalidate_on_new_head == true
  ' "$AUTO" >/dev/null || { al_err 'github automation contract invalid'; return 1; }
  al_ok 'github automation: valid, Hermes dynamic subscription, non-production'
}

decision() {
  local file="${1:-}"
  [ -n "$file" ] || { al_err 'usage: al github decision FILE'; return 64; }
  [ -f "$file" ] || { al_err "decision artifact hilang: $file"; return 2; }
  jq -e '
    .schema_version == "decision-event/v1"
    and (.event_id | type == "string" and length > 0)
    and (.actor.type == "human")
    and (.actor.id | type == "string" and length > 0)
    and (.head_sha | type == "string" and length > 0)
    and (.confirmation.required == true)
    and (.confirmation.confirmed == true)
  ' "$file" >/dev/null || { al_err 'decision artifact incomplete atau belum dikonfirmasi'; return 1; }
  local expected current
  expected=$(jq -r '.head_sha' "$file")
  current=$(git -C "$AL_REPO_ROOT" rev-parse HEAD 2>/dev/null) || { al_err 'HEAD tidak terbukti'; return 2; }
  [ "$expected" = "$current" ] || { al_err 'decision stale: head SHA berbeda'; return 2; }
  al_ok 'decision: human confirmed and bound to current HEAD'
}

list_decisions() {
  [ -d "$DECISIONS" ] || { al_info 'belum ada decisions artifact'; return 0; }
  find "$DECISIONS" -maxdepth 1 -type f -name '*.json' -print | sort
}

cmd="${1:-help}"; [ $# -gt 0 ] && shift || true
case "$cmd" in
  validate) validate ;;
  decision) decision "$@" ;;
  list-decisions) list_decisions ;;
  help|--help|-h) usage ;;
  *) al_err "subcommand tidak dikenal: $cmd"; usage >&2; exit 64 ;;
esac
