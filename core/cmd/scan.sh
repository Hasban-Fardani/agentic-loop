#!/usr/bin/env bash
# al scan — scanner secret/PII yang tidak pernah mencetak nilai temuan.
#
# Exit: 0 bersih, 1 ada temuan, 2 tidak dapat dibuktikan (tool hilang) -> UNKNOWN.
# Pola dari AL_SECRET_PATTERN / AL_PII_PATTERN; scope dari argumen atau AL_REPO_ROOT.
set -Eeuo pipefail

# Gate SEBELUM source: bootstrap sendiri butuh sed/grep untuk redaksi, jadi
# PATH yang rusak harus jadi exit 2 (UNKNOWN) di sini, bukan 127 dari dalam lib.
# `command -v` adalah builtin, jadi pemeriksaan ini tetap sahih tanpa PATH.
for _b in grep find sed; do
  command -v "$_b" >/dev/null 2>&1 || {
    printf 'scan: tool %s tidak tersedia — hasil tidak dapat dibuktikan\n' "$_b" >&2
    exit 2
  }
done

. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"

SCOPE="${1:-${AL_SCAN_SCOPE:-$AL_REPO_ROOT}}"
[ -e "$SCOPE" ] || al_die "scope tidak ada: $SCOPE"

findings=0
report() { # report LABEL FILE LINE — lokasi saja, nilai TIDAK dicetak
  printf 'scan: %s finding at %s:%s [value withheld]\n' "$1" "$(al_repo_rel "$2")" "$3"
}

scan_pattern() {
  label="$1"; pat="$2"; allow="${3:-}"
  [ -n "$pat" ] || return 0
  while IFS= read -r f; do
    case "$f" in
      *"/.git/"*) continue ;;
    esac
    # AL_SCAN_EXCLUDE adalah daftar dipisah '|'
    skip=0
    _IFS="$IFS"; IFS='|'
    for ex in $AL_SCAN_EXCLUDE; do
      [ -n "$ex" ] || continue
      case "$f" in *"/$ex/"*|*"/$ex") skip=1; break ;; esac
    done
    IFS="$_IFS"
    [ "$skip" = 1 ] && continue

    # Baca nomor baris DAN isinya, supaya allowlist dapat diterapkan per baris.
    # Isi baris tidak pernah dicetak — hanya dipakai untuk mencocokkan allowlist.
    while IFS=: read -r ln content; do
      [ -n "$ln" ] || continue
      if [ -n "$allow" ] && printf '%s' "$content" | LC_ALL=C grep -qE "$allow"; then
        continue
      fi
      report "$label" "$f" "$ln"
      findings=1
    done <<EOF
$(LC_ALL=C grep -nE "$pat" "$f" 2>/dev/null)
EOF
    # -size -1024k, bukan -1M: find membulatkan ke atas per unit, jadi `-1M`
    # berarti "< 1 blok 1M" = 0 dan tidak pernah match.
  done <<EOF
$(find "$SCOPE" -type f -size -"${AL_SCAN_MAX_FILE_KB}"k 2>/dev/null)
EOF
}

scan_pattern secret "$AL_SECRET_PATTERN"
scan_pattern pii    "$AL_PII_PATTERN" "$AL_PII_ALLOW"

# Allowlist berbasis path untuk repo yang memang menyimpan fixture sintetis
# guna menguji scanner ini. Hanya berlaku bila TIDAK ada temuan di luar fixture.
if [ "$findings" -ne 0 ] && [ "$AL_ALLOW_FIXTURE_SECRETS" = 1 ]; then
  # Gabungkan pola dengan aman: pola kosong menghasilkan "empty (sub)expression"
  # pada grep, yang dulu membuat daftar `outside` kosong dan allowlist lolos
  # untuk kebocoran nyata. Fail closed bila tak ada pola sama sekali.
  combined=''
  for pat in "$AL_SECRET_PATTERN" "$AL_PII_PATTERN"; do
    [ -n "$pat" ] || continue
    combined="${combined:+$combined|}$pat"
  done
  if [ -z "$combined" ]; then
    printf 'scan: tidak ada pola aktif; allowlist tidak diterapkan\n'
  else
    outside=$(LC_ALL=C grep -rlE "$combined" "$SCOPE" 2>/dev/null \
      | grep -v "/$AL_FIXTURE_DIR/" \
      | grep -v '/\.git/' \
      | grep -v "/$AL_ARTIFACT_DIR/" \
      | grep -v "/$AL_LOG_DIR/" || true)
    if [ -z "$outside" ]; then
      printf 'scan: hanya temuan sintetis di %s/, di-allowlist (AL_ALLOW_FIXTURE_SECRETS=1)\n' "$AL_FIXTURE_DIR"
      findings=0
    else
      printf 'scan: allowlist TIDAK berlaku — ada temuan di luar %s/\n' "$AL_FIXTURE_DIR"
    fi
  fi
fi

[ "$findings" -eq 0 ] && printf 'scan: pass\n'
exit "$findings"
