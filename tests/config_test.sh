#!/usr/bin/env bash
# Config cascade + .env parsing. Prinsip: environment selalu menang (CI secret
# store), .env adalah data dan tidak pernah dieksekusi.
. "${BASH_SOURCE[0]%/*}/lib.sh"

CFG="$(new_dir cfg)"
DOTENV="$AL/.env"
# .env repo ini harus bersih lagi setelah test, apa pun yang terjadi.
trap 'rm -f "$DOTENV"; rm -rf "$TEST_TMP"' EXIT

boot() { AL_CONFIG_HOME="$CFG" bash -c ". $AL/core/lib/bootstrap.sh; $1"; }

printf 'AL_PROFILE=from_confighome\nAL_RISK_TIER=from_confighome\n' > "$CFG/config.env"
printf 'AL_RISK_TIER=from_dotenv\n' > "$DOTENV"

assert_eq "config.env mengalahkan default bawaan" from_confighome "$(boot 'echo $AL_PROFILE')"
assert_eq ".env mengalahkan config.env"           from_dotenv     "$(boot 'echo $AL_RISK_TIER')"
assert_eq "environment mengalahkan .env" from_env \
  "$(AL_CONFIG_HOME="$CFG" AL_RISK_TIER=from_env bash -c ". $AL/core/lib/bootstrap.sh; echo \$AL_RISK_TIER")"
assert_eq "default berlaku bila tak di-set" 900 \
  "$(bash -c ". $AL/core/lib/bootstrap.sh; echo \$AL_TIMEOUT_DEFAULT")"
# Kosong-tapi-di-set adalah keputusan sengaja, bukan "belum di-set".
assert_eq "nilai kosong eksplisit dipertahankan" "[]" \
  "$(AL_RISK_TIER= bash -c ". $AL/core/lib/bootstrap.sh; echo \"[\$AL_RISK_TIER]\"")"

# .env sebagai data: command substitution tidak boleh jalan.
printf 'EVIL=$(touch %s/pwned)\nOK_KEY=v\n' "$TEST_TMP" > "$DOTENV"
boot 'true' >/dev/null 2>&1 || true
refute ".env tidak pernah mengeksekusi command" test -f "$TEST_TMP/pwned"
assert_eq "key biasa tetap termuat" v "$(boot 'echo $OK_KEY')"

# Heredoc, bukan printf: quote di dalam nilai .env harus sampai apa adanya.
cat > "$DOTENV" <<'ENVEOF'
q="a"
s='b'
c=d  # note
export e=f
1BAD=x
BAD-NAME=y
ENVEOF
assert_eq "quote/komentar/export diproses, ident tak valid dilewati" abdf \
  "$(boot 'echo $q$s$c$e${BAD:-}')"

rm -f "$DOTENV"
assert "AL_HOME terdeteksi"      bash -c ". $AL/core/lib/bootstrap.sh; [ -d \"\$AL_HOME/core\" ]"
assert "path artifact diturunkan" bash -c ". $AL/core/lib/bootstrap.sh; [ -n \"\$AL_ARTIFACT_PATH\" ]"
assert "AL_SECRET_VARS tidak kosong" bash -c ". $AL/core/lib/bootstrap.sh; [ -n \"\$AL_SECRET_VARS\" ]"
assert "AL_PII_ALLOW punya default"  bash -c ". $AL/core/lib/bootstrap.sh; [ -n \"\$AL_PII_ALLOW\" ]"

test_summary
