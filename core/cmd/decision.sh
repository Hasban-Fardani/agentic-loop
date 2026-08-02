#!/usr/bin/env bash
# al decision — cetak decision + quality flags dari artifact terakhir.
# Dipisah dari `al run` supaya bisa dibaca tanpa menjalankan evidence lagi.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"
al_need jq || exit 2

art="${1:-}"
if [ -z "$art" ]; then
  art=$(ls -t "$AL_ARTIFACT_PATH"/*.json 2>/dev/null | head -1 || true)
fi
[ -n "$art" ] && [ -f "$art" ] || al_die "belum ada artifact di $AL_ARTIFACT_DIR (jalankan: al run)"

jq -r '"\(.verifier_decision)\t\(.head_sha[0:12])\t\(.profile)\t\(.quality_flags|join(","))"' "$art"

# exit code mengikuti kontrak yang sama dengan `al run`
case "$(jq -r .verifier_decision "$art")" in
  PASS) exit 0 ;;
  FAIL) exit 1 ;;
  *)    exit 2 ;;
esac
