#!/usr/bin/env bash
# al metrics: hitung ulang dari artifact + event. Tidak ada target yang ditebak.
. "${BASH_SOURCE[0]%/*}/lib.sh"

R="$(new_repo m)"
met() { ( cd "$1" && AL_HOME="$AL" "$AL/bin/al" metrics "${@:2}" ); }

# Tanpa data, metrics tidak boleh mengarang nol yang tampak seperti pengukuran.
E="$(new_dir empty)"; git -C "$E" init -q
assert_eq "tanpa artifact -> 2" 2 "$(rc_of met "$E")"
assert_contains "menyebut cara mengisi data" "$(out_of met "$E")" "al run"

# new_repo sudah menjalankan satu smoke run untuk meng-commit lockfile, jadi
# hitungan dibandingkan secara relatif terhadap baseline, bukan diasumsikan nol.
base_runs=$(met "$R" --json | jq -r .runs)
base_pass=$(met "$R" --json | jq -r .pass)
al_in "$R" run standard >/dev/null 2>&1 || true
assert_eq "dengan data -> 0" 0 "$(rc_of met "$R")"
j=$(met "$R" --json)
assert "output --json valid" bash -c 'printf %s "$1" | jq -e . >/dev/null' _ "$j"
assert_eq "runs bertambah satu" $((base_runs+1)) "$(printf %s "$j" | jq -r .runs)"
assert_eq "PASS bertambah satu" $((base_pass+1)) "$(printf %s "$j" | jq -r .pass)"
assert_eq "profile standard tercatat" 1 "$(printf %s "$j" | jq -r '.by_profile.standard')"
assert_eq "tier low = semua run" "$(printf %s "$j" | jq -r .runs)" \
  "$(printf %s "$j" | jq -r '.by_tier.low')"

# unknown_rate adalah metrik utama: ia mengukur apakah infra dapat dipercaya,
# bukan apakah kode benar.
assert_eq "unknown_rate 0 saat semua PASS" 0 "$(printf %s "$j" | jq -r .unknown_rate)"
printf '#!/usr/bin/env bash\nexit 1\n' > "$R/scripts/evidence/test.sh"
AL_STRICT_WORKTREE=0 al_in "$R" run smoke >/dev/null 2>&1 || true
git -C "$R" checkout -- scripts/evidence/test.sh
mv "$R/scripts/evidence/build.sh" "$TEST_TMP/b.bak"
AL_STRICT_WORKTREE=0 al_in "$R" run standard >/dev/null 2>&1 || true
mv "$TEST_TMP/b.bak" "$R/scripts/evidence/build.sh"
j=$(met "$R" --json)
assert_eq "FAIL terhitung"    1 "$(printf %s "$j" | jq -r .fail)"
assert_eq "UNKNOWN terhitung" 1 "$(printf %s "$j" | jq -r .unknown)"
# Diturunkan dari data, bukan dihardcode: rate harus konsisten dengan runs.
runs=$(printf %s "$j" | jq -r .runs)
assert_eq "unknown_rate = unknown/runs" "$((100 / runs))" \
  "$(printf %s "$j" | jq -r .unknown_rate)"
assert "flag teratas dilaporkan" bash -c \
  'printf %s "$1" | jq -e ".top_flags|length > 0" >/dev/null' _ "$j"

# Event log opsional, tetapi ikut kalau ada.
al_in "$R" event merge actor=human pr_number=1 >/dev/null 2>&1
j=$(met "$R" --json)
assert_eq "event dihitung per tipe" 1 "$(printf %s "$j" | jq -r '.events.merge')"

out=$(met "$R")
assert_contains "teks menyebut Evidence runs" "$out" "Evidence runs"
assert_contains "teks menyatakan belum ada target" "$out" "belum ada target"
refute_contains "tidak ada target dikarang" "$out" "%  target"

test_summary
