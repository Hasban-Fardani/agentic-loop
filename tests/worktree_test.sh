#!/usr/bin/env bash
# al worktree: satu issue = satu branch = satu worktree. Isolasi adalah alasannya,
# jadi validasi nama dan penolakan kerja belum ter-commit adalah inti kontraknya.
. "${BASH_SOURCE[0]%/*}/lib.sh"

mk() {
  local d="$TEST_TMP/${1:-w$RANDOM}/repo"
  mkdir -p "$d"
  ( cd "$d"; git init -q; git config user.name t; git config user.email t@example.test
    echo '{}' > package.json
    AL_HOME="$AL" "$AL/bin/al" init >/dev/null 2>&1
    git add -A; git commit -q -m init )
  printf '%s' "$d"
}
wt() { local d="$1"; shift; ( cd "$d" && AL_HOME="$AL" "$AL/bin/al" worktree "$@" ); }

R="$(mk basic)"
WROOT="$(dirname "$R")/repo-worktrees"

assert_eq "add membuat worktree" 0 "$(rc_of wt "$R" add 42 add-google-login)"
assert "direktori worktree ada"  test -d "$WROOT/42-add-google-login"
# Nomor issue harus ada di nama branch: itu yang menautkan branch ke Issue,
# sehingga artifact evidence bisa dikaitkan ke task yang benar.
assert_eq "branch memuat tipe/issue/slug" "feat/42-add-google-login" \
  "$(git -C "$WROOT/42-add-google-login" rev-parse --abbrev-ref HEAD)"
assert "worktree punya .agent/ dari base" test -f "$WROOT/42-add-google-login/.agent/evidence.yaml"

assert_eq "issue duplikat ditolak" 1 "$(rc_of wt "$R" add 42 add-google-login)"
assert_contains "list menampilkan worktree" "$(out_of wt "$R" list)" "42-add-google-login"

# Nama dipakai apa adanya di git dan shell, jadi ditolak, bukan dibersihkan.
assert_eq "issue non-numerik ditolak"  1 "$(rc_of wt "$R" add abc slug)"
assert_eq "slug dengan spasi ditolak"  1 "$(rc_of wt "$R" add 43 'Bad Slug')"
assert_eq "slug huruf besar ditolak"   1 "$(rc_of wt "$R" add 43 BadSlug)"
# Regresi: pada locale seperti en_PH.UTF-8 range glob `a-z` ikut mencakup huruf
# besar, sehingga BadSlug lolos. LC_ALL=C yang memperbaikinya.
assert_eq "huruf besar tetap ditolak di locale non-C" 1 \
  "$(LC_ALL=en_PH.UTF-8 rc_of wt "$R" add 43 AlsoBad)"
assert_eq "slug berawalan '-' ditolak" 1 "$(rc_of wt "$R" add 43 -lead)"
assert_eq "slug berakhiran '-' ditolak" 1 "$(rc_of wt "$R" add 43 trail-)"
assert_eq "underscore ditolak"          1 "$(rc_of wt "$R" add 43 u_score)"
assert_eq "tipe non-conventional ditolak" 1 "$(rc_of wt "$R" add 44 ok bogus)"
assert_eq "argumen kurang ditolak"     1 "$(rc_of wt "$R" add 45)"
for tipe in feat fix chore refactor docs test perf; do
  assert_eq "tipe $tipe diterima" 0 "$(rc_of wt "$R" add "10$((RANDOM%90))" "s-$tipe" "$tipe")"
done

# Kerja belum ter-commit hilang bersama worktree; itu tidak reversibel.
echo scratch > "$WROOT/42-add-google-login/dirty.txt"
assert_eq "worktree kotor menolak dihapus" 1 "$(rc_of wt "$R" remove 42 add-google-login)"
assert "worktree kotor tetap ada" test -d "$WROOT/42-add-google-login"
assert_contains "menyebut cara memaksa" "$(out_of wt "$R" remove 42 add-google-login)" "AL_FORCE"

assert_eq "AL_FORCE=1 menghapus" 0 \
  "$(AL_FORCE=1 rc_of wt "$R" remove 42 add-google-login)"
refute "worktree terhapus" test -d "$WROOT/42-add-google-login"
# Branch tanpa commit sendiri sudah tercakup base, jadi `-d` memang menghapusnya.
refute "branch tanpa commit ikut dibersihkan" \
  bash -c 'git -C "$1" branch --list "feat/42-add-google-login" | grep -q .' _ "$R"

# Properti sesungguhnya dari `-d`: branch dengan commit yang belum ter-merge
# TIDAK boleh hilang tanpa disadari. Ini yang membedakan -d dari -D.
wt "$R" add 77 unmerged-work >/dev/null 2>&1
U="$WROOT/77-unmerged-work"
( cd "$U" && echo real > work.txt && git add work.txt \
  && git -c user.name=t -c user.email=t@example.test commit -q -m "real work" )
out=$(AL_FORCE=1 out_of wt "$R" remove 77 unmerged-work)
refute "worktree ter-remove" test -d "$U"
assert "branch belum ter-merge dipertahankan" \
  bash -c 'git -C "$1" branch --list "feat/77-unmerged-work" | grep -q .' _ "$R"
assert_contains "user diberi tahu cara menghapus manual" "$out" "git branch -D"

assert_eq "remove worktree tak ada -> 1" 1 "$(rc_of wt "$R" remove 99 nothing)"
assert_eq "prune selalu 0" 0 "$(rc_of wt "$R" prune)"
assert_eq "action tak dikenal ditolak" 1 "$(rc_of wt "$R" bogus)"

# Dry-run tidak boleh menyentuh filesystem.
D="$(mk dry)"; DROOT="$(dirname "$D")/repo-worktrees"
AL_DRY_RUN=1 wt "$D" add 7 dry-run >/dev/null 2>&1
refute "AL_DRY_RUN tidak membuat worktree" test -d "$DROOT/7-dry-run"
refute "AL_DRY_RUN tidak membuat branch" \
  bash -c 'git -C "$1" branch --list "feat/7-dry-run" | grep -q .' _ "$D"

# Di luar repo git, tidak ada yang bisa dikerjakan.
N="$(new_dir notgit)"
assert_eq "bukan repo git -> 2" 2 "$(rc_of bash -c 'cd "$1" && AL_REPO_ROOT="$1" bash "$2/core/cmd/worktree.sh" list' _ "$N" "$AL")"

test_summary
