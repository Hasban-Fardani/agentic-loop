#!/usr/bin/env bash
# al doctor — laporkan konfigurasi efektif, tool, dan harness terpasang.
# Read-only. Nilai secret TIDAK pernah dicetak; hanya status "set"/"not set".
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"

fail=0
row()  { printf '  %-28s %s\n' "$1" "$2"; }
bad()  { printf '  %-28s %s\n' "$1" "MISSING — $2"; fail=1; }

printf '\nagentic-loop doctor\n'
printf '===================\n\n'

printf 'Paths\n'
row AL_HOME       "$AL_HOME"
row AL_REPO_ROOT  "$AL_REPO_ROOT"
row AL_CONFIG_HOME "$AL_CONFIG_HOME"

printf '\nConfig sources (presedensi rendah -> tinggi)\n'
for f in "$AL_CONFIG_HOME/config.env" "$AL_REPO_ROOT/.env"; do
  if [ -f "$f" ]; then
    perm=$(ls -l "$f" | cut -d' ' -f1)
    row "$(al_repo_rel "$f")" "ada ($perm)"
    case "$perm" in
      -rw-------*) : ;;
      *) al_warn "permission $f terlalu terbuka; jalankan: chmod 600 $f" ;;
    esac
  else
    row "$(al_repo_rel "$f")" "tidak ada (opsional)"
  fi
done
row "environment" "selalu menang atas file"

printf '\nRequired tools\n'
for t in git jq bash; do
  if command -v "$t" >/dev/null 2>&1; then
    row "$t" "$(command -v "$t")"
  else
    bad "$t" "wajib"
  fi
done

printf '\nOptional tools\n'
for t in shellcheck yq gh docker timeout gtimeout perl; do
  if command -v "$t" >/dev/null 2>&1; then row "$t" "$(command -v "$t")"
  else row "$t" "absen"; fi
done
if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
  if command -v perl >/dev/null 2>&1; then
    row "timeout strategy" "perl fallback (ok)"
  else
    bad "timeout strategy" "butuh salah satu: timeout, gtimeout, atau perl"
  fi
else
  row "timeout strategy" "coreutils"
fi

printf '\nSecrets (nama saja, nilai tidak pernah dicetak)\n'
for v in $AL_SECRET_VARS; do
  eval "val=\${$v:-}"
  if [ -n "$val" ]; then row "$v" "set (${#val} char, diredaksi)"; fi
done
printf '  %-28s %s\n' "(total terdaftar)" "$(printf '%s\n' $AL_SECRET_VARS | wc -l | tr -d ' ') nama di AL_SECRET_VARS"

printf '\nEffective evidence config\n'
row AL_PROFILE           "$AL_PROFILE"
row AL_TIMEOUT_DEFAULT   "${AL_TIMEOUT_DEFAULT}s"
row AL_RISK_TIER         "$AL_RISK_TIER"
row AL_STRICT_WORKTREE   "$AL_STRICT_WORKTREE"
row AL_STRICT_ACCEPTANCE "$AL_STRICT_ACCEPTANCE"
row AL_POLICY_VERSION    "$AL_POLICY_VERSION"

printf '\nRepo target\n'
if git -C "$AL_REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if head_sha=$(git -C "$AL_REPO_ROOT" rev-parse --short HEAD 2>/dev/null); then
    row "git" "$(git -C "$AL_REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null) @ $head_sha"
  else
    row "git" "repo kosong (belum ada commit)"
  fi
  dirty=$(git -C "$AL_REPO_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  row "worktree" "$([ "$dirty" = 0 ] && echo bersih || echo "$dirty file berubah")"
else
  row "git" "bukan repository git"
fi
for f in "$AL_MANIFEST" "$AL_ACCEPTANCE_MAP" "$AL_POLICY_FILE"; do
  [ -f "$AL_REPO_ROOT/$f" ] && row "$f" "ada" || row "$f" "tidak ada (jalankan: al init)"
done

printf '\n.gitignore safety\n'
gi="$AL_REPO_ROOT/.gitignore"
if [ -f "$gi" ]; then
  for pat in ".env" "$AL_ARTIFACT_DIR" "$AL_LOG_DIR"; do
    if grep -qF -- "$pat" "$gi"; then row "$pat" "ignored"
    else bad "$pat" "belum ada di .gitignore"; fi
  done
else
  bad ".gitignore" "tidak ada"
fi
# Pemeriksaan paling penting: pastikan .env tidak pernah ter-track.
if git -C "$AL_REPO_ROOT" ls-files --error-unmatch .env >/dev/null 2>&1; then
  printf '  %-28s %s\n' ".env tracked" "BAHAYA — .env ada di index git"
  al_err ".env ter-track oleh git. Jalankan: git rm --cached .env"
  fail=1
else
  row ".env tracked" "tidak (benar)"
fi

printf '\nHarness terdeteksi\n'
found=0
for pair in "claude:$AL_CLAUDE_HOME" "codex:$AL_CODEX_HOME" "hermes:$AL_HERMES_HOME" "opencode:$AL_OPENCODE_HOME"; do
  name="${pair%%:*}"; dir="${pair#*:}"
  if [ -d "$dir" ]; then row "$name" "$dir"; found=$((found+1)); fi
done
[ -d "$AL_CURSOR_DIR" ] && { row cursor "$AL_CURSOR_DIR"; found=$((found+1)); }
[ "$found" = 0 ] && row "(tidak ada)" "install akan membuat direktori sesuai kebutuhan"

printf '\n'
if [ "$fail" = 0 ]; then al_ok "doctor: ok"; else al_err "doctor: ada masalah wajib di atas"; fi
exit "$fail"
