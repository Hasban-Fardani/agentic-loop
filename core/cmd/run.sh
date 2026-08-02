#!/usr/bin/env bash
# al run — jalankan evidence profile, hasilkan Evidence Artifact JSON.
#
# Semua tunable dari env/.env (lihat .env.example). Tidak ada path atau ambang
# yang di-hardcode di sini.
#
# Exit: 0 PASS, 1 FAIL, 2 UNKNOWN. Keputusan juga ada di artifact.verifier_decision.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"

PROFILE="${1:-$AL_PROFILE}"
al_need git jq || exit 2

[ -f "$AL_MANIFEST_PATH" ] || al_die "manifest tidak ada: $AL_MANIFEST (jalankan: al init)"

RUN_ID="${AL_RUN_ID:-${CI_RUN_ID:-local-$(date -u +%Y%m%dT%H%M%SZ)-$$}}"
LOG_DIR="$AL_LOG_PATH/$RUN_ID"
mkdir -p "$LOG_DIR" "$AL_ARTIFACT_PATH"

STEPS="$(al_yaml_seq "$AL_MANIFEST_PATH" profiles "$PROFILE")"
[ -n "$STEPS" ] || al_die "profile tidak dikenal: $PROFILE (cek profiles: di $AL_MANIFEST)"

CONTRACT_VERSION="$(al_yaml_scalar "$AL_MANIFEST_PATH" contract_version)"
REPOSITORY="$(al_yaml_scalar "$AL_MANIFEST_PATH" repository)"
ENV_MODE="$(al_yaml_scalar "$AL_MANIFEST_PATH" environment_mode)"
: "${CONTRACT_VERSION:=$AL_CONTRACT_VERSION}"
: "${REPOSITORY:=$(basename "$AL_REPO_ROOT")}"
: "${ENV_MODE:=approximate}"

HEAD_SHA="$(git -C "$AL_REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
BASE_SHA="$(git -C "$AL_REPO_ROOT" rev-parse "${AL_BASE_REF:-${BASE_REF:-HEAD}}" 2>/dev/null || echo unknown)"

DECISION=PASS
REASONS=""
CMD_JSON="[]"

note()      { REASONS="$REASONS $1"; }
downgrade() { # UNKNOWN mengalahkan FAIL; FAIL mengalahkan PASS
  case "$1" in
    UNKNOWN) DECISION=UNKNOWN ;;
    FAIL)    [ "$DECISION" = UNKNOWN ] || DECISION=FAIL ;;
  esac
}

cd "$AL_REPO_ROOT"

# Higiene commit diambil SEBELUM step berjalan. Adapter setup yang sah sering
# menulis lockfile atau artifact build, dan itu bukan bukti bahwa commit-nya
# kotor. Yang kita pertanyakan: apakah kode yang diuji terikat ke satu commit.
WORKTREE_DIRTY_AT_START=0
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then WORKTREE_DIRTY_AT_START=1; fi

for step in $STEPS; do
  script="$(al_yaml_nested "$AL_MANIFEST_PATH" commands "$step")"
  [ -n "$script" ] || script="$AL_ADAPTER_DIR/$step.sh"
  tmo="$(al_yaml_nested "$AL_MANIFEST_PATH" timeouts_seconds "$step")"
  : "${tmo:=$AL_TIMEOUT_DEFAULT}"
  log="$LOG_DIR/$step.log"

  if [ ! -f "$script" ]; then
    note "MISSING_ADAPTER_$step"; downgrade UNKNOWN
    al_warn "[unavailable] $step -> adapter tidak ada: $script"
    CMD_JSON=$(jq --arg n "$step" --arg s "$script" \
      '. + [{name:$n, script:$s, exit_code:null, duration_ms:0, log_hash:null, status:"unavailable"}]' <<<"$CMD_JSON")
    continue
  fi

  start=$(date +%s)
  set +e
  # Redaksi diterapkan pada boundary tulis log: nilai secret tidak pernah
  # menyentuh disk. PIPESTATUS[0] dipakai agar exit code adapter tidak tertelan
  # oleh exit code sed.
  al_timeout "$tmo" bash "$script" 2>&1 | al_redact > "$log"
  rc=${PIPESTATUS[0]}
  set -e
  dur=$(( ($(date +%s) - start) * 1000 ))
  lh="$(al_sha256 "$log")"

  case "$rc" in
    0)   status=pass ;;
    1)   status=fail;        note "STEP_FAIL_$step";            downgrade FAIL ;;
    2)   status=unavailable; note "STEP_UNAVAILABLE_$step";     downgrade UNKNOWN ;;
    124) status=timeout;     note "STEP_TIMEOUT_$step";         downgrade UNKNOWN ;;
    *)   status=error;       note "STEP_ERROR_${step}_rc$rc";   downgrade UNKNOWN ;;
  esac
  al_info "[$status] $step rc=$rc ${dur}ms -> $(al_repo_rel "$log")"
  CMD_JSON=$(jq --arg n "$step" --arg sc "$script" --argjson e "$rc" --argjson d "$dur" \
    --arg h "$lh" --arg s "$status" \
    '. + [{name:$n, script:$sc, exit_code:$e, duration_ms:$d, log_hash:$h, status:$s}]' <<<"$CMD_JSON")
done

# --- gate acceptance: human_only tanpa approval menolak PASS otomatis ---------
if [ "$AL_STRICT_ACCEPTANCE" = 1 ]; then
  if [ ! -f "$AL_ACCEPTANCE_PATH" ]; then
    note ACCEPTANCE_MAP_MISSING; downgrade UNKNOWN
  elif grep -q 'type: *human_only' "$AL_ACCEPTANCE_PATH" 2>/dev/null \
    && grep -A3 'type: *human_only' "$AL_ACCEPTANCE_PATH" \
       | grep -qE 'approval_ref: *("")?(PENDING|TBD|TODO)?[[:space:]]*$'; then
    note HUMAN_ONLY_APPROVAL_PENDING; downgrade UNKNOWN
  fi
fi

# --- higiene commit: hasil harus terikat ke satu commit ----------------------
if [ "$AL_STRICT_WORKTREE" = 1 ] && [ "$WORKTREE_DIRTY_AT_START" = 1 ]; then
  note DIRTY_WORKTREE; downgrade UNKNOWN
fi

# scanner status diturunkan dari step security, bukan ditebak
sec_status=$(jq -r '(.[] | select(.name=="security") | .status) // "not_run"' <<<"$CMD_JSON")
case "$sec_status" in
  pass)                     scan=pass ;;
  fail)                     scan=fail ;;
  unavailable|timeout|error) scan=unavailable ;;
  *)                        scan=not_run ;;
esac

ART="$AL_ARTIFACT_PATH/evidence-${HEAD_SHA:0:12}-${RUN_ID}.json"
jq -n \
  --arg av "$CONTRACT_VERSION" --arg repo "$REPOSITORY" \
  --arg task "${AL_TASK_ID}" --arg pr "${AL_PR_NUMBER:-${PR_NUMBER:-}}" \
  --arg base "$BASE_SHA" --arg head "$HEAD_SHA" --arg run "$RUN_ID" \
  --arg profile "$PROFILE" --arg tier "$AL_RISK_TIER" --arg pol "$AL_POLICY_VERSION" \
  --arg mode "$ENV_MODE" --argjson cmds "$CMD_JSON" \
  --arg map "$AL_ACCEPTANCE_MAP" --arg scan "$scan" --arg dec "$DECISION" \
  --arg reasons "${REASONS# }" --arg logs "$(al_repo_rel "$LOG_DIR")" \
  '{artifact_version:$av, task_id:$task,
    pr_number:(if $pr=="" then null else ($pr|tonumber? // null) end),
    repository:$repo, base_sha:$base, head_sha:$head, commit_sha:$head, ci_run_id:$run,
    profile:$profile, risk_tier:$tier, policy_version:$pol,
    environment:{mode:$mode, runner_image_digest:env.RUNNER_IMAGE_DIGEST,
                 runtime_versions:{bash:env.BASH_VERSION}},
    commands:$cmds, required_commands:[$cmds[].name],
    skipped_commands:[$cmds[]|select(.status=="unavailable")|.name], skip_reasons:[],
    acceptance_map_ref:$map,
    quality_flags:(if $reasons=="" then [] else ($reasons|split(" ")) end),
    secret_scan_status:$scan, pii_scan_status:$scan, redaction_status:"pass",
    verifier_decision:$dec, log_dir:$logs, created_at:(now|todate)}' > "$ART"

# hash dihitung atas konten tanpa field hash itu sendiri, agar bisa diverifikasi ulang
h=$(jq -S 'del(.artifact_hash)' "$ART" | al_sha256_stdin)
jq --arg h "sha256:$h" '.artifact_hash=$h' "$ART" > "$ART.tmp" && mv "$ART.tmp" "$ART"

al_info "artifact: $(al_repo_rel "$ART")"
case "$DECISION" in
  PASS) al_ok   "decision: PASS" ;;
  FAIL) al_err  "decision: FAIL${REASONS:+ (${REASONS# })}" ;;
  *)    al_warn "decision: UNKNOWN${REASONS:+ (${REASONS# })} — merge diblokir, bukan retry kode" ;;
esac

case "$DECISION" in PASS) exit 0 ;; FAIL) exit 1 ;; *) exit 2 ;; esac
