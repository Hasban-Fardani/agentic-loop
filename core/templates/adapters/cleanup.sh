#!/usr/bin/env bash
# Adapter cleanup — dihasilkan `al init`. Aman diedit; command dari deteksi stack
# atau override AL_CMD_CLEANUP di .env, jadi biasanya tak perlu diubah.
# Exit: 0 ok, 1 gagal, 2 tidak dapat dibuktikan (-> UNKNOWN).
set -Eeuo pipefail
AL_HOME="${AL_HOME:-$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)}"
. "$AL_HOME/core/lib/bootstrap.sh"
. "$AL_HOME/core/lib/detect.sh"

# Hanya log kedaluwarsa. Artifact tunduk pada retention + legal hold.
exec bash "$AL_HOME/core/cmd/clean.sh"
