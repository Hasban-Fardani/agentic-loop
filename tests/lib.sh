# shellcheck shell=bash
# Test harness. Sengaja tanpa framework: satu file, assert eksplisit, sandbox
# yang selalu dibersihkan. Prinsip PRD #1 — evidence over claims — berlaku untuk
# toolkit ini sendiri, bukan hanya untuk repo yang dijaganya.

set -Eeuo pipefail

AL_HOME="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
export AL_HOME
AL="$AL_HOME"

_pass=0; _fail=0; _skipped=0
_current=""

# Sandbox per file test. Dihapus lewat trap, termasuk saat gagal di tengah.
# Gagal keras kalau mktemp tidak menghasilkan direktori: TEST_TMP kosong berarti
# fixture `git init` jatuh ke cwd dan mengotori repo — pernah terjadi.
TEST_TMP="$(mktemp -d)"
[ -d "$TEST_TMP" ] || { printf 'TEST_TMP tidak dibuat\n' >&2; exit 2; }
trap 'rm -rf "$TEST_TMP"' EXIT

# Credential palsu dirakit saat runtime supaya file test ini sendiri tidak
# mengandung pola yang bisa memicu scanner-nya sendiri.
FAKE_GH="ghp_$(printf 'a%.0s' $(seq 36))"
FAKE_AWS="AKIA$(printf 'B%.0s' $(seq 16))"
export FAKE_GH FAKE_AWS

# --- assertions -------------------------------------------------------------

ok()   { printf 'ok %s\n' "$1"; _pass=$((_pass+1)); }
fail() { printf 'not ok %s%s\n' "$1" "${2:+ -- $2}"; _fail=$((_fail+1)); }
skip() { printf 'skip %s%s\n' "$1" "${2:+ -- $2}"; _skipped=$((_skipped+1)); }

# assert NAME CMD... — lulus bila CMD exit 0
assert() { local n="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$n"; else fail "$n"; fi; }

# refute NAME CMD... — lulus bila CMD exit != 0
refute() {
  local n="$1"; shift
  if "$@" >/dev/null 2>&1; then fail "$n" "berhasil padahal harus gagal"; else ok "$n"; fi
}

# assert_eq NAME WANT GOT
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "want='$2' got='$3'"; fi
}

# assert_rc NAME WANT_RC CMD... — exit code adalah kontrak, jadi diuji eksplisit
assert_rc() {
  local n="$1" want="$2"; shift 2
  local got; got=$(rc_of "$@")
  if [ "$got" = "$want" ]; then ok "$n"; else fail "$n" "want rc=$want got rc=$got"; fi
}

# assert_contains NAME HAYSTACK NEEDLE
assert_contains() {
  case "$2" in *"$3"*) ok "$1" ;; *) fail "$1" "tidak memuat '$3'" ;; esac
}

# refute_contains NAME HAYSTACK NEEDLE — dipakai untuk membuktikan tidak ada
# kebocoran secret; ini assert paling penting di suite ini.
refute_contains() {
  case "$2" in *"$3"*) fail "$1" "memuat yang seharusnya tidak ada" ;; *) ok "$1" ;; esac
}

rc_of() { set +e; "$@" >/dev/null 2>&1; local r=$?; set -e; printf '%s' "$r"; }
out_of() { set +e; "$@" 2>&1; set -e; }

# --- fixtures ---------------------------------------------------------------

# new_dir [NAME] — direktori kosong di dalam sandbox
new_dir() {
  [ -d "$TEST_TMP" ] || { printf 'TEST_TMP hilang\n' >&2; exit 2; }
  local d="$TEST_TMP/${1:-d$RANDOM}"; mkdir -p "$d"; printf '%s' "$d"
}

# new_repo NAME [TEST_CMD] — repo git ber-commit dengan .agent/ hasil `al init`
# dan acceptance yang sudah di-approve, siap dipakai menguji gate.
new_repo() {
  local d="$TEST_TMP/${1:-r$RANDOM}" tc="${2:-true}"
  mkdir -p "$d"
  (
    cd "$d"
    git init -q
    git config user.name test; git config user.email test@example.test
    printf '{"name":"t","scripts":{"test":"%s","build":"true","lint":"true"}}\n' "$tc" > package.json
    AL_HOME="$AL" "$AL/bin/al" init >/dev/null 2>&1
    sed -i.bak 's/approval_ref: PENDING/approval_ref: APR-TEST/' .agent/acceptance-evidence.yaml
    rm -f .agent/*.bak
    git add -A && git commit -q -m init
    # Run sekali supaya lockfile yang ditulis package manager ikut ter-commit;
    # tanpa ini worktree kotor dan setiap gate turun jadi UNKNOWN.
    AL_HOME="$AL" "$AL/bin/al" run smoke >/dev/null 2>&1 || true
    git add -A && git commit -q -m lock 2>/dev/null || true
  )
  printf '%s' "$d"
}

# al_in DIR ARGS... — jalankan CLI di dalam repo, tanpa mengubah cwd pemanggil
al_in() { local d="$1"; shift; ( cd "$d" && AL_HOME="$AL" "$AL/bin/al" "$@" ); }

# decision_of DIR — verdict dari artifact terbaru
decision_of() {
  local a; a=$(ls -t "$1"/.agent/artifacts/*.json 2>/dev/null | head -1) || return 1
  jq -r .verifier_decision "$a"
}

# flags_of DIR — quality_flags dari artifact terbaru, dipisah koma
flags_of() {
  local a; a=$(ls -t "$1"/.agent/artifacts/*.json 2>/dev/null | head -1) || return 1
  jq -r '.quality_flags|join(",")' "$a"
}

# --- reporting --------------------------------------------------------------

# Dipanggil di akhir setiap file test. Exit code menjadi kontrak untuk runner.
test_summary() {
  printf '# %s: pass=%d fail=%d skip=%d\n' "${0##*/}" "$_pass" "$_fail" "$_skipped"
  [ "$_fail" -eq 0 ]
}
