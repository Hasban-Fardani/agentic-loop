#!/usr/bin/env bash
# Test runner. `al selftest` memanggil ini.
#
#   tests/run.sh              semua file *_test.sh
#   tests/run.sh scan config  hanya yang namanya cocok
#
# Exit: 0 semua lulus, 1 ada yang gagal.
set -Eeuo pipefail

cd "${BASH_SOURCE[0]%/*}"
AL_HOME="$(cd .. && pwd)"

# Tanpa jq atau git, hampir semua test tidak bermakna. Gagal cepat dan jelas
# daripada melaporkan kegagalan palsu di puluhan assert.
for bin in git jq bash; do
  command -v "$bin" >/dev/null 2>&1 || { printf 'butuh %s\n' "$bin" >&2; exit 2; }
done

files=""
if [ $# -gt 0 ]; then
  for pat in "$@"; do
    for f in *"$pat"*_test.sh; do [ -f "$f" ] && files="$files $f"; done
  done
  [ -n "$files" ] || { printf 'tidak ada test cocok: %s\n' "$*" >&2; exit 2; }
else
  files=$(printf '%s\n' *_test.sh)
fi

use_color=0; [ -t 1 ] && use_color=1
red(){ [ "$use_color" = 1 ] && printf '\033[31m%s\033[0m' "$1" || printf '%s' "$1"; }
grn(){ [ "$use_color" = 1 ] && printf '\033[32m%s\033[0m' "$1" || printf '%s' "$1"; }

total_pass=0; total_fail=0; total_skip=0; failed_files=""
start=$(date +%s)

for f in $files; do
  [ -f "$f" ] || continue
  printf '\n== %s\n' "$f"
  set +e
  # Path absolut: `${BASH_SOURCE[0]%/*}` di dalam file test tidak memotong apa
  # pun bila argumennya nama telanjang, sehingga `. lib.sh` gagal.
  out=$(AL_HOME="$AL_HOME" bash "$PWD/$f" 2>&1); rc=$?
  set -e
  # Tampilkan kegagalan verbatim; keberhasilan diringkas supaya output terbaca.
  printf '%s\n' "$out" | grep -E '^(not ok|skip)' || true
  # Ringkasan selalu baris `# <file>: pass=…`; heading seperti `# CLI surface`
  # di dalam file test tidak boleh salah dibaca sebagai ringkasan.
  line=$(printf '%s\n' "$out" | grep -E '^# .*pass=' | tail -1)
  printf '%s\n' "${line:-# (tidak ada ringkasan)}"
  p=$(printf '%s' "$line" | sed -n 's/.*pass=\([0-9]*\).*/\1/p'); : "${p:=0}"
  fl=$(printf '%s' "$line" | sed -n 's/.*fail=\([0-9]*\).*/\1/p'); : "${fl:=0}"
  sk=$(printf '%s' "$line" | sed -n 's/.*skip=\([0-9]*\).*/\1/p'); : "${sk:=0}"
  total_pass=$((total_pass+p)); total_fail=$((total_fail+fl)); total_skip=$((total_skip+sk))
  if [ "$rc" -ne 0 ]; then
    failed_files="$failed_files $f"
    # rc != 0 tanpa fail tercatat berarti file mati sebelum meringkas — itu
    # kegagalan tersendiri, jangan dihitung nol.
    [ "$fl" -eq 0 ] && { total_fail=$((total_fail+1)); printf 'not ok %s -- keluar rc=%d tanpa ringkasan\n' "$f" "$rc"; }
  fi
done

printf '\n----------------------------------------\n'
printf 'pass=%d fail=%d skip=%d in %ds\n' \
  "$total_pass" "$total_fail" "$total_skip" "$(( $(date +%s) - start ))"

if [ "$total_fail" -eq 0 ]; then
  printf '%s\n' "$(grn 'SUITE OK')"
  exit 0
fi
printf '%s%s\n' "$(red 'SUITE FAILED:')" "$failed_files"
exit 1
