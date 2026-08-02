# shellcheck shell=bash
# Redaksi + logging. Di-source setelah config.sh.
#
# Kontrak: tidak ada nilai secret yang boleh sampai ke stdout, log file, artifact,
# atau event log. Redaksi bekerja dua arah:
#   1. by-value  — nilai variabel yang terdaftar di AL_SECRET_VARS diganti literal.
#   2. by-pattern — apa pun yang cocok AL_SECRET_PATTERN diganti, walau nama
#                   variabelnya tidak kita kenal (mis. token yang di-echo tool lain).

[ -n "${_AL_REDACT_LOADED:-}" ] && return 0
_AL_REDACT_LOADED=1

: "${AL_SECRET_VARS:?config.sh harus di-source lebih dulu}"

# Bangun script sed sekali saja. Nilai pendek (<8 char) dilewati: terlalu umum,
# meredaksinya merusak log tanpa menambah keamanan.
_al_build_sed() {
  _al_sed_script=''
  for _v in $AL_SECRET_VARS; do
    eval "_val=\${$_v:-}"
    [ -n "$_val" ] || continue
    [ "${#_val}" -ge 8 ] || continue
    # escape karakter yang bermakna bagi sed
    _esc=$(printf '%s' "$_val" | sed 's/[][\\/.*^$&]/\\&/g')
    _al_sed_script="${_al_sed_script}s/${_esc}/[REDACTED:${_v}]/g;"
  done
  if [ -n "${AL_SECRET_PATTERN:-}" ]; then
    _al_sed_script="${_al_sed_script}s/${AL_SECRET_PATTERN}/[REDACTED:pattern]/g;"
  fi
  unset _v _val _esc
}
_al_build_sed

# al_redact — filter stdin. Selalu exit 0; kegagalan redaksi tidak boleh
# menghentikan pipeline evidence, tetapi juga tidak boleh meloloskan data mentah,
# jadi bila sed gagal kita buang isinya dan tandai.
al_redact() {
  if [ -z "$_al_sed_script" ]; then cat; return 0; fi
  sed -E "$_al_sed_script" 2>/dev/null || echo "[REDACTION_FAILED: output withheld]"
}

# al_redact_str STRING — redaksi satu string (untuk pesan error/event).
al_redact_str() { printf '%s' "$1" | al_redact; }

# ---------------------------------------------------------------- logging

_al_use_color() {
  case "${AL_COLOR:-auto}" in
    always) return 0 ;;
    never)  return 1 ;;
    *)      [ -t 2 ] ;;
  esac
}
if _al_use_color; then
  _C_RED=$'\033[31m'; _C_YEL=$'\033[33m'; _C_GRN=$'\033[32m'
  _C_DIM=$'\033[2m';  _C_OFF=$'\033[0m'
else
  _C_RED=''; _C_YEL=''; _C_GRN=''; _C_DIM=''; _C_OFF=''
fi

# Semua logger menulis ke stderr agar stdout tetap bersih untuk data
# machine-readable, dan semuanya lewat redaksi.
al_info() { [ "${AL_QUIET:-0}" = 1 ] && return 0; printf '%s\n' "$(al_redact_str "$*")" >&2; }
al_ok()   { [ "${AL_QUIET:-0}" = 1 ] && return 0; printf '%s%s%s\n' "$_C_GRN" "$(al_redact_str "$*")" "$_C_OFF" >&2; }
al_warn() { printf '%swarn:%s %s\n' "$_C_YEL" "$_C_OFF" "$(al_redact_str "$*")" >&2; }
al_err()  { printf '%serror:%s %s\n' "$_C_RED" "$_C_OFF" "$(al_redact_str "$*")" >&2; }
al_die()  { al_err "$*"; exit 1; }
al_debug(){ [ -n "${AL_DEBUG:-}" ] || return 0; printf '%s· %s%s\n' "$_C_DIM" "$(al_redact_str "$*")" "$_C_OFF" >&2; }

# al_run CMD... — hormati AL_DRY_RUN untuk operasi yang mengubah state.
al_run() {
  if [ "${AL_DRY_RUN:-0}" = 1 ]; then
    al_info "DRY-RUN: $*"
    return 0
  fi
  "$@"
}
