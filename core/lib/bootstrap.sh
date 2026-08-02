# shellcheck shell=bash
# Satu titik masuk untuk semua script agentic-loop.
#
#   . "$(dirname "$0")/../lib/bootstrap.sh"
#
# Urutan sengaja: config (nilai) -> redact (butuh AL_SECRET_VARS) -> util
# (butuh al_err dari redact).

[ -n "${_AL_BOOTSTRAP_LOADED:-}" ] && return 0
_AL_BOOTSTRAP_LOADED=1

_al_lib="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
# shellcheck source=core/lib/config.sh
. "$_al_lib/config.sh"
# shellcheck source=core/lib/redact.sh
. "$_al_lib/redact.sh"
# shellcheck source=core/lib/util.sh
. "$_al_lib/util.sh"
unset _al_lib

# Path absolut yang sudah diselesaikan, agar script tidak menghitung ulang.
AL_ARTIFACT_PATH="$AL_REPO_ROOT/$AL_ARTIFACT_DIR"
AL_LOG_PATH="$AL_REPO_ROOT/$AL_LOG_DIR"
AL_MANIFEST_PATH="$AL_REPO_ROOT/$AL_MANIFEST"
AL_ACCEPTANCE_PATH="$AL_REPO_ROOT/$AL_ACCEPTANCE_MAP"
AL_EVENT_PATH="$AL_REPO_ROOT/$AL_EVENT_LOG"
export AL_ARTIFACT_PATH AL_LOG_PATH AL_MANIFEST_PATH AL_ACCEPTANCE_PATH AL_EVENT_PATH
