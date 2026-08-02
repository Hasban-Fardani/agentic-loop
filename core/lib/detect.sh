#!/usr/bin/env bash
# Deteksi stack repo sekali, ekspor AL_STACK + command yang sesuai.
# Adapter men-source ini supaya satu set adapter bekerja di repo Node, PHP, Go,
# Python, Rust, atau Makefile tanpa diedit. Override lewat env kalau tebakan salah.

[ -n "${_AL_DETECT_LOADED:-}" ] && return 0
_AL_DETECT_LOADED=1

_d() { [ -f "$AL_REPO_ROOT/$1" ]; }

al_set_default AL_STACK ""
if [ -z "$AL_STACK" ]; then
  if   _d package.json;   then AL_STACK=node
  elif _d composer.json;  then AL_STACK=php
  elif _d go.mod;         then AL_STACK=go
  elif _d Cargo.toml;     then AL_STACK=rust
  elif _d pyproject.toml || _d requirements.txt; then AL_STACK=python
  elif _d Makefile;       then AL_STACK=make
  else AL_STACK=unknown
  fi
fi
export AL_STACK

# Package manager Node: ikuti lockfile, jangan asumsi npm.
al_node_pm() {
  if   _d bun.lockb || _d bun.lock;  then echo bun
  elif _d pnpm-lock.yaml;            then echo pnpm
  elif _d yarn.lock;                 then echo yarn
  else echo npm
  fi
}

# al_has_script NAME — apakah package.json punya script bernama NAME.
al_has_script() {
  _d package.json || return 1
  command -v jq >/dev/null 2>&1 || return 1
  jq -e --arg s "$1" '.scripts[$s] // empty' "$AL_REPO_ROOT/package.json" >/dev/null 2>&1
}

# al_make_target NAME — apakah Makefile punya target NAME.
al_make_target() {
  _d Makefile || return 1
  grep -qE "^$1:" "$AL_REPO_ROOT/Makefile"
}

# Default per-stack. Semua bisa dioverride dengan AL_CMD_<STEP> dari .env,
# jadi repo tak biasa tidak perlu mengedit adapter.
case "$AL_STACK" in
  node)
    pm="$(al_node_pm)"
    al_set_default AL_CMD_SETUP    "$pm install"
    al_set_default AL_CMD_BUILD    "$pm run build"
    al_set_default AL_CMD_TEST     "$pm test"
    al_set_default AL_CMD_LINT     "$pm run lint"
    al_set_default AL_CMD_SECURITY "$pm audit --audit-level=high"
    ;;
  php)
    al_set_default AL_CMD_SETUP    "composer install --no-interaction --prefer-dist"
    al_set_default AL_CMD_BUILD    ""
    al_set_default AL_CMD_TEST     "./vendor/bin/phpunit"
    al_set_default AL_CMD_LINT     "./vendor/bin/phpcs"
    al_set_default AL_CMD_SECURITY "composer audit"
    ;;
  go)
    al_set_default AL_CMD_SETUP    "go mod download"
    al_set_default AL_CMD_BUILD    "go build ./..."
    al_set_default AL_CMD_TEST     "go test ./..."
    al_set_default AL_CMD_LINT     "go vet ./..."
    al_set_default AL_CMD_SECURITY ""
    ;;
  rust)
    al_set_default AL_CMD_SETUP    "cargo fetch"
    al_set_default AL_CMD_BUILD    "cargo build --locked"
    al_set_default AL_CMD_TEST     "cargo test --locked"
    al_set_default AL_CMD_LINT     "cargo clippy -- -D warnings"
    al_set_default AL_CMD_SECURITY "cargo audit"
    ;;
  python)
    al_set_default AL_CMD_SETUP    "python -m pip install -e ."
    al_set_default AL_CMD_BUILD    ""
    al_set_default AL_CMD_TEST     "python -m pytest -q"
    al_set_default AL_CMD_LINT     "python -m ruff check ."
    al_set_default AL_CMD_SECURITY "python -m pip_audit"
    ;;
  make)
    al_set_default AL_CMD_SETUP    "$(al_make_target setup && echo 'make setup')"
    al_set_default AL_CMD_BUILD    "$(al_make_target build && echo 'make build')"
    al_set_default AL_CMD_TEST     "$(al_make_target test  && echo 'make test')"
    al_set_default AL_CMD_LINT     "$(al_make_target lint  && echo 'make lint')"
    al_set_default AL_CMD_SECURITY ""
    ;;
  *)
    al_set_default AL_CMD_SETUP ""; al_set_default AL_CMD_BUILD ""
    al_set_default AL_CMD_TEST  ""; al_set_default AL_CMD_LINT  ""
    al_set_default AL_CMD_SECURITY ""
    ;;
esac
unset pm

# al_step CMD_STRING STEP_NAME — jalankan, atau umumkan no-op secara eksplisit.
# no-op sengaja exit 0 dan menyebut alasannya; skip diam-diam adalah cara
# evidence gate berbohong.
al_step() {
  if [ -z "$1" ]; then
    printf '%s: no_op (tidak ada command untuk stack %s; set AL_CMD_%s untuk override)\n' \
      "$2" "$AL_STACK" "$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]')"
    return 0
  fi
  printf '%s: %s\n' "$2" "$1"
  # shellcheck disable=SC2086 # command string sengaja di-split jadi argumen
  eval "$1"
}
