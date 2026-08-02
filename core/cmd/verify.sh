#!/usr/bin/env bash
# al verify — self-test policy & permission boundary di repo target.
#
# Menguji integration boundary dan policy proyek, BUKAN internal harness.
# Exit: 0 semua lulus, 1 ada FAIL, 2 hanya SKIP (field tak tersedia di harness ini).
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"

pass=0; fail=0; skip=0
ok(){ printf 'PASS  %s\n' "$1"; pass=$((pass+1)); }
no(){ printf 'FAIL  %s%s\n' "$1" "${2:+ -- $2}"; fail=$((fail+1)); }
sk(){ printf 'SKIP  %s%s\n' "$1" "${2:+ -- $2}"; skip=$((skip+1)); }
chk(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else no "$n"; fi; }
ref(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then no "$n" "berhasil padahal harus gagal"; else ok "$n"; fi; }

POLICY="$AL_REPO_ROOT/$AL_POLICY_FILE"

printf '\n=== 1. Contract files ===\n'
chk "manifest ada ($AL_MANIFEST)"        test -f "$AL_MANIFEST_PATH"
chk "acceptance map ada"                 test -f "$AL_ACCEPTANCE_PATH"
chk "policy ada ($AL_POLICY_FILE)"       test -f "$POLICY"
[ -f "$AL_MANIFEST_PATH" ] || { al_err "jalankan: al init"; exit 1; }

printf '\n=== 2. Adapter ===\n'
for step in $(al_yaml_seq "$AL_MANIFEST_PATH" profiles full); do
  s="$(al_yaml_nested "$AL_MANIFEST_PATH" commands "$step")"
  : "${s:=$AL_ADAPTER_DIR/$step.sh}"
  if [ -f "$AL_REPO_ROOT/$s" ]; then
    chk "adapter $step syntax"           bash -n "$AL_REPO_ROOT/$s"
    chk "adapter $step pakai set -Eeuo"  grep -q 'set -Eeuo pipefail' "$AL_REPO_ROOT/$s"
  else
    no "adapter $step" "tidak ada: $s"
  fi
done
ref "adapter tidak push ke branch protected" \
  grep -rqE "git push.*($AL_PROTECTED_BRANCH|master)" "$AL_REPO_ROOT/$AL_ADAPTER_DIR"

printf '\n=== 3. Timeout ===\n'
start=$(date +%s)
set +e; al_timeout 1 sleep 10 >/dev/null 2>&1; rc=$?; set -e
el=$(( $(date +%s) - start ))
if [ "$rc" = 124 ] && [ "$el" -le 4 ]; then ok "timeout membunuh proses (124 dalam ${el}s)"
elif [ "$el" -le 4 ]; then no "timeout" "proses mati cepat tapi rc=$rc, bukan 124"
else no "timeout" "rc=$rc setelah ${el}s"; fi

printf '\n=== 4. Decision ladder ===\n'
run(){ set +e; bash "$AL_HOME/core/cmd/run.sh" "$1" >/dev/null 2>&1; echo $?; set -e; }
# Untuk menguji pemetaan step -> decision, gate lain harus dinonaktifkan.
# Kalau tidak, worktree kotor menurunkan FAIL menjadi UNKNOWN dan tes ini
# mengukur gate yang salah. Gate worktree/acceptance diuji terpisah.
run_step_only(){ set +e; AL_STRICT_WORKTREE=0 AL_STRICT_ACCEPTANCE=0 \
  bash "$AL_HOME/core/cmd/run.sh" "$1" >/dev/null 2>&1; echo $?; set -e; }
art(){ ls -t "$AL_ARTIFACT_PATH"/*.json 2>/dev/null | head -1; }
dec(){ jq -r .verifier_decision "$(art)" 2>/dev/null; }

if [ -n "$(git -C "$AL_REPO_ROOT" status --porcelain 2>/dev/null)" ]; then
  sk "clean tree -> PASS" "worktree kotor; commit dulu"
else
  rc=$(run smoke)
  { [ "$rc" = 0 ] && [ "$(dec)" = PASS ]; } && ok "clean tree -> PASS/exit0" \
    || no "clean tree -> PASS" "rc=$rc dec=$(dec)"
fi

# FAIL vs UNKNOWN: keduanya diuji dengan menukar adapter `test` sementara, karena
# hanya step yang benar-benar ada di profile yang memengaruhi keputusan.
# Adapter asli disimpan dan dipulihkan lewat trap, supaya kegagalan di tengah
# tidak meninggalkan repo dengan adapter rusak.
TARGET="$AL_REPO_ROOT/$AL_ADAPTER_DIR/test.sh"
SAVED=""
# Pulihkan dengan `cp -p`, bukan `mv`: file dari mktemp bermode 600, dan mv akan
# membawa mode itu ke adapter sehingga git melihatnya sebagai file berubah.
restore(){ [ -n "$SAVED" ] && [ -f "$SAVED" ] && { cp -p "$SAVED" "$TARGET"; rm -f "$SAVED"; SAVED=""; }; }
trap restore EXIT

if [ -f "$TARGET" ]; then
  SAVED="$(mktemp)"; cp -p "$TARGET" "$SAVED"

  # FAIL: adapter exit 1.
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TARGET"
  rc=$(run_step_only smoke)
  { [ "$rc" = 1 ] && [ "$(dec)" = FAIL ]; } && ok "adapter gagal -> FAIL/exit1" \
    || no "adapter gagal -> FAIL" "rc=$rc dec=$(dec)"

  # UNKNOWN mengalahkan FAIL: adapter hilang sama sekali.
  rm -f "$TARGET"
  rc=$(run_step_only smoke)
  { [ "$rc" = 2 ] && [ "$(dec)" = UNKNOWN ]; } && ok "adapter hilang -> UNKNOWN/exit2" \
    || no "adapter hilang -> UNKNOWN" "rc=$rc dec=$(dec)"

  restore
  chk "adapter dipulihkan utuh" git -C "$AL_REPO_ROOT" diff --quiet -- "$AL_ADAPTER_DIR/test.sh"
else
  sk "decision ladder FAIL/UNKNOWN" "tidak ada $AL_ADAPTER_DIR/test.sh"
fi

printf '\n=== 5. Scanner ===\n'
chk "scanner jalan"  bash "$AL_HOME/core/cmd/scan.sh" "$AL_REPO_ROOT"
rc=$(set +e; PATH=/nonexistent /bin/bash "$AL_HOME/core/cmd/scan.sh" "$AL_REPO_ROOT" >/dev/null 2>&1; echo $?)
[ "$rc" = 2 ] && ok "scanner tak tersedia -> exit 2 (UNKNOWN), bukan 0/1" \
  || no "scanner unavailable" "rc=$rc"

printf '\n=== 6. Secret hygiene ===\n'
gi="$AL_REPO_ROOT/.gitignore"
chk ".gitignore ada"                    test -f "$gi"
chk ".env di-ignore"                    git -C "$AL_REPO_ROOT" check-ignore -q .env
ref ".env TIDAK ter-track git"          git -C "$AL_REPO_ROOT" ls-files --error-unmatch .env
chk "artifact di-ignore"                git -C "$AL_REPO_ROOT" check-ignore -q "$AL_ARTIFACT_DIR"
if [ -f "$AL_REPO_ROOT/.env.example" ]; then
  ref ".env.example bebas credential" \
    grep -qE '(ghp_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,})' "$AL_REPO_ROOT/.env.example"
else
  sk ".env.example" "tidak ada"
fi

printf '\n=== 7. Policy declarations ===\n'
if [ -f "$POLICY" ]; then
  for d in "serial_only: true" "external_provider: disabled" "write_approval: required" \
           "mode: manual_allowlist" "export: disabled"; do
    chk "policy menyatakan '$d'" grep -q "$d" "$POLICY"
  done
  for fb in merge_own_pr push_to_protected_branch deploy_production; do
    chk "forbidden: $fb" grep -q "$fb" "$POLICY"
  done
else
  sk "policy declarations" "tidak ada $AL_POLICY_FILE"
fi

printf '\n=== 8. Harness config mapping ===\n'
# Nama field tiap harness berbeda. Yang tidak ada dilaporkan SKIP, bukan lulus
# diam-diam — operator wajib memetakan dan mengujinya sendiri.
mapped=0
if [ -f "$POLICY" ] && command -v hermes >/dev/null 2>&1; then
  in_map=0
  while IFS= read -r line; do
    case "$line" in
      "  hermes:") in_map=1; continue ;;
      "  "[a-z]*:) [ "$in_map" = 1 ] && in_map=0 ;;
    esac
    [ "$in_map" = 1 ] || continue
    case "$line" in "    "*:*) : ;; *) continue ;; esac
    key=$(printf '%s' "$line" | sed -E 's/^    ([^:]+):.*/\1/')
    want=$(printf '%s' "$line" | sed -E 's/^    [^:]+:[[:space:]]*//; s/[[:space:]]*#.*//')
    got=$(hermes config get "$key" 2>/dev/null | tail -1 | tr -d '\r')
    mapped=$((mapped+1))
    if   [ -z "$got" ];        then sk "hermes $key" "field tidak ada di versi ini"
    elif [ "$got" = "$want" ]; then ok "hermes $key=$got"
    else no "hermes $key" "want=$want got=$got"; fi
  done < "$POLICY"
fi
[ "$mapped" = 0 ] && sk "harness config mapping" "tidak ada harness yang dapat diperiksa dari sini"

printf '\n'
printf 'SUMMARY pass=%d fail=%d skip=%d\n' "$pass" "$fail" "$skip"
[ "$fail" -gt 0 ] && exit 1
[ "$skip" -gt 0 ] && exit 2
exit 0
