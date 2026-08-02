#!/usr/bin/env bash
# al scope — tegakkan Allowed/Forbidden paths dari task secara mekanis.
#
# Prinsip PRD #2: scope adalah kontrak, bukan imbauan. Sebuah role yang
# "sebaiknya tidak" menyentuh sesuatu akan menyentuhnya; yang menahan adalah
# pemeriksaan yang gagal, bukan kalimat di dalam prompt.
#
#   al scope check          bandingkan diff terhadap base dengan scope task
#   al scope show           tampilkan scope efektif
#
# Exit: 0 dalam scope, 1 ada pelanggaran, 2 scope tidak dapat dibuktikan.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"
al_need git || exit 2

SCOPE_FILE="$AL_REPO_ROOT/$AL_SCOPE_FILE"
ACTION="${1:-check}"

# Scope hilang bukan berarti bebas. Tanpa kontrak, tidak ada yang bisa
# dibuktikan — itu UNKNOWN, sama seperti evidence tanpa artifact.
[ -f "$SCOPE_FILE" ] || {
  al_err "scope tidak ada: $AL_AGENT_DIR/scope.yaml"
  al_info "buat dari template: al init, lalu isi allowed/forbidden dari Issue"
  exit 2
}

# ponytail: pembaca list YAML rata (`- pola` di bawah satu key). Cukup untuk
# scope; kalau butuh nested/anchor, pindah ke yq — jangan besarkan awk ini.
yaml_list() { # yaml_list KEY
  awk -v k="^$1:" '
    $0 ~ k {inb=1; next}
    inb && /^[A-Za-z]/ {inb=0}
    inb && /^[[:space:]]*-[[:space:]]*/ {
      sub(/^[[:space:]]*-[[:space:]]*/,""); sub(/[[:space:]]*#.*/,"")
      gsub(/^["'"'"']|["'"'"']$/,""); if (length($0)) print
    }
  ' "$SCOPE_FILE"
}

ALLOWED="$(yaml_list allowed)"
FORBIDDEN="$(yaml_list forbidden)"
TASK="$(al_yaml_scalar "$SCOPE_FILE" task_id)"
BASE="${AL_BASE_REF:-${BASE_REF:-}}"

if [ "$ACTION" = show ]; then
  printf 'task_id: %s\nbase: %s\n\nallowed:\n' "${TASK:-<unset>}" "${BASE:-auto}"
  printf '%s\n' "$ALLOWED" | sed 's/^/  - /'
  printf '\nforbidden:\n'
  [ -n "$FORBIDDEN" ] && printf '%s\n' "$FORBIDDEN" | sed 's/^/  - /' || printf '  (none)\n'
  exit 0
fi

[ "$ACTION" = check ] || al_die "usage: al scope [check|show]"

# Base ref: eksplisit menang, lalu upstream, lalu default branch. Kalau tidak
# ada yang bisa diselesaikan, kita tidak tahu apa yang "berubah" — exit 2.
if [ -z "$BASE" ]; then
  BASE=$(git -C "$AL_REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
fi
if [ -z "$BASE" ]; then
  for cand in "$AL_GIT_REMOTE/$AL_PROTECTED_BRANCH" "$AL_PROTECTED_BRANCH"; do
    git -C "$AL_REPO_ROOT" rev-parse --verify -q "$cand" >/dev/null 2>&1 && { BASE="$cand"; break; }
  done
fi
[ -n "$BASE" ] || { al_err "base ref tidak dapat ditentukan; set AL_BASE_REF"; exit 2; }

# Diff tiga-titik: hanya yang branch ini ubah, bukan yang base maju sendiri.
changed=$(git -C "$AL_REPO_ROOT" diff --name-only "$BASE"...HEAD 2>/dev/null) || {
  al_err "gagal diff terhadap $BASE"; exit 2; }
# Perubahan belum ter-commit juga dihitung: agent bisa saja belum commit.
# `-uall` wajib — tanpa itu git meringkas direktori untracked menjadi satu baris
# (`src/`), sehingga `src/auth/session.js` tidak pernah diperiksa terhadap
# aturan forbidden dan pelanggaran lolos.
changed="$changed
$(git -C "$AL_REPO_ROOT" status --porcelain -uall 2>/dev/null | sed 's/^...//')"
# `|| true` wajib: grep mengembalikan 1 saat tidak ada baris tersisa, dan di
# bawah `set -e` itu membunuh script sebelum cabang "tidak ada perubahan"
# sempat berjalan — gate lolos tanpa pesan apa pun.
changed=$(printf '%s\n' "$changed" | grep -v '^$' | sort -u || true)

[ -n "$changed" ] || { al_ok "scope: tidak ada perubahan"; exit 0; }

# Cocokkan pola gaya gitignore: prefiks direktori atau glob.
matches() { # matches PATH PATTERN
  case "$2" in
    */) case "$1" in "$2"*) return 0 ;; esac ;;
    *)  case "$1" in $2) return 0 ;; esac
        # `src/api` juga mencakup `src/api/handler.go`
        case "$1" in "$2"/*) return 0 ;; esac ;;
  esac
  return 1
}

violations=0
while IFS= read -r file; do
  [ -n "$file" ] || continue

  # Forbidden dievaluasi lebih dulu dan mengalahkan allowed: sebuah pola luas
  # seperti `src/**` tidak boleh diam-diam membuka `src/auth/`.
  hit=""
  while IFS= read -r pat; do
    [ -n "$pat" ] && matches "$file" "$pat" && { hit="$pat"; break; }
  done <<EOF
$FORBIDDEN
EOF
  if [ -n "$hit" ]; then
    printf 'scope: FORBIDDEN %s (pola: %s)\n' "$file" "$hit"
    violations=$((violations+1)); continue
  fi

  if [ -z "$ALLOWED" ]; then continue; fi   # allowed kosong = tak dibatasi
  ok=""
  while IFS= read -r pat; do
    [ -n "$pat" ] && matches "$file" "$pat" && { ok=1; break; }
  done <<EOF
$ALLOWED
EOF
  [ -n "$ok" ] || { printf 'scope: OUT-OF-SCOPE %s\n' "$file"; violations=$((violations+1)); }
done <<EOF
$changed
EOF

n=$(printf '%s\n' "$changed" | grep -c '')
if [ "$violations" -eq 0 ]; then
  al_ok "scope: $n file, semua dalam scope${TASK:+ ($TASK)}"
  exit 0
fi
al_err "scope: $violations pelanggaran dari $n file${TASK:+ ($TASK)}"
al_info "perluas $AL_AGENT_DIR/scope.yaml lewat review, jangan diam-diam"
exit 1
