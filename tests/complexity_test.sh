#!/usr/bin/env bash
# al complexity: mengukur, bukan menasihati. Penilaian "over-engineered" adalah
# pekerjaan skill ponytail (upstream, prosa). Di sini hanya angka terukur yang
# tidak bisa didebat oleh model yang menulis kodenya.
. "${BASH_SOURCE[0]%/*}/lib.sh"

# Stub lizard: kontrak yang kita andalkan hanya `-C n --warnings_only` -> exit 1
# saat ada breach. Distub supaya suite tidak bergantung pada tool opsional.
STUB="$TEST_TMP/lizard-stub"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
# Meniru lizard: laporkan warning untuk file bernama *messy*, exit 1.
found=0
for a in "$@"; do
  case "$a" in
    -*) continue ;;
    *messy*) printf '%s:1: warning: messy has 17 NLOC, 15 CCN, 162 token, 1 PARAM, 17 length, 0 ND\n' "$a"; found=1 ;;
  esac
done
exit "$found"
EOF
chmod +x "$STUB"

cx() { local d="$1"; shift; ( cd "$d" && AL_HOME="$AL" "$AL/bin/al" complexity "$@" ); }

R="$(new_repo cx)"
mkdir -p "$R/src"

echo "# degradasi saat engine absen"
# Pembedaan yang menentukan: optional mengumumkan no_op, required menolak
# menebak. Tidak ada jalur yang mengubah "tak terukur" menjadi "lulus".
assert_eq "required + absent -> 2 (UNKNOWN)" 2 \
  "$(AL_COMPLEXITY_MODE=required AL_LIZARD_COMMAND=- rc_of cx "$R" check)"
out=$(AL_COMPLEXITY_MODE=required AL_LIZARD_COMMAND=- out_of cx "$R" check)
assert_contains "required menyebut cara memasang" "$out" "pipx install lizard"
assert_eq "optional + absent -> 0" 0 \
  "$(AL_COMPLEXITY_MODE=optional AL_LIZARD_COMMAND=- rc_of cx "$R" check)"
out=$(AL_COMPLEXITY_MODE=optional AL_LIZARD_COMMAND=- out_of cx "$R" check)
assert_contains "optional menandai no_op eksplisit" "$out" "COMPLEXITY_TOOL_UNAVAILABLE"
refute_contains "optional tidak mengaku pass"      "$out" "complexity: pass"
assert_eq "off -> 0 tanpa mengukur" 0 "$(AL_COMPLEXITY_MODE=off rc_of cx "$R" check)"
assert_contains "off dinyatakan sebagai no_op" \
  "$(AL_COMPLEXITY_MODE=off out_of cx "$R" check)" "no_op"

echo "# cakupan: hanya file berubah, hanya bahasa yang benar-benar diurai"
printf 'echo hi\n' > "$R/script.sh"
out=$(AL_LIZARD_COMMAND="$STUB" out_of cx "$R" check)
assert_contains "bash bukan 'sederhana' tapi tidak terukur" "$out" "no_op"
refute_contains "tidak mengklaim pass untuk bahasa tak didukung" "$out" "complexity: pass"
rm -f "$R/script.sh"

echo "# status candidate melaporkan, tidak memblokir"
# Angka 10/15 adalah hipotesis; gaya fluent bisa menaikkan CCN tanpa kode
# benar-benar sulit dibaca. Jadi threshold baru mengikat setelah divalidasi.
printf 'export function messy(a){ return a; }\n' > "$R/src/messy.js"
assert_eq "candidate + breach -> 0" 0 "$(AL_LIZARD_COMMAND="$STUB" rc_of cx "$R" check)"
out=$(AL_LIZARD_COMMAND="$STUB" out_of cx "$R" check)
assert_contains "temuan tetap dilaporkan"     "$out" "messy"
assert_contains "menyatakan tidak memblokir"  "$out" "TIDAK memblokir"
assert_contains "menyebut cara mengikatnya"   "$out" "status: approved"

echo "# status approved memblokir"
sed -i.bak 's/^status: candidate/status: approved/' "$R/.agent/complexity.yaml"
rm -f "$R/.agent"/*.bak
assert_eq "approved + breach -> 1" 1 "$(AL_LIZARD_COMMAND="$STUB" rc_of cx "$R" check)"
out=$(AL_LIZARD_COMMAND="$STUB" out_of cx "$R" check)
assert_contains "menyebut fungsi yang melewati budget" "$out" "melewati budget"

echo "# pengecualian butuh entri eksplisit"
cat >> "$R/.agent/complexity.yaml" <<'YAML'
YAML
python3 - "$R/.agent/complexity.yaml" <<'PY'
import sys
p=sys.argv[1]; t=open(p).read()
t=t.replace("exceptions: []", """exceptions:
  - function: messy
    reason: "legacy dispatch"
    owner: hasban
    review_date: 2026-11-01""")
open(p,"w").write(t)
PY
assert_eq "fungsi ber-pengecualian -> 0" 0 "$(AL_LIZARD_COMMAND="$STUB" rc_of cx "$R" check)"
out=$(AL_LIZARD_COMMAND="$STUB" out_of cx "$R" check)
assert_contains "pengecualian dilaporkan, bukan disembunyikan" "$out" "excused messy"

echo "# file bersih lulus"
rm -f "$R/src/messy.js"
printf 'export function ok(){ return 1; }\n' > "$R/src/ok.js"
assert_eq "tanpa breach -> 0" 0 "$(AL_LIZARD_COMMAND="$STUB" rc_of cx "$R" check)"

echo "# permukaan"
assert_eq "show selalu 0" 0 "$(rc_of cx "$R" show)"
assert_contains "show menampilkan budget" "$(out_of cx "$R" show)" "max_ccn"
assert_eq "mode tak dikenal ditolak" 1 "$(AL_COMPLEXITY_MODE=bogus rc_of cx "$R" check)"
assert_eq "action tak dikenal ditolak" 1 "$(rc_of cx "$R" bogus)"
assert "template complexity.yaml dipasang al init" test -f "$R/.agent/complexity.yaml"
assert "template menyatakan angka itu hipotesis" \
  grep -qi "HIPOTESIS" "$AL/core/templates/complexity.yaml"

test_summary
