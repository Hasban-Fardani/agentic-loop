#!/usr/bin/env bash
# Adapter lint — dihasilkan `al init`. Aman diedit; command dari deteksi stack
# atau override AL_CMD_LINT di .env, jadi biasanya tak perlu diubah.
# Exit: 0 ok, 1 gagal, 2 tidak dapat dibuktikan (-> UNKNOWN).
set -Eeuo pipefail
AL_HOME="${AL_HOME:-$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)}"
. "$AL_HOME/core/lib/bootstrap.sh"
. "$AL_HOME/core/lib/detect.sh"

# Shell repo apa pun tetap dapat syntax check gratis.
fail=0
while IFS= read -r f; do bash -n "$f" || fail=1; done <<EOF
$(find "$AL_REPO_ROOT" -name '*.sh' -type f -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null)
EOF
al_step "$AL_CMD_LINT" lint || fail=1
exit "$fail"
