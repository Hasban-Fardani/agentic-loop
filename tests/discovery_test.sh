#!/usr/bin/env bash
# al discovery: yang diperbaiki adalah paksaan untuk mencari, bukan daya cari.
# Riset ke serena/codegraph/understand-anything: tidak satu pun menjawab
# "apakah sudah ada kode yang fungsinya sama". Jadi gate ini menuntut artifact,
# dan tidak boleh mengklaim kepastian yang tidak dimilikinya.
. "${BASH_SOURCE[0]%/*}/lib.sh"

dc() { local d="$1"; shift; ( cd "$d" && AL_HOME="$AL" "$AL/bin/al" discovery "$@" ); }
fill() { # fill REPO — isi record seperti agent yang benar-benar memeriksa
  python3 - "$1/.agent/discovery/TASK-000.md" <<'PY'
import sys
p=sys.argv[1]; t=open(p).read()
t=t.replace("- \n- \n", "- `src/report.js:1` — ada tapi tanpa filter tanggal\n- `src/legacy.js:9` — format beda\n")
t=t.replace("## Conclusion\n<!-- reuse | extend | no-suitable-reuse -->\n", "## Conclusion\nextend\n")
open(p,"w").write(t)
PY
}

R="$(new_repo dc)"
mkdir -p "$R/src"
printf 'export function downloadReport(id){ return id; }\n' > "$R/src/report.js"
git -C "$R" add -A >/dev/null 2>&1
git -C "$R" commit -q -m src

echo "# tanpa record, tidak ada yang terbukti"
assert_eq "record hilang -> 2 (UNKNOWN)" 2 "$(rc_of dc "$R" verify)"
assert_contains "menyebut cara memulai" "$(out_of dc "$R" verify)" "al discovery start"

echo "# start membangun record dari pencarian nyata"
assert_eq "start -> 0" 0 "$(rc_of dc "$R" start --query "report download")"
REC="$R/.agent/discovery/TASK-000.md"
assert "record dibuat" test -f "$REC"
assert_contains "mencatat command git grep"  "$(cat "$REC")" "git grep"
assert_contains "mencatat token split"        "$(cat "$REC")" "token split"
assert_contains "mencatat pencarian riwayat"  "$(cat "$REC")" "git log -S"
# Recall berlapis: query "report download" harus menemukan downloadReport lewat
# token, meski nama fungsinya tidak sama persis dengan query.
assert_contains "token menemukan nama yang berbeda susunan" "$(cat "$REC")" "src/report.js"
assert_contains "mencatat commit sebagai bukti" "$(cat "$REC")" "commit:"

echo "# template yang belum diisi WAJIB gagal"
# Regresi: filter komentar per-baris membuat teks instruksi multi-baris lolos
# sebagai "sudah dijustifikasi", sehingga record kosong dinyatakan lengkap.
assert_eq "record kosong -> 1" 1 "$(rc_of dc "$R" verify)"
out=$(out_of dc "$R" verify)
assert_contains "menuntut kandidat diperiksa" "$out" "kandidat diperiksa"
assert_contains "menuntut Conclusion"         "$out" "Conclusion harus"

echo "# record terisi lulus"
fill "$R"
assert_eq "record lengkap -> 0" 0 "$(rc_of dc "$R" verify)"
out=$(out_of dc "$R" verify)
assert_contains "melaporkan kesimpulan"  "$out" "extend"
# Label confidence wajib ada: fallback command TIDAK membuktikan tidak ada kode
# serupa, hanya bahwa pencarian yang terdaftar tidak menemukannya.
assert_contains "melaporkan kelas confidence" "$out" "command-fallback"
assert_contains "record menyatakan batas klaimnya" \
  "$(cat "$REC")" "TIDAK membuktikan"

echo "# conclusion tak valid ditolak"
python3 - "$REC" <<'PY'
import sys
p=sys.argv[1]; t=open(p).read()
open(p,"w").write(t.replace("## Conclusion\nextend", "## Conclusion\nsudah dicek kok"))
PY
assert_eq "conclusion sembarang -> 1" 1 "$(rc_of dc "$R" verify)"

echo "# confidence tak valid ditolak"
fill "$R"
python3 - "$REC" <<'PY'
import sys
p=sys.argv[1]; t=open(p).read()
open(p,"w").write(t.replace("command-fallback", "sangat yakin"))
PY
assert_eq "confidence sembarang -> 1" 1 "$(rc_of dc "$R" verify)"

echo "# justifikasi eksplisit adalah jalan keluar yang sah"
rm -f "$REC"
dc "$R" start --query "sesuatu yang benar-benar baru" >/dev/null 2>&1
python3 - "$REC" <<'PY'
import sys
p=sys.argv[1]; t=open(p).read()
t=t.replace("- \n- \n", "- tidak ada kandidat: dicari 3 istilah, semua nol hasil\n")
t=t.replace("## Conclusion\n<!-- reuse | extend | no-suitable-reuse -->\n", "## Conclusion\nno-suitable-reuse\n")
open(p,"w").write(t)
PY
assert_eq "justifikasi tanpa kandidat -> 0" 0 "$(rc_of dc "$R" verify)"

echo "# task terpisah, dry-run, permukaan"
assert_eq "task lain masih 2" 2 "$(rc_of dc "$R" verify --task TASK-999)"
assert_eq "start butuh --query" 1 "$(rc_of dc "$R" start)"
AL_DRY_RUN=1 dc "$R" start --task TASK-DRY --query x >/dev/null 2>&1
refute "AL_DRY_RUN tidak menulis record" test -f "$R/.agent/discovery/TASK-DRY.md"
assert_eq "show menampilkan record" 0 "$(rc_of dc "$R" show)"
assert_eq "action tak dikenal ditolak" 1 "$(rc_of dc "$R" bogus)"

test_summary
