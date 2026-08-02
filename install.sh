#!/usr/bin/env bash
# agentic-loop installer — pasang skills + CLI ke harness apa pun.
#
#   ./install.sh                 # deteksi otomatis, pasang ke semua yang ada
#   ./install.sh claude codex    # hanya harness tertentu
#   ./install.sh --dry-run       # tampilkan rencana, tidak menulis apa pun
#   ./install.sh --uninstall     # lepas kembali
#   ./install.sh --mode copy     # snapshot beku, bukan symlink
#
# Idempoten: menjalankan dua kali tidak menduplikasi apa pun.
# Semua path dari env (AL_CLAUDE_HOME, dst) — lihat .env.example.
set -Eeuo pipefail

AL_HOME="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
export AL_HOME
# shellcheck source=core/lib/config.sh
. "$AL_HOME/core/lib/config.sh"
. "$AL_HOME/core/lib/redact.sh"

UNINSTALL=0
TARGETS=""
ALL_HARNESSES="claude codex cursor hermes opencode agents"

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall)  UNINSTALL=1 ;;
    --dry-run|-n) AL_DRY_RUN=1 ;;
    --mode)       shift; AL_INSTALL_MODE="${1:?--mode butuh symlink|copy}" ;;
    --mode=*)     AL_INSTALL_MODE="${1#--mode=}" ;;
    --help|-h)
      sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)           al_die "opsi tidak dikenal: $1" ;;
    *)            TARGETS="$TARGETS $1" ;;
  esac
  shift
done
export AL_DRY_RUN AL_INSTALL_MODE

case "$AL_INSTALL_MODE" in
  symlink|copy) : ;;
  *) al_die "AL_INSTALL_MODE harus symlink atau copy, dapat: $AL_INSTALL_MODE" ;;
esac

SRC_SKILLS="$AL_HOME/skills"
[ -d "$SRC_SKILLS" ] || al_die "direktori skills tidak ada: $SRC_SKILLS"

# ---------------------------------------------------------------- primitives

link_or_copy() { # link_or_copy SRC DEST
  src="$1"; dest="$2"
  if [ "${AL_DRY_RUN:-0}" = 1 ]; then
    al_info "DRY-RUN: $AL_INSTALL_MODE $(basename "$src") -> $dest"
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  # Bersihkan target lama apa pun bentuknya, supaya idempoten dan tidak
  # menumpuk symlink bersarang. Kurung wajib: `[ ] || [ ] && rm` bernilai
  # false saat target tidak ada, dan di bawah `set -e` itu membunuh fungsi.
  if [ -e "$dest" ] || [ -L "$dest" ]; then rm -rf "$dest"; fi
  if [ "$AL_INSTALL_MODE" = symlink ]; then
    ln -s "$src" "$dest"
  else
    cp -R "$src" "$dest"
  fi
}

remove_path() { # remove_path DEST
  [ -e "$1" ] || [ -L "$1" ] || return 0
  if [ "${AL_DRY_RUN:-0}" = 1 ]; then al_info "DRY-RUN: rm $1"; return 0; fi
  rm -rf "$1"
}

# install_skill_tree DEST_DIR — pasang setiap skill sebagai <dest>/<name>
install_skill_tree() {
  dest_root="$1"
  n=0
  for d in "$SRC_SKILLS"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name="$(basename "$d")"
    link_or_copy "${d%/}" "$dest_root/$name"
    n=$((n+1))
  done
  printf '%s' "$n"
}

uninstall_skill_tree() {
  dest_root="$1"
  for d in "$SRC_SKILLS"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    remove_path "$dest_root/$(basename "$d")"
  done
}

# write_file_if_absent DEST CONTENT — jangan pernah menimpa file user.
write_file_if_absent() {
  dest="$1"; content="$2"
  if [ -e "$dest" ]; then al_debug "ada, dilewati: $dest"; return 0; fi
  if [ "${AL_DRY_RUN:-0}" = 1 ]; then al_info "DRY-RUN: tulis $dest"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  printf '%s\n' "$content" > "$dest"
  al_info "tulis $dest"
}

# ---------------------------------------------------------------- harnesses
#
# Path diverifikasi dari dokumentasi masing-masing harness; lihat
# docs/HARNESS-MATRIX.md untuk sumbernya. Semua bisa dioverride lewat env.

detect() { # detect NAME -> 0 bila harness tampak terpasang
  case "$1" in
    claude)   [ -d "$AL_CLAUDE_HOME" ] || command -v claude   >/dev/null 2>&1 ;;
    codex)    [ -d "$AL_CODEX_HOME" ]  || command -v codex    >/dev/null 2>&1 ;;
    hermes)   [ -d "$AL_HERMES_HOME" ] || command -v hermes   >/dev/null 2>&1 ;;
    opencode) [ -d "$AL_OPENCODE_HOME" ] || command -v opencode >/dev/null 2>&1 ;;
    cursor)   [ -d "$AL_CURSOR_DIR" ]  || command -v cursor   >/dev/null 2>&1 ;;
    agents)   return 0 ;;   # AGENTS.md selalu relevan: standar terbuka
    *) return 1 ;;
  esac
}

skills_dir_for() {
  case "$1" in
    claude)   printf '%s/skills' "$AL_CLAUDE_HOME" ;;
    codex)    printf '%s/skills' "$AL_CODEX_HOME" ;;
    hermes)   printf '%s/skills' "$AL_HERMES_HOME" ;;
    opencode) printf '%s/skills' "$AL_OPENCODE_HOME" ;;
    *) return 1 ;;
  esac
}

do_install() {
  h="$1"
  case "$h" in
    claude|codex|hermes|opencode)
      dir="$(skills_dir_for "$h")"
      cnt="$(install_skill_tree "$dir")"
      al_ok "$h: $cnt skill -> $dir"
      # `if`, bukan `&&`: sebuah && yang gagal di akhir fungsi mengembalikan 1
      # dan `set -e` di pemanggil akan menghentikan seluruh install.
      if [ "$h" = opencode ]; then
        al_info "  catatan: opencode juga menerima skills.paths di opencode.json"
      fi
      ;;
    cursor)
      # Cursor memakai .cursor/rules/*.mdc dengan frontmatter berbeda, jadi
      # SKILL.md tidak bisa disimlink apa adanya. Kita hasilkan pointer tipis
      # yang mengarahkan agent ke sumber aslinya — satu sumber kebenaran tetap.
      dir="$AL_CURSOR_DIR/rules"
      if [ "${AL_DRY_RUN:-0}" = 1 ]; then
        al_info "DRY-RUN: tulis $dir/agentic-loop.mdc"
      else
        mkdir -p "$dir"
        {
          printf -- '---\n'
          printf 'description: Evidence gate, risk gate, and secret safety for agentic changes\n'
          printf 'alwaysApply: false\n'
          printf -- '---\n\n'
          printf '# agentic-loop\n\n'
          printf 'Skill sources live in `%s`.\n\n' "$SRC_SKILLS"
          for d in "$SRC_SKILLS"/*/; do
            [ -f "$d/SKILL.md" ] || continue
            printf -- '- `%s/SKILL.md`\n' "${d%/}"
          done
          printf '\nRead the relevant SKILL.md before acting on evidence, risk, or secrets.\n'
        } > "$dir/agentic-loop.mdc"
        al_ok "cursor: pointer rule -> $dir/agentic-loop.mdc"
      fi
      ;;
    agents)
      # AGENTS.md adalah standar terbuka (Codex, Cursor, opencode, Zed, Aider,
      # Copilot, Gemini CLI, dll). Aturan: file terdekat menang, jadi kita hanya
      # menulis bila belum ada — tidak pernah menimpa milik user.
      write_file_if_absent "$AL_REPO_ROOT/AGENTS.md" "$(cat "$AL_HOME/core/templates/AGENTS.md")"
      al_ok "agents: AGENTS.md di $AL_REPO_ROOT"
      ;;
  esac
}

do_uninstall() {
  h="$1"
  case "$h" in
    claude|codex|hermes|opencode)
      dir="$(skills_dir_for "$h")"
      uninstall_skill_tree "$dir"
      al_ok "$h: skill dilepas dari $dir" ;;
    cursor)
      remove_path "$AL_CURSOR_DIR/rules/agentic-loop.mdc"
      al_ok "cursor: pointer rule dilepas" ;;
    agents)
      al_warn "agents: AGENTS.md TIDAK dihapus otomatis (bisa berisi editanmu)" ;;
  esac
}

# ---------------------------------------------------------------- main

[ -n "$TARGETS" ] || {
  for h in $ALL_HARNESSES; do
    detect "$h" && TARGETS="$TARGETS $h"
  done
}
[ -n "$TARGETS" ] || al_die "tidak ada harness terdeteksi; sebut eksplisit: ./install.sh claude"

for h in $TARGETS; do
  case " $ALL_HARNESSES " in
    *" $h "*) : ;;
    *) al_die "harness tidak dikenal: $h (pilih: $ALL_HARNESSES)" ;;
  esac
done

al_info "mode=$AL_INSTALL_MODE dry_run=${AL_DRY_RUN:-0} target=${TARGETS# }"

for h in $TARGETS; do
  if [ "$UNINSTALL" = 1 ]; then do_uninstall "$h"; else do_install "$h"; fi
done

if [ "$UNINSTALL" = 1 ]; then
  al_ok "uninstall selesai"
  exit 0
fi

# CLI di PATH. AL_BIN_DIR menang; kalau kosong, pakai direktori bin user yang
# sudah ada. Set AL_BIN_DIR=- untuk melewati langkah ini sama sekali.
if [ "${AL_BIN_DIR:-}" = "-" ]; then
  al_info "cli: dilewati (AL_BIN_DIR=-)"
else
  for bindir in ${AL_BIN_DIR:+"$AL_BIN_DIR"} "$HOME/.local/bin" "$HOME/bin"; do
    [ -d "$bindir" ] || continue
    link_or_copy "$AL_HOME/bin/al" "$bindir/al"
    al_ok "cli: al -> $bindir/al"
    break
  done
fi

cat <<EOF

Selesai. Langkah berikutnya:

  1. Salin config contoh (JANGAN commit .env):
       cp $AL_HOME/.env.example <repo>/.env
  2. Periksa konfigurasi efektif:
       $AL_HOME/bin/al doctor
  3. Pasang evidence contract di repo target:
       cd <repo> && $AL_HOME/bin/al init
  4. Jalankan gate:
       $AL_HOME/bin/al run standard

Semua tunable lewat environment atau .env. Tidak ada yang perlu diedit
per-agent: satu sumber di $SRC_SKILLS dipakai semua harness.
EOF
