#!/usr/bin/env bash
# al scope: kontrak path yang ditegakkan mesin, bukan imbauan di prompt.
. "${BASH_SOURCE[0]%/*}/lib.sh"

mk_repo() {
  local d="$TEST_TMP/${1:-s$RANDOM}"
  mkdir -p "$d"
  ( cd "$d"; git init -q; git config user.name t; git config user.email t@example.test
    echo '{}' > package.json
    AL_HOME="$AL" "$AL/bin/al" init >/dev/null 2>&1
    git add -A; git commit -q -m init )
  printf '%s' "$d"
}
scope() { local d="$1"; shift; ( cd "$d" && AL_HOME="$AL" "$AL/bin/al" scope "$@" ); }

R="$(mk_repo ok)"
mkdir -p "$R/src" "$R/tests"; echo x > "$R/src/a.js"; echo y > "$R/tests/a_test.js"
assert_eq "perubahan dalam allowed -> 0" 0 "$(rc_of scope "$R" check)"

# Forbidden mengalahkan allowed: pola luas `src/` tidak boleh membuka `src/auth/`.
mkdir -p "$R/src/auth"; echo s > "$R/src/auth/session.js"
assert_eq "forbidden di dalam allowed -> 1" 1 "$(rc_of scope "$R" check)"
out=$(out_of scope "$R" check)
assert_contains "pelanggaran menyebut file"  "$out" "src/auth/session.js"
assert_contains "pelanggaran menyebut pola" "$out" "src/auth/"
rm -rf "$R/src/auth"

# Regresi: git meringkas direktori untracked jadi satu baris, sehingga file di
# dalamnya tak pernah diperiksa. `-uall` yang mencegah itu.
mkdir -p "$R/migrations"; echo m > "$R/migrations/001.sql"
out=$(out_of scope "$R" check)
assert_contains "file dalam dir untracked ikut diperiksa" "$out" "migrations/001.sql"
rm -rf "$R/migrations"

echo z > "$R/random.txt"
out=$(out_of scope "$R" check)
assert_contains "file di luar allowed ditandai" "$out" "OUT-OF-SCOPE"
assert_eq "out-of-scope -> 1" 1 "$(rc_of scope "$R" check)"
rm -f "$R/random.txt"

# Allowed kosong = tidak dibatasi, tetapi forbidden tetap berlaku.
U="$(mk_repo unbounded)"
cat > "$U/.agent/scope.yaml" <<'YAML'
task_id: TASK-U
allowed:
forbidden:
  - "secrets/"
YAML
echo a > "$U/anything.txt"
assert_eq "allowed kosong tidak membatasi" 0 "$(rc_of scope "$U" check)"
mkdir -p "$U/secrets"; echo s > "$U/secrets/k.txt"
assert_eq "forbidden tetap berlaku saat allowed kosong" 1 "$(rc_of scope "$U" check)"

# Scope hilang bukan berarti bebas: tak ada kontrak = tak ada yang terbukti.
N="$(mk_repo noscope)"; rm -f "$N/.agent/scope.yaml"
assert_eq "scope hilang -> 2 (UNKNOWN)" 2 "$(rc_of scope "$N" check)"
assert_contains "menyebut cara memperbaiki" "$(out_of scope "$N" check)" "scope.yaml"

# Tanpa perubahan, tak ada yang bisa dilanggar.
C="$(mk_repo clean2)"
assert_eq "tanpa perubahan -> 0" 0 "$(rc_of scope "$C" check)"

out=$(out_of scope "$R" show)
assert_contains "show menampilkan task_id" "$out" "TASK-"
assert_contains "show menampilkan allowed" "$out" "allowed:"
assert_eq "show selalu 0" 0 "$(rc_of scope "$R" show)"
assert_eq "action tak dikenal ditolak" 1 "$(rc_of scope "$R" bogus)"

test_summary
