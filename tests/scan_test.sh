#!/usr/bin/env bash
# Scanner: tri-state, tidak pernah mencetak nilai, allowlist berbatas.
. "${BASH_SOURCE[0]%/*}/lib.sh"

D="$(new_dir pii)"
one() { printf '%s\n' "$2" > "$D/$1"; }
# Alamat dirakit saat runtime, sama seperti FAKE_GH: file test ini sendiri harus
# lolos `al scan`, kalau tidak repo ini tidak bisa membuktikan dirinya bersih.
AT='@'
# Satu baris per file supaya verdict per kasus tidak ambigu.
one gmail.txt  "reach me at real1${AT}gmail.com"
one digit.txt  "digit${AT}foo.com"
one corp.txt   "j.doe${AT}acme-corp.co.id"
one phone.txt  "+628${AT:+}1234567890"   # dirakit; jangan tulis literal
one ssh.txt    "git${AT}github.com:Hasban-Fardani/agentic-loop.git"
one hg.txt     "hg${AT}bitbucket.org:x/y"
one ex.txt     "someone${AT}example.com"
one dot.txt    "u${AT}host.test"
one inv.txt    "a${AT}b.invalid"
one nr.txt     "noreply${AT}github.com"

pii() { AL_SECRET_PATTERN='' rc_of bash "$AL/core/cmd/scan.sh" "$D/$1"; }
for x in gmail.txt corp.txt phone.txt; do
  assert_eq "PII nyata tertangkap: $x" 1 "$(pii "$x")"
done
# Regresi: allowlist `git@` pernah ikut memaafkan alamat yang berakhiran "git@".
assert_eq "alamat berakhiran git${AT} tidak ikut ter-allowlist" 1 "$(pii digit.txt)"
for x in ssh.txt hg.txt ex.txt dot.txt inv.txt nr.txt; do
  assert_eq "bentuk dokumentasi/SSH di-allowlist: $x" 0 "$(pii "$x")"
done

# Allowlist hanya berlaku pada pass PII; sebuah baris tidak boleh menyembunyikan
# credential dengan menyelipkan alamat contoh.
printf 'git%sgithub.com:x/y.git tok=%s\n' "$AT" "$FAKE_GH" > "$D/mix.txt"
assert_eq "secret tetap tertangkap di baris ber-allowlist" 1 \
  "$(rc_of bash "$AL/core/cmd/scan.sh" "$D/mix.txt")"
out=$(out_of bash "$AL/core/cmd/scan.sh" "$D/mix.txt")
refute_contains "nilai token tidak dicetak" "$out" "$FAKE_GH"
assert_contains "lokasi temuan dilaporkan"  "$out" "value withheld"

printf 'k=%s\n' "$FAKE_AWS" > "$D/aws.txt"
assert_eq "AWS key tertangkap" 1 "$(rc_of bash "$AL/core/cmd/scan.sh" "$D/aws.txt")"

# Pola dan allowlist sepenuhnya env-driven: tak perlu menyentuh script.
assert_eq "AL_PII_ALLOW kosong mengaktifkan lagi git@" 1 \
  "$(AL_PII_ALLOW='' AL_SECRET_PATTERN='' rc_of bash "$AL/core/cmd/scan.sh" "$D/ssh.txt")"
printf 'a%smycorp.internal\n' "$AT" > "$D/c.txt"
assert_eq "AL_PII_ALLOW custom dihormati" 0 \
  "$(AL_PII_ALLOW='@mycorp\.internal' AL_SECRET_PATTERN='' rc_of bash "$AL/core/cmd/scan.sh" "$D/c.txt")"
printf 'plate=XYZ-4242\n' > "$D/p.txt"
assert_eq "AL_SECRET_PATTERN custom dihormati" 1 \
  "$(AL_SECRET_PATTERN='XYZ-[0-9]{4}' AL_PII_PATTERN='' rc_of bash "$AL/core/cmd/scan.sh" "$D/p.txt")"

C="$(new_dir clean)"; echo 'echo hi' > "$C/a.sh"
assert_eq "scope bersih -> 0" 0 "$(rc_of bash "$AL/core/cmd/scan.sh" "$C")"
# /bin/bash absolut: dengan PATH rusak, `bash` telanjang tidak dapat di-resolve.
assert_eq "tool hilang -> 2 (UNKNOWN), bukan 0/1" 2 \
  "$(rc_of env PATH=/nonexistent /bin/bash "$AL/core/cmd/scan.sh" "$D")"

# Allowlist fixture: hanya untuk repo yang memang menyimpan secret sintetis.
F="$(new_dir fx)"; mkdir -p "$F/tests/fixtures" "$F/src"; git -C "$F" init -q
printf 'k=%s\n' "$FAKE_AWS" > "$F/tests/fixtures/s.txt"
assert_eq "temuan khusus fixture di-allowlist" 0 \
  "$(AL_REPO_ROOT="$F" AL_ALLOW_FIXTURE_SECRETS=1 AL_PII_PATTERN='' rc_of bash "$AL/core/cmd/scan.sh" "$F")"
printf 'k=%s\n' "$FAKE_AWS" > "$F/src/leak.txt"
# Regresi: pola kosong pernah membuat daftar "di luar fixture" ikut kosong,
# sehingga kebocoran nyata lolos lewat jalur allowlist.
assert_eq "kebocoran di luar fixture mengalahkan allowlist" 1 \
  "$(AL_REPO_ROOT="$F" AL_ALLOW_FIXTURE_SECRETS=1 AL_PII_PATTERN='' rc_of bash "$AL/core/cmd/scan.sh" "$F")"

assert_eq "repo ini sendiri bersih" 0 "$(rc_of bash "$AL/core/cmd/scan.sh" "$AL")"

test_summary
