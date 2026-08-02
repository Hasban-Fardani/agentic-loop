#!/usr/bin/env bash
# al worktree — satu Issue = satu branch = satu worktree.
#
# Dua task aktif tidak boleh berbagi working directory; itu satu-satunya cara
# mencegah dua agent saling menimpa file. Worktree yang menumpuk adalah context
# debt versi filesystem, jadi `remove` sama pentingnya dengan `add`.
#
#   al worktree add <issue> <slug> [tipe]   buat branch + worktree
#   al worktree list                        worktree milik repo ini
#   al worktree remove <issue> <slug>       hapus worktree + branch lokal
#   al worktree prune                       bersihkan registrasi yang basi
#
# Exit: 0 sukses, 1 gagal, 2 prasyarat tidak terpenuhi.
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"
al_need git || exit 2

ACTION="${1:-list}"
[ $# -gt 0 ] && shift || true

git -C "$AL_REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || { al_err "bukan repository git"; exit 2; }

REPO_NAME="$(basename "$AL_REPO_ROOT")"
al_set_default AL_WORKTREE_ROOT "$(dirname "$AL_REPO_ROOT")/${REPO_NAME}-worktrees"

# validate — nama branch dan direktori dipakai apa adanya di shell dan git,
# jadi karakter di luar [a-z0-9-] ditolak, bukan dibersihkan diam-diam.
#
# LC_ALL=C wajib: pada locale seperti en_PH.UTF-8, range `a-z` di dalam pola
# glob ikut mencakup huruf besar (collation-nya case-insensitive), sehingga
# "BadSlug" lolos. Kolasi C membuat range berarti persis apa yang tertulis.
validate() { # validate ISSUE SLUG
  local issue="$1" slug="$2"
  case "$issue" in
    ''|*[!0-9]*) al_err "nomor issue harus angka, dapat: '$issue'"; return 1 ;;
  esac
  # Harus mulai dan berakhir alfanumerik: `-lead` dan `trail-` menghasilkan nama
  # branch dan direktori yang jelek dan menyulitkan tooling lain.
  if LC_ALL=C expr "$slug" : '[a-z0-9]\([a-z0-9-]*[a-z0-9]\)\{0,1\}$' >/dev/null 2>&1; then
    return 0
  fi
  al_err "slug hanya boleh huruf kecil a-z, 0-9, dan '-' di tengah, dapat: '$slug'"
  return 1
}

wt_path() { printf '%s/%s-%s' "$AL_WORKTREE_ROOT" "$1" "$2"; }
branch_of() { printf '%s/%s-%s' "$1" "$2" "$3"; }

case "$ACTION" in
  add)
    issue="${1:-}"; slug="${2:-}"; tipe="${3:-feat}"
    [ -n "$issue" ] && [ -n "$slug" ] || al_die "usage: al worktree add <issue> <slug> [tipe]"
    validate "$issue" "$slug" || exit 1
    case "$tipe" in
      feat|fix|chore|refactor|docs|test|perf) : ;;
      *) al_die "tipe harus Conventional Commits: feat|fix|chore|refactor|docs|test|perf" ;;
    esac

    branch="$(branch_of "$tipe" "$issue" "$slug")"
    path="$(wt_path "$issue" "$slug")"

    # Nomor issue wajib ada di nama branch: itu yang menautkan branch ke Issue
    # dan membuat artifact evidence bisa dikaitkan ke task yang benar.
    if git -C "$AL_REPO_ROOT" show-ref --verify -q "refs/heads/$branch"; then
      al_die "branch sudah ada: $branch"
    fi
    [ -e "$path" ] && al_die "path sudah dipakai: $path"

    base="${AL_BASE_REF:-$AL_GIT_REMOTE/$AL_PROTECTED_BRANCH}"
    git -C "$AL_REPO_ROOT" rev-parse --verify -q "$base" >/dev/null 2>&1 \
      || base="$AL_PROTECTED_BRANCH"
    git -C "$AL_REPO_ROOT" rev-parse --verify -q "$base" >/dev/null 2>&1 \
      || { al_err "base ref tidak ditemukan: $base"; exit 2; }

    if [ "${AL_DRY_RUN:-0}" = 1 ]; then
      al_info "DRY-RUN: git worktree add $path -b $branch $base"
      exit 0
    fi
    mkdir -p "$AL_WORKTREE_ROOT"
    git -C "$AL_REPO_ROOT" worktree add "$path" -b "$branch" "$base" >/dev/null \
      || { al_err "gagal membuat worktree"; exit 1; }
    al_ok "worktree: $path"
    al_info "branch:   $branch (dari $base)"
    al_info "berikutnya: cd $path && al run smoke"
    ;;

  list)
    # Hanya baris worktree, tanpa metadata git internal.
    git -C "$AL_REPO_ROOT" worktree list
    ;;

  remove)
    issue="${1:-}"; slug="${2:-}"
    [ -n "$issue" ] && [ -n "$slug" ] || al_die "usage: al worktree remove <issue> <slug>"
    validate "$issue" "$slug" || exit 1
    path="$(wt_path "$issue" "$slug")"
    [ -e "$path" ] || { al_err "worktree tidak ada: $path"; exit 1; }

    # Cari branch dari worktree itu sendiri, jangan menebak tipenya.
    branch=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || true)

    # Kerja yang belum ter-commit akan hilang bersama worktree. Itu tidak
    # reversibel, jadi tolak kecuali dipaksa secara eksplisit.
    if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ] && [ "${AL_FORCE:-0}" != 1 ]; then
      al_err "worktree punya perubahan belum ter-commit: $path"
      al_info "commit dulu, atau AL_FORCE=1 untuk membuangnya"
      exit 1
    fi

    if [ "${AL_DRY_RUN:-0}" = 1 ]; then
      al_info "DRY-RUN: git worktree remove $path${branch:+ && git branch -d $branch}"
      exit 0
    fi
    git -C "$AL_REPO_ROOT" worktree remove ${AL_FORCE:+--force} "$path" \
      || { al_err "gagal menghapus worktree"; exit 1; }
    al_ok "worktree dihapus: $path"

    if [ -n "$branch" ] && [ "$branch" != HEAD ]; then
      # -d, bukan -D: branch yang belum ter-merge tidak dihapus tanpa disadari.
      if git -C "$AL_REPO_ROOT" branch -d "$branch" >/dev/null 2>&1; then
        al_ok "branch dihapus: $branch"
      else
        al_warn "branch $branch belum ter-merge; dibiarkan (hapus manual: git branch -D $branch)"
      fi
    fi
    ;;

  prune)
    if [ "${AL_DRY_RUN:-0}" = 1 ]; then
      git -C "$AL_REPO_ROOT" worktree prune --dry-run
    else
      git -C "$AL_REPO_ROOT" worktree prune
      al_ok "registrasi worktree basi dibersihkan"
    fi
    ;;

  *) al_die "usage: al worktree [add|list|remove|prune]" ;;
esac
