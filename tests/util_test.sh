#!/usr/bin/env bash
# Helper portabel: timeout dan pembaca YAML. macOS tidak punya GNU timeout,
# jadi fallback perl wajib menghasilkan exit code yang sama.
. "${BASH_SOURCE[0]%/*}/lib.sh"
. "$AL/core/lib/bootstrap.sh"

start=$(date +%s)
rc=$(rc_of al_timeout 1 sleep 20)
el=$(( $(date +%s) - start ))
assert_eq "timeout mengembalikan 124" 124 "$rc"
if [ "$el" -le 4 ]; then ok "timeout memutus dalam ${el}s"; else fail "timeout lambat" "${el}s"; fi
sleep 1
refute "child dibunuh, tidak jadi orphan" pgrep -f "sleep 20"

assert_rc "sukses diteruskan"          0 al_timeout 5 true
assert_rc "exit code child dijaga"     3 al_timeout 5 sh -c 'exit 3'
assert_rc "command tak ada -> 127"   127 al_timeout 5 /nonexistent/binary

f="$(new_dir y)/m.yaml"
cat > "$f" <<'YAML'
contract_version: "evidence-v1"
repository: demo
profiles:
  smoke: [setup, test]
  standard: [setup, build, test]
commands:
  setup: "scripts/evidence/setup.sh"
  test: scripts/evidence/test.sh
timeouts_seconds:
  setup: 300
YAML
assert_eq "scalar, quote dibuang"  evidence-v1 "$(al_yaml_scalar "$f" contract_version)"
assert_eq "scalar tanpa quote"     demo        "$(al_yaml_scalar "$f" repository)"
assert_eq "sequence inline"        "setup test" "$(al_yaml_seq "$f" profiles smoke)"
assert_eq "nested, quote dibuang"  scripts/evidence/setup.sh "$(al_yaml_nested "$f" commands setup)"
assert_eq "nested tanpa quote"     scripts/evidence/test.sh  "$(al_yaml_nested "$f" commands test)"
assert_eq "nested dari blok lain"  300 "$(al_yaml_nested "$f" timeouts_seconds setup)"
assert_eq "key tak ada -> kosong"  ""  "$(al_yaml_nested "$f" commands nosuch)"

assert     "al_need menemukan tool ada"    al_need git jq
refute     "al_need gagal untuk tool absen" al_need definitely-not-a-real-binary
assert_eq  "sha256 file konsisten" "$(al_sha256 "$f")" "$(al_sha256 "$f")"
assert_eq  "sha256 stdin cocok dengan file" \
  "$(al_sha256 "$f")" "$(al_sha256_stdin < "$f")"

test_summary
