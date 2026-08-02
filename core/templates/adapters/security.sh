#!/usr/bin/env bash
# Adapter security — dihasilkan `al init`. Aman diedit; command dari deteksi stack
# atau override AL_CMD_SECURITY di .env, jadi biasanya tak perlu diubah.
# Exit: 0 ok, 1 gagal, 2 tidak dapat dibuktikan (-> UNKNOWN).
set -Eeuo pipefail
AL_HOME="${AL_HOME:-$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)}"
. "$AL_HOME/core/lib/bootstrap.sh"
. "$AL_HOME/core/lib/detect.sh"

# Scanner secret/PII bawaan selalu jalan; audit dependency stack sebagai tambahan.
rc=0
bash "$AL_HOME/core/cmd/scan.sh" || rc=$?
# rc 2 = tool hilang -> UNKNOWN. Jangan tertimpa hasil audit dependency.
[ "$rc" = 2 ] && exit 2
al_step "$AL_CMD_SECURITY" security || rc=1
exit "$rc"
