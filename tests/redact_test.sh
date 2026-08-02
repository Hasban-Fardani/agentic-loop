#!/usr/bin/env bash
# Redaksi. Kontrak: tidak ada nilai secret yang boleh sampai ke stdout, log,
# artifact, atau event. Dua lapis — nama variabel dan pola.
. "${BASH_SOURCE[0]%/*}/lib.sh"

red() { GITHUB_TOKEN="$FAKE_GH" bash -c ". $AL/core/lib/bootstrap.sh; $1" 2>&1; }

out=$(red 'echo "t=$GITHUB_TOKEN" | al_redact')
assert_contains "secret terdaftar diredaksi by-name" "$out" "REDACTED:GITHUB_TOKEN"
refute_contains "token mentah tidak lolos"           "$out" "$FAKE_GH"

# Credential yang namanya tidak kita kenal harus tetap tertangkap oleh pola.
out=$(bash -c ". $AL/core/lib/bootstrap.sh; echo 'k=$FAKE_AWS' | al_redact")
assert_contains "credential tak terdaftar tertangkap by-pattern" "$out" "REDACTED"
refute_contains "nilai AWS tidak tercetak"                      "$out" "$FAKE_AWS"

for fn in al_warn al_err al_info al_ok; do
  refute_contains "$fn meredaksi" "$(red "$fn \"x \$GITHUB_TOKEN\"")" "$FAKE_GH"
done

# Logger menulis ke stderr supaya stdout tetap murni untuk data machine-readable.
assert_eq "logger tidak mengotori stdout" "" \
  "$(bash -c ". $AL/core/lib/bootstrap.sh; al_info hi" 2>/dev/null)"

# Nilai pendek sengaja tidak diredaksi: terlalu umum, meredaksinya merusak log.
assert_contains "nilai pendek tidak diredaksi" \
  "$(GH_TOKEN=abc bash -c ". $AL/core/lib/bootstrap.sh; echo 'keep abc' | al_redact")" "abc"

# AL_SECRET_VARS dapat diperluas dari .env tanpa menyentuh script.
out=$(MY_CUSTOM_TOKEN="s3cret-value-long-enough" \
  AL_SECRET_VARS="MY_CUSTOM_TOKEN" \
  bash -c ". $AL/core/lib/bootstrap.sh; echo \"v=\$MY_CUSTOM_TOKEN\" | al_redact")
assert_contains "AL_SECRET_VARS custom dihormati" "$out" "REDACTED:MY_CUSTOM_TOKEN"

test_summary
