#!/usr/bin/env bash
# al event TYPE [key=val ...] — append event audit ke AL_EVENT_LOG.
# Append-only, idempoten lewat hash konten. Nilai secret diredaksi.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"
al_need jq || exit 2

TYPE="${1:-}"
[ -n "$TYPE" ] || al_die "usage: al event <type> [key=val ...]"
shift

case "$TYPE" in
  task_started|evidence_run|approval|merge|deploy|incident|deletion|rollback) : ;;
  *) al_die "event_type tidak dikenal: $TYPE" ;;
esac

mkdir -p "$(dirname "$AL_EVENT_PATH")"

uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen
  else od -xN16 -An /dev/urandom | tr -d ' \n'; fi
}

json=$(jq -nc \
  --arg id   "$(uuid)" \
  --arg t    "$TYPE" \
  --arg pol  "$AL_POLICY_VERSION" \
  --arg proj "$(basename "$AL_REPO_ROOT")" \
  --arg task "$AL_TASK_ID" \
  --arg sha  "$(git -C "$AL_REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)" \
  '{event_id:$id, project_id:$proj, task_id:$task, event_type:$t,
    commit_sha:$sha, policy_version:$pol, created_at:(now|todate)}')

for kv in "$@"; do
  case "$kv" in
    *=*) : ;;
    *) al_die "argumen harus key=val, dapat: $kv" ;;
  esac
  k="${kv%%=*}"
  v="$(al_redact_str "${kv#*=}")"
  json=$(jq -c --arg k "$k" --arg v "$v" '.[$k]=$v' <<<"$json")
done

# idempotency_key = hash konten tanpa event_id/created_at, sehingga event yang
# identik secara semantik tidak tercatat dua kali walau di-retry.
key=$(jq -S 'del(.event_id, .created_at)' <<<"$json" | al_sha256_stdin)
json=$(jq -c --arg k "$key" '.idempotency_key=$k' <<<"$json")

if [ -f "$AL_EVENT_PATH" ] && grep -qF "\"idempotency_key\":\"$key\"" "$AL_EVENT_PATH"; then
  al_info "event duplikat ditekan: $TYPE"
  exit 0
fi

if [ "${AL_DRY_RUN:-0}" = 1 ]; then
  al_info "DRY-RUN: append ke $(al_repo_rel "$AL_EVENT_PATH")"
  printf '%s\n' "$json"
  exit 0
fi

printf '%s\n' "$json" >> "$AL_EVENT_PATH"
printf '%s\n' "$json"
