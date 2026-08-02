#!/usr/bin/env bash
# al metrics — hitung ulang metrik dari artifact dan event log.
#
# Tidak ada target di sini. Baseline belum ada, dan menuliskan angka yang
# ditebak lebih buruk daripada tidak menuliskan apa pun: ia terlihat seperti
# pengukuran. Isi baseline setelah 2-4 minggu pemakaian nyata.
#
#   al metrics            ringkasan terbaca manusia
#   al metrics --json     satu objek JSON untuk diproses lanjut
#
# Exit: 0 selalu bila data dapat dibaca, 2 bila tidak ada data sama sekali.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"
al_need jq || exit 2

FMT=text
[ "${1:-}" = "--json" ] && FMT=json

arts=$(find "$AL_ARTIFACT_PATH" -name '*.json' -type f 2>/dev/null | sort || true)
n_art=$(printf '%s\n' "$arts" | grep -c . || true)

if [ "$n_art" -eq 0 ] && [ ! -f "$AL_EVENT_PATH" ]; then
  al_err "belum ada data: tidak ada artifact di $AL_ARTIFACT_DIR maupun event log"
  al_info "jalankan: al run standard"
  exit 2
fi

# Semua artifact digabung jadi satu array supaya agregasi terjadi di jq, bukan
# di loop shell.
if [ "$n_art" -gt 0 ]; then
  # shellcheck disable=SC2086 # daftar path sengaja di-split
  all=$(jq -s '.' $arts 2>/dev/null || echo '[]')
else
  all='[]'
fi

metrics=$(jq -n --argjson a "$all" '
  ($a | length) as $n |
  {
    runs: $n,
    pass:    [$a[]|select(.verifier_decision=="PASS")]    | length,
    fail:    [$a[]|select(.verifier_decision=="FAIL")]    | length,
    unknown: [$a[]|select(.verifier_decision=="UNKNOWN")] | length,
    # UNKNOWN rate adalah metrik utama PRD section 7: ia mengukur apakah
    # infrastruktur dapat dipercaya, bukan apakah kode benar.
    unknown_rate: (if $n>0 then (([$a[]|select(.verifier_decision=="UNKNOWN")]|length) * 100 / $n | floor) else null end),
    by_profile: ($a | group_by(.profile) | map({key: .[0].profile, value: length}) | from_entries),
    by_tier:    ($a | group_by(.risk_tier) | map({key: .[0].risk_tier, value: length}) | from_entries),
    # Flag paling sering menunjukkan di mana workflow sesungguhnya macet.
    top_flags: ([$a[].quality_flags // [] | .[]] | group_by(.) | map({flag: .[0], n: length})
                | sort_by(-.n) | .[0:5]),
    scan_fail:        [$a[]|select(.secret_scan_status=="fail")]        | length,
    scan_unavailable: [$a[]|select(.secret_scan_status=="unavailable")] | length,
    slowest_step: ([$a[].commands // [] | .[] | select(.duration_ms != null)]
                   | sort_by(-.duration_ms) | .[0] // null
                   | if . then {name: .name, ms: .duration_ms} else null end),
    first_run: ($a | map(.created_at) | sort | .[0] // null),
    last_run:  ($a | map(.created_at) | sort | .[-1] // null)
  }')

# Event log opsional; kalau ada, hitung per tipe.
ev='{}'
if [ -f "$AL_EVENT_PATH" ]; then
  ev=$(jq -s 'group_by(.event_type) | map({key: .[0].event_type, value: length}) | from_entries' \
    "$AL_EVENT_PATH" 2>/dev/null || echo '{}')
fi
metrics=$(jq -n --argjson m "$metrics" --argjson e "$ev" '$m + {events: $e}')

if [ "$FMT" = json ]; then
  printf '%s\n' "$metrics"
  exit 0
fi

printf '\nagentic-loop metrics — %s\n' "$(basename "$AL_REPO_ROOT")"
printf '=====================================\n\n'
jq -r '
  "Evidence runs: \(.runs)",
  "  PASS     \(.pass)",
  "  FAIL     \(.fail)",
  "  UNKNOWN  \(.unknown)\(if .unknown_rate != null then "  (\(.unknown_rate)%)" else "" end)",
  "",
  "Per profile: \(.by_profile | to_entries | map("\(.key)=\(.value)") | join("  "))",
  "Per tier:    \(.by_tier    | to_entries | map("\(.key)=\(.value)") | join("  "))",
  "",
  (if (.top_flags|length) > 0
   then "Flag tersering:\n" + (.top_flags | map("  \(.n)x \(.flag)") | join("\n"))
   else "Flag tersering: (tidak ada)" end),
  "",
  "Scanner: fail=\(.scan_fail) unavailable=\(.scan_unavailable)",
  (if .slowest_step then "Step terlama: \(.slowest_step.name) (\(.slowest_step.ms)ms)" else "" end),
  (if (.events|length) > 0
   then "Event: " + (.events | to_entries | map("\(.key)=\(.value)") | join("  "))
   else "Event: (belum ada)" end),
  "",
  "Rentang: \(.first_run // "-") .. \(.last_run // "-")"
' <<<"$metrics"

cat <<'EOF'

Catatan: belum ada target di sini, dan itu disengaja. Baseline diisi setelah
2-4 minggu pemakaian nyata (PRD section 7). Angka yang ditebak terlihat seperti
pengukuran, dan itu lebih menyesatkan daripada kolom yang kosong.
EOF
