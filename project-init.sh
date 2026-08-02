#!/usr/bin/env bash
# Project initializer — pasang contract agentic-loop ke repo target.
# Ini bukan installer harness. Untuk install skill gunakan install.sh.
set -Eeuo pipefail

AL_HOME="${AL_HOME:-$(cd "${BASH_SOURCE[0]%/*}" && pwd)}"
export AL_HOME

aep=0
while [ $# -gt 0 ]; do
  case "$1" in
    --aep) aep=1 ;;
    --dry-run) export AL_DRY_RUN=1 ;;
    --force) export AL_FORCE=1 ;;
    --help|-h)
      cat <<'EOF'
project-init.sh — bootstrap contract agentic-loop ke project

USAGE
  ./project-init.sh [--aep] [--dry-run] [--force]

Jalankan dari root project target. Script hanya menulis contract project.
Untuk install skill ke Hermes/Claude/Codex, gunakan install.sh.
EOF
      exit 0
      ;;
    *) printf 'opsi tidak dikenal: %s\n' "$1" >&2; exit 64 ;;
  esac
  shift
done

if [ "$aep" = 1 ]; then
  exec "$AL_HOME/bin/al" init --aep
fi
exec "$AL_HOME/bin/al" init
