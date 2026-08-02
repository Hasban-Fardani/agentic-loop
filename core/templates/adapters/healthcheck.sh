#!/usr/bin/env bash
# Adapter healthcheck — dihasilkan `al init`. Aman diedit; command dari deteksi stack
# atau override AL_CMD_HEALTHCHECK di .env, jadi biasanya tak perlu diubah.
# Exit: 0 ok, 1 gagal, 2 tidak dapat dibuktikan (-> UNKNOWN).
set -Eeuo pipefail
AL_HOME="${AL_HOME:-$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)}"
. "$AL_HOME/core/lib/bootstrap.sh"
. "$AL_HOME/core/lib/detect.sh"

# Conditional: tanpa AL_HEALTHCHECK_URL tidak ada yang bisa dibuktikan.
if [ -z "${AL_HEALTHCHECK_URL:-}" ]; then
  echo "healthcheck: no_op (AL_HEALTHCHECK_URL tidak di-set)"
  exit 0
fi
command -v curl >/dev/null 2>&1 || exit 2
al_timeout 30 curl -fsS -o /dev/null "$AL_HEALTHCHECK_URL" || exit 1
echo "healthcheck: ok"
