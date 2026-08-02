#!/usr/bin/env bash
# Adapter setup — dihasilkan `al init`. Aman diedit; command dari deteksi stack
# atau override AL_CMD_SETUP di .env, jadi biasanya tak perlu diubah.
# Exit: 0 ok, 1 gagal, 2 tidak dapat dibuktikan (-> UNKNOWN).
set -Eeuo pipefail
AL_HOME="${AL_HOME:-$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)}"
. "$AL_HOME/core/lib/bootstrap.sh"
. "$AL_HOME/core/lib/detect.sh"

al_step_with_secondary "$AL_CMD_SETUP" "$AL_CMD_SETUP_SECONDARY" setup
