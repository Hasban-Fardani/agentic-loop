# shellcheck shell=bash
# Utilitas portabel: timeout, sha256, pembaca YAML sederhana.
# Di-source setelah config.sh + redact.sh.

[ -n "${_AL_UTIL_LOADED:-}" ] && return 0
_AL_UTIL_LOADED=1

# al_timeout SECS CMD... — exit 124 bila melewati batas, di mana pun dijalankan.
# GNU coreutils `timeout` tidak ada di macOS default, jadi ada fallback perl.
al_timeout() {
  _secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$_secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_secs" "$@"
  else
    # fork wajib: `exec` membuang handler ALRM, sehingga SIGALRM lolos ke child
    # dan exit code menjadi 142, bukan 124 yang jadi kontrak kita.
    perl -e '
      my $s = shift;
      my $pid = fork();
      if ($pid == 0) { exec @ARGV or exit 127; }
      $SIG{ALRM} = sub { kill "TERM", $pid; sleep 1; kill "KILL", $pid; exit 124 };
      alarm $s;
      waitpid($pid, 0);
      alarm 0;
      exit($? >> 8 || ($? & 127 ? 128 + ($? & 127) : 0));
    ' "$_secs" "$@"
  fi
}

# al_sha256 FILE
al_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# al_sha256_stdin
al_sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  else shasum -a 256 | cut -d' ' -f1; fi
}

# --- Pembaca YAML ------------------------------------------------------------
# ponytail: ceiling = YAML rata dua level (scalar, `key: [a, b]`, dan map anak
# satu tingkat). Cukup untuk evidence manifest. Bila manifest butuh nested list
# atau anchor, ganti ke `yq` bila ada, atau helper terkompilasi — jangan
# menumbuhkan regex ini.

al_yaml_scalar() { # FILE KEY
  grep -E "^$2:" "$1" 2>/dev/null | head -1 \
    | sed -E "s/^$2:[[:space:]]*//; s/[[:space:]]*#.*//; s/^[\"']//; s/[\"']$//"
}

al_yaml_seq() { # FILE PARENT KEY  -> "a b c" dari `  key: [a, b, c]`
  grep -E "^  $3:[[:space:]]*\[" "$1" 2>/dev/null \
    | sed -E 's/.*\[(.*)\].*/\1/; s/,/ /g; s/["'"'"']//g'
}

al_yaml_nested() { # FILE PARENT CHILD
  awk -v p="^$2:" -v c="^  $3:" '
    $0 ~ p {inb=1; next}
    inb && /^[A-Za-z]/ {inb=0}
    inb && $0 ~ c {sub(/^  [A-Za-z_]+:[[:space:]]*/,""); sub(/[[:space:]]*#.*/,""); print; exit}
  ' "$1" | sed -E 's/^["'"'"']//; s/["'"'"']$//'
}

# al_need CMD... — gagal cepat dengan pesan yang menyebut tool mana yang hilang.
al_need() {
  _missing=''
  for _c in "$@"; do
    command -v "$_c" >/dev/null 2>&1 || _missing="$_missing $_c"
  done
  [ -z "$_missing" ] && return 0
  al_err "tool wajib tidak ditemukan:$_missing"
  return 1
}

# al_repo_rel PATH — path absolut -> relatif terhadap AL_REPO_ROOT (untuk log).
al_repo_rel() { printf '%s' "${1#"$AL_REPO_ROOT"/}"; }
