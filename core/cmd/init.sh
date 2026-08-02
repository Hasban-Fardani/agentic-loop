#!/usr/bin/env bash
# al init — pasang skeleton .agent/ + adapter evidence ke repo saat ini.
# Idempoten: file yang sudah ada tidak ditimpa kecuali AL_FORCE=1.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"

TPL="$AL_HOME/core/templates"
[ -d "$TPL" ] || al_die "template tidak ditemukan: $TPL"

printf '\nWARNING: agentic-loop hanya untuk development, testing, dan staging.\n' >&2
printf 'WARNING: jangan gunakan di production atau berikan production secrets.\n\n' >&2

git -C "$AL_REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || al_warn "bukan repo git — evidence gate butuh commit SHA untuk mengikat hasil"

placed=0; kept=0

put() { # put SRC DEST_REL
  dest="$AL_REPO_ROOT/$2"
  if [ -e "$dest" ] && [ "${AL_FORCE:-0}" != 1 ]; then
    al_debug "ada, dilewati: $2"; kept=$((kept+1)); return 0
  fi
  if [ "${AL_DRY_RUN:-0}" = 1 ]; then al_info "DRY-RUN: tulis $2"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  # Substitusi hanya placeholder yang kita kendalikan sendiri.
  sed -e "s|@@REPO@@|$(basename "$AL_REPO_ROOT")|g" \
      -e "s|@@AGENT_DIR@@|$AL_AGENT_DIR|g" \
      -e "s|@@ADAPTER_DIR@@|$AL_ADAPTER_DIR|g" \
      -e "s|@@POLICY_VERSION@@|$AL_POLICY_VERSION|g" \
      -e "s|@@CONTRACT_VERSION@@|$AL_CONTRACT_VERSION|g" \
      "$1" > "$dest"
  case "$2" in *.sh) chmod +x "$dest" ;; esac
  al_info "tulis $2"; placed=$((placed+1))
}

put "$TPL/evidence.yaml"            "$AL_AGENT_DIR/evidence.yaml"
put "$TPL/acceptance-evidence.yaml" "$AL_AGENT_DIR/acceptance-evidence.yaml"
put "$TPL/agent-policy.yaml"        "$AL_AGENT_DIR/agent-policy.yaml"
put "$TPL/scope.yaml"               "$AL_AGENT_DIR/scope.yaml"
put "$TPL/complexity.yaml"          "$AL_AGENT_DIR/complexity.yaml"
put "$TPL/GOALS.md"                  "$AL_GOAL_FILE"
put "$TPL/goal.json"                 "$AL_GOAL_CONTRACT"
put "$TPL/plan.json"                 "$AL_PLAN_CONTRACT"
put "$TPL/tasklist.json"             "$AL_TASKLIST_CONTRACT"
put "$TPL/github-automation.json"    "$AL_AGENT_DIR/github-automation.json"
put "$TPL/decision-event.json"       "$AL_AGENT_DIR/decision-event.json"
[ "${AL_DRY_RUN:-0}" = 1 ] || mkdir -p "$AL_REPO_ROOT/$AL_AGENT_DIR/decisions"

for step in setup build test lint security healthcheck cleanup; do
  put "$TPL/adapters/$step.sh" "$AL_ADAPTER_DIR/$step.sh"
done

if [ "${1:-}" = "--aep" ]; then
  for f in AGENTS.md WORKFLOW.md TASK_TEMPLATE.md CHECKLIST.md METRICS.md README.md CONVENTIONS.md COMPLEXITY.md; do
    put "$TPL/aep/$f" "$f"
  done
fi

# .gitignore: tambah baris yang belum ada, jangan pernah menulis ulang file user.
gi="$AL_REPO_ROOT/.gitignore"
# Baris minimum yang WAJIB: secret dan output runtime. Lockfile sengaja TIDAK
# di-ignore — ia justru harus di-commit untuk reproducibility.
need="/.env
!/.env.example
/$AL_ARTIFACT_DIR/
/$AL_LOG_DIR/
/$AL_EVENT_LOG"
added=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  if [ -f "$gi" ] && grep -qxF -- "$line" "$gi"; then continue; fi
  if [ "${AL_DRY_RUN:-0}" = 1 ]; then al_info "DRY-RUN: .gitignore += $line"; continue; fi
  [ "$added" = 0 ] && printf '\n# agentic-loop\n' >> "$gi"
  printf '%s\n' "$line" >> "$gi"
  added=$((added+1))
done <<EOF
$need
EOF
[ "$added" -gt 0 ] && al_info ".gitignore: $added baris ditambah"

al_ok "init: $placed file dibuat, $kept dipertahankan"
al_info "berikutnya: al doctor && al run smoke"
