#!/usr/bin/env bash
# Evidence gate: tangga keputusan, integritas artifact, dan yang paling penting —
# secret tidak pernah menyentuh disk.
. "${BASH_SOURCE[0]%/*}/lib.sh"

R="$(new_repo gate)"

assert_eq "profil standard -> PASS/0" 0 "$(rc_of al_in "$R" run standard)"
assert_eq "verdict artifact = PASS"   PASS "$(decision_of "$R")"
assert_eq "tidak ada flag saat PASS"  ""   "$(flags_of "$R")"

# Tangga: FAIL untuk kode salah, UNKNOWN untuk yang tak dapat dibuktikan.
printf '#!/usr/bin/env bash\nexit 1\n' > "$R/scripts/evidence/test.sh"
assert_eq "test gagal -> FAIL/1" 1 "$(AL_STRICT_WORKTREE=0 rc_of al_in "$R" run smoke)"
assert_eq "verdict = FAIL"       FAIL "$(decision_of "$R")"
assert_contains "flag STEP_FAIL dicatat" "$(flags_of "$R")" "STEP_FAIL_test"

rm -f "$R/scripts/evidence/test.sh"
assert_eq "adapter hilang -> UNKNOWN/2" 2 "$(AL_STRICT_WORKTREE=0 rc_of al_in "$R" run smoke)"
assert_eq "verdict = UNKNOWN"           UNKNOWN "$(decision_of "$R")"
assert_contains "flag MISSING_ADAPTER dicatat" "$(flags_of "$R")" "MISSING_ADAPTER_test"
git -C "$R" checkout -- scripts/evidence/test.sh

# UNKNOWN mengalahkan FAIL: infra yang tak terbukti tidak boleh tampak seperti
# fitur yang rusak, karena budget retry-nya berbeda.
printf '#!/usr/bin/env bash\nexit 1\n' > "$R/scripts/evidence/lint.sh"
mv "$R/scripts/evidence/build.sh" "$TEST_TMP/build.bak"
assert_eq "UNKNOWN mengalahkan FAIL -> 2" 2 "$(AL_STRICT_WORKTREE=0 rc_of al_in "$R" run standard)"
fl="$(flags_of "$R")"
assert_contains "kedua sebab tercatat (fail)"    "$fl" "STEP_FAIL_lint"
assert_contains "kedua sebab tercatat (missing)" "$fl" "MISSING_ADAPTER_build"
mv "$TEST_TMP/build.bak" "$R/scripts/evidence/build.sh"
git -C "$R" checkout -- scripts/evidence/lint.sh

# Worktree kotor melepaskan hasil dari commit -> tidak dapat dibuktikan.
echo scratch >> "$R/README.md"
assert_eq "worktree kotor -> UNKNOWN/2" 2 "$(rc_of al_in "$R" run smoke)"
assert_contains "flag DIRTY_WORKTREE" "$(flags_of "$R")" "DIRTY_WORKTREE"
assert_eq "AL_STRICT_WORKTREE=0 keluar dari gate itu" 0 \
  "$(AL_STRICT_WORKTREE=0 rc_of al_in "$R" run smoke)"
rm -f "$R/README.md"

# Acceptance human_only tanpa approval menolak PASS otomatis.
P="$(new_repo accept)"
sed -i.bak 's/approval_ref: APR-TEST/approval_ref: PENDING/' "$P/.agent/acceptance-evidence.yaml"
rm -f "$P/.agent"/*.bak
git -C "$P" add -A && git -C "$P" commit -q -m pending
assert_eq "human_only PENDING -> UNKNOWN/2" 2 "$(rc_of al_in "$P" run smoke)"
assert_contains "flag HUMAN_ONLY_APPROVAL_PENDING" "$(flags_of "$P")" "HUMAN_ONLY"
assert_eq "AL_STRICT_ACCEPTANCE=0 keluar dari gate itu" 0 \
  "$(AL_STRICT_ACCEPTANCE=0 rc_of al_in "$P" run smoke)"

# Integritas artifact: hash harus dapat dihitung ulang oleh pihak lain.
al_in "$R" run standard >/dev/null 2>&1 || true
a=$(ls -t "$R"/.agent/artifacts/*.json | head -1)
assert     "artifact JSON valid"      jq -e . "$a"
assert_eq  "head_sha = HEAD"          "$(git -C "$R" rev-parse HEAD)" "$(jq -r .head_sha "$a")"
assert_eq  "artifact_hash cocok" \
  "sha256:$(jq -S 'del(.artifact_hash)' "$a" | shasum -a 256 | cut -d' ' -f1)" \
  "$(jq -r .artifact_hash "$a")"
assert "setiap step pass punya log_hash" \
  jq -e '[.commands[]|select(.status=="pass" and .log_hash==null)]|length==0' "$a"
assert "log_hash cocok dengan byte log" bash -c '
  d="$2/$(jq -r .log_dir "$1")"
  jq -r ".commands[]|select(.log_hash!=null)|\"\(.name) \(.log_hash)\"" "$1" | while read -r n hh; do
    [ "$(shasum -a 256 "$d/$n.log" | cut -d" " -f1)" = "$hh" ] || exit 1
  done' _ "$a" "$R"
assert_eq "policy_version tercatat" policy-v7.1 "$(jq -r .policy_version "$a")"
assert_eq "AL_TASK_ID masuk artifact" TASK-777 \
  "$(AL_TASK_ID=TASK-777 al_in "$R" run smoke >/dev/null 2>&1; jq -r .task_id "$(ls -t "$R"/.agent/artifacts/*.json|head -1)")"

# Redaksi di boundary tulis: nilai secret tidak pernah menyentuh disk.
L="$(new_repo leak 'echo tok=$GITHUB_TOKEN')"
GITHUB_TOKEN="$FAKE_GH" AL_STRICT_WORKTREE=0 al_in "$L" run smoke >/dev/null 2>&1 || true
refute "token tidak ada di log evidence"      grep -rqF "$FAKE_GH" "$L/.agent/logs/"
refute "token tidak ada di artifact"          grep -rqF "$FAKE_GH" "$L/.agent/artifacts/"
assert "penanda redaksi ada di log"           grep -rq "REDACTED" "$L/.agent/logs/"

assert_eq "profil tak dikenal ditolak" 1 "$(rc_of al_in "$R" run nosuchprofile)"

test_summary
