# shellcheck shell=bash
# Deteksi tool opsional. Satu tempat, supaya tiap command tidak menulis ulang
# logika "ada/tidak ada" dan tidak ada yang diam-diam menganggap absen = lulus.
#
# Kontrak: fungsi al_have_* mengembalikan 0 bila tool benar-benar dapat dipakai,
# dan mencetak apa pun. Pemanggil yang memutuskan absen itu UNKNOWN atau no_op.

[ -n "${_AL_OPTIONAL_LOADED:-}" ] && return 0
_AL_OPTIONAL_LOADED=1

# al_resolve VAR CMD... — pakai override env kalau ada, kalau tidak cari di PATH.
# Override wajib dihormati supaya CI bisa menunjuk binary tertentu tanpa mengubah
# PATH global, dan supaya test bisa menyuntikkan stub.
al_resolve() {
  _var="$1"; shift
  eval "_ov=\${$_var:-}"
  if [ -n "$_ov" ]; then
    # Override bernilai '-' berarti "anggap tidak ada", untuk menguji degradasi.
    [ "$_ov" = "-" ] && return 1
    command -v "$_ov" >/dev/null 2>&1 && { printf '%s' "$_ov"; return 0; }
    return 1
  fi
  for _c in "$@"; do
    command -v "$_c" >/dev/null 2>&1 && { printf '%s' "$_c"; return 0; }
  done
  return 1
}

# lizard: cyclomatic complexity lintas bahasa. Satu-satunya tool yang menutup
# PHP+JS+TS+Go+Python+Rust dalam satu paket dengan threshold per-fungsi dan
# exit code non-nol. Diverifikasi: `-C n --warnings_only` exit 1 saat breach.
al_have_lizard() { al_resolve AL_LIZARD_COMMAND lizard; }

# codegraph: symbol graph + FTS5 lewat CLI yang benar-benar scriptable
# (`query --json`, `explore`, `affected --stdin`). Dipakai sebagai penguat recall
# discovery, bukan pengganti — ia menjawab "di mana simbol X", bukan
# "apakah ada kode yang fungsinya sama".
al_have_codegraph() {
  al_resolve AL_CODEGRAPH_COMMAND codegraph || return 1
  # Tanpa index per-project, CLI-nya tidak punya apa pun untuk dijawab.
  [ -d "$AL_REPO_ROOT/.codegraph" ] || return 1
}

# understand-anything: graph-nya JSON yang di-commit, jadi bisa dibaca gratis
# dengan jq bila kebetulan ada. TIDAK dipakai sebagai gate: lapisan LLM-nya
# non-deterministik dan berbiaya token.
al_have_ua_graph() { [ -f "$AL_REPO_ROOT/.ua/knowledge-graph.json" ]; }

# al_tool_state NAME — laporkan status tool untuk doctor/artifact.
al_tool_state() {
  case "$1" in
    lizard)    al_have_lizard    >/dev/null 2>&1 && echo available || echo absent ;;
    codegraph) al_have_codegraph >/dev/null 2>&1 && echo available || echo absent ;;
    ua)        al_have_ua_graph  >/dev/null 2>&1 && echo available || echo absent ;;
    *) echo unknown ;;
  esac
}
