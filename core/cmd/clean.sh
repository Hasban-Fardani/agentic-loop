#!/usr/bin/env bash
# al clean — hapus log kedaluwarsa. Artifact TIDAK pernah disentuh di sini:
# retention 1 tahun dan legal hold dikelola terpisah dan sengaja manual.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"

if [ "$AL_LEGAL_HOLD" = 1 ]; then
  al_warn "AL_LEGAL_HOLD=1 — tidak ada yang dihapus"
  exit 0
fi

[ -d "$AL_LOG_PATH" ] || { al_info "tidak ada direktori log"; exit 0; }

n=$(find "$AL_LOG_PATH" -mindepth 1 -maxdepth 1 -type d -mtime +"$AL_LOG_RETENTION_DAYS" 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" = 0 ]; then
  al_info "tidak ada log lebih tua dari ${AL_LOG_RETENTION_DAYS} hari"
  exit 0
fi

if [ "${AL_DRY_RUN:-0}" = 1 ]; then
  al_info "DRY-RUN: akan menghapus $n direktori log"
  find "$AL_LOG_PATH" -mindepth 1 -maxdepth 1 -type d -mtime +"$AL_LOG_RETENTION_DAYS" 2>/dev/null
  exit 0
fi

find "$AL_LOG_PATH" -mindepth 1 -maxdepth 1 -type d -mtime +"$AL_LOG_RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true
al_ok "clean: $n direktori log dihapus; artifact dipertahankan"
