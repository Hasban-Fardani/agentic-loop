#!/usr/bin/env bash
# al complexity — ukur kompleksitas, bukan menasihati soal kesederhanaan.
#
# Pembagian kerja yang disengaja:
#   - Penilaian "ini over-engineered" adalah pekerjaan skill ponytail (upstream).
#     Itu prosa/heuristik dan memang tepat dikerjakan model.
#   - Command ini hanya melaporkan angka terukur: CCN, panjang fungsi, jumlah
#     parameter. Angka tidak bisa didebat oleh model yang menulis kodenya.
#
# Engine: lizard (terryyin/lizard). Diverifikasi: `-C n --warnings_only`
# mengembalikan exit 1 saat ada fungsi melewati threshold, 0 saat bersih.
#
# Exit: 0 dalam budget (atau no_op yang dideklarasikan), 1 melewati budget,
#       2 tidak dapat dibuktikan (engine wajib tapi absen).
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"
. "${BASH_SOURCE[0]%/*}/../lib/optional.sh"

ACTION="${1:-check}"
CFG="$AL_REPO_ROOT/$AL_COMPLEXITY_FILE"

# Budget dari file bila ada, kalau tidak dari env/default. File menang atas
# default tetapi tidak atas environment, sama seperti cascade lainnya.
if [ -f "$CFG" ]; then
  _s=$(al_yaml_scalar "$CFG" status);      [ -n "$_s" ] && AL_COMPLEXITY_STATUS="$_s"
  _m=$(al_yaml_scalar "$CFG" mode);        [ -n "$_m" ] && al_set_default AL_COMPLEXITY_MODE "$_m"
  _c=$(al_yaml_scalar "$CFG" max_ccn);     [ -n "$_c" ] && al_set_default AL_MAX_CCN "$_c"
  _l=$(al_yaml_scalar "$CFG" max_function_lines); [ -n "$_l" ] && al_set_default AL_MAX_FUNCTION_LINES "$_l"
  _a=$(al_yaml_scalar "$CFG" max_params);  [ -n "$_a" ] && al_set_default AL_MAX_PARAMS "$_a"
fi
: "${AL_COMPLEXITY_STATUS:=candidate}"

if [ "$ACTION" = show ]; then
  printf 'status:   %s\n' "$AL_COMPLEXITY_STATUS"
  printf 'mode:     %s\n' "$AL_COMPLEXITY_MODE"
  printf 'engine:   lizard (%s)\n' "$(al_tool_state lizard)"
  printf 'max_ccn:  %s\n' "$AL_MAX_CCN"
  printf 'max_lines: %s\n' "$AL_MAX_FUNCTION_LINES"
  printf 'max_params: %s\n' "$AL_MAX_PARAMS"
  exit 0
fi
[ "$ACTION" = check ] || al_die "usage: al complexity [check|show]"

case "$AL_COMPLEXITY_MODE" in
  off)
    printf 'complexity: no_op (AL_COMPLEXITY_MODE=off)\n'
    exit 0 ;;
  optional|required) : ;;
  *) al_die "AL_COMPLEXITY_MODE harus off|optional|required, dapat: $AL_COMPLEXITY_MODE" ;;
esac

if ! LIZARD="$(al_have_lizard)"; then
  # Perbedaan yang menentukan: optional mengumumkan no_op, required menolak
  # menebak. Tidak ada jalur yang mengubah "tak terukur" menjadi "lulus".
  if [ "$AL_COMPLEXITY_MODE" = required ]; then
    printf 'complexity: engine tidak tersedia — hasil tidak dapat dibuktikan\n' >&2
    printf 'complexity: pasang dengan `pipx install lizard`, atau set AL_LIZARD_COMMAND\n' >&2
    exit 2
  fi
  printf 'complexity: no_op COMPLEXITY_TOOL_UNAVAILABLE (lizard absen, mode=optional)\n'
  printf 'complexity: pasang `pipx install lizard` untuk mengaktifkan gate ini\n'
  exit 0
fi

# Cakupan: hanya file yang diubah branch ini. Mengukur seluruh repo akan
# menghukum utang lama yang bukan tanggung jawab PR ini.
BASE="${AL_BASE_REF:-${BASE_REF:-}}"
if [ -z "$BASE" ]; then
  BASE=$(git -C "$AL_REPO_ROOT" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || true)
fi
if [ -z "$BASE" ]; then
  for cand in "$AL_GIT_REMOTE/$AL_PROTECTED_BRANCH" "$AL_PROTECTED_BRANCH"; do
    git -C "$AL_REPO_ROOT" rev-parse --verify -q "$cand" >/dev/null 2>&1 && { BASE="$cand"; break; }
  done
fi

changed=""
if [ -n "$BASE" ]; then
  changed=$(git -C "$AL_REPO_ROOT" diff --name-only "$BASE"...HEAD 2>/dev/null || true)
fi
changed="$changed
$(git -C "$AL_REPO_ROOT" status --porcelain -uall 2>/dev/null | sed 's/^...//')"
# `|| true` wajib: grep exit 1 saat kosong, dan di bawah set -e itu mematikan
# script sebelum cabang "tidak ada file" berjalan.
changed=$(printf '%s\n' "$changed" | grep -v '^$' | sort -u || true)

# Hanya ekstensi yang benar-benar diurai lizard. Bash tidak didukung — itu
# "tidak terukur", bukan "sederhana".
supported='\.(c|cc|cpp|cxx|h|hpp|cs|java|js|jsx|mjs|cjs|ts|tsx|py|rb|php|swift|scala|go|lua|rs|kt|kts|m|mm|sol|zig|f90|erl|gd)$'
targets=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$AL_REPO_ROOT/$f" ] || continue     # file terhapus tidak diukur
  printf '%s\n' "$f" | grep -qE "$supported" || continue
  targets="$targets $AL_REPO_ROOT/$f"
done <<EOF
$changed
EOF

if [ -z "$targets" ]; then
  printf 'complexity: no_op (tidak ada file berubah dengan bahasa yang didukung)\n'
  exit 0
fi

n_files=$(printf '%s\n' $targets | grep -c . || true)
printf 'complexity: %s file, budget CCN<=%s lines<=%s params<=%s\n' \
  "$n_files" "$AL_MAX_CCN" "$AL_MAX_FUNCTION_LINES" "$AL_MAX_PARAMS"

set +e
# shellcheck disable=SC2086 # daftar path sengaja di-split
out=$("$LIZARD" -C "$AL_MAX_CCN" -L "$AL_MAX_FUNCTION_LINES" -a "$AL_MAX_PARAMS" \
      --warnings_only $targets 2>&1)
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  printf 'complexity: pass\n'
  exit 0
fi

# Pengecualian per-fungsi, dari config. Setiap entri wajib punya alasan dan
# owner di file; command ini hanya mencocokkan nama, bukan menilai alasannya.
exceptions=""
if [ -f "$CFG" ]; then
  exceptions=$(awk '
    /^exceptions:/ {inb=1; next}
    inb && /^[A-Za-z]/ {inb=0}
    inb && /function:/ {sub(/.*function:[[:space:]]*/,""); sub(/[[:space:]]*#.*/,"")
                        gsub(/^["'"'"']|["'"'"']$/,""); print}
  ' "$CFG")
fi

violations=0; excused=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in *warning:*) : ;; *) continue ;; esac
  fn=$(printf '%s' "$line" | sed -E 's/.*warning: ([^ ]+) has.*/\1/')
  hit=""
  while IFS= read -r ex; do
    [ -n "$ex" ] && [ "$ex" = "$fn" ] && { hit=1; break; }
  done <<EOF
$exceptions
EOF
  if [ -n "$hit" ]; then
    printf 'complexity: excused %s (pengecualian di %s)\n' "$fn" "$AL_COMPLEXITY_FILE"
    excused=$((excused+1))
  else
    printf 'complexity: %s\n' "${line#"$AL_REPO_ROOT"/}"
    violations=$((violations+1))
  fi
done <<EOF
$out
EOF

if [ "$violations" -eq 0 ]; then
  printf 'complexity: pass (%s pengecualian dipakai)\n' "$excused"
  exit 0
fi

# Status candidate berarti threshold belum disetujui owner, jadi temuan
# dilaporkan tetapi tidak memblokir. Angka 10/15 adalah hipotesis awal, bukan
# kebenaran universal — Laravel fluent builder bisa menaikkannya tanpa kode
# benar-benar sulit dibaca.
if [ "$AL_COMPLEXITY_STATUS" != approved ]; then
  printf 'complexity: %s temuan, TIDAK memblokir (status=%s di %s)\n' \
    "$violations" "$AL_COMPLEXITY_STATUS" "$AL_COMPLEXITY_FILE" >&2
  printf 'complexity: set `status: approved` setelah threshold divalidasi ke kode nyata\n' >&2
  exit 0
fi

printf 'complexity: %s fungsi melewati budget\n' "$violations" >&2
printf 'complexity: sederhanakan, atau catat pengecualian beralasan di %s\n' "$AL_COMPLEXITY_FILE" >&2
exit 1
