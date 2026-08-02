#!/usr/bin/env bash
# al discovery — catat bukti pencarian reuse sebelum menulis kode.
#
# Yang sebenarnya diperbaiki di sini bukan daya cari, tapi paksaan untuk mencari.
# Riset ke tiga tool code-intelligence (serena, codegraph, understand-anything)
# menunjukkan tidak satu pun menjawab "apakah sudah ada kode yang fungsinya
# sama" — semuanya menjawab "di mana simbol X". Jadi retrieval yang lebih canggih
# tidak menolong kalau tidak ada yang memaksa agent melihat lebih dulu.
#
# Karena itu command ini memaksa artifact, bukan mengklaim kepastian:
#   - `start` menyiapkan record berisi command yang benar-benar dijalankan
#   - `verify` menolak record yang kosong atau tanpa kandidat yang diperiksa
#   - kesimpulan "tidak ada yang bisa dipakai ulang" wajib menyebut apa yang
#     dicari; ia diberi label confidence, bukan disajikan sebagai fakta
#
# Exit: 0 record lengkap, 1 record cacat/kurang, 2 record tidak ada (UNKNOWN).
set -Eeuo pipefail
. "${BASH_SOURCE[0]%/*}/../lib/bootstrap.sh"
. "${BASH_SOURCE[0]%/*}/../lib/optional.sh"
al_need git || exit 2

ACTION="${1:-verify}"
[ $# -gt 0 ] && shift || true

TASK="$AL_TASK_ID"
QUERY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --task)  shift; TASK="${1:?--task butuh nilai}" ;;
    --query) shift; QUERY="${1:?--query butuh nilai}" ;;
    --task=*)  TASK="${1#--task=}" ;;
    --query=*) QUERY="${1#--query=}" ;;
    *) al_die "argumen tidak dikenal: $1" ;;
  esac
  shift
done

DIR="$AL_REPO_ROOT/$AL_DISCOVERY_DIR"
REC="$DIR/$TASK.md"

case "$ACTION" in
start)
  [ -n "$QUERY" ] || al_die "usage: al discovery start --query <apa yang dicari> [--task ID]"

  # Recall berlapis, semuanya dari tool yang sudah ada. Tanpa dependency baru:
  #   1. git grep case-insensitive untuk istilah utuh
  #   2. token dipecah, supaya "reportDownload" ketemu lewat "download"
  #   3. riwayat git, supaya implementasi yang pernah dihapus/dipindah terlihat
  # Kalau codegraph terpasang dan sudah ter-index, hasilnya ditambahkan sebagai
  # kandidat berkualitas lebih tinggi — bukan pengganti.
  hits_exact=$(git -C "$AL_REPO_ROOT" grep -rn -i -I --heading -- "$QUERY" 2>/dev/null | head -40 || true)

  tokens=$(printf '%s' "$QUERY" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '\n' \
    | awk 'length($0)>=4' | sort -u | head -6)
  hits_token=""
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    h=$(git -C "$AL_REPO_ROOT" grep -rln -i -I -- "$tok" 2>/dev/null | head -8 || true)
    [ -n "$h" ] && hits_token="$hits_token
  ## token: $tok
$(printf '%s\n' "$h" | sed 's/^/  - /')"
  done <<EOF
$tokens
EOF

  hist=$(git -C "$AL_REPO_ROOT" log --oneline -S"$QUERY" --pickaxe-regex -i -20 2>/dev/null | head -12 || true)

  cg=""
  cg_state="absent"
  if al_have_codegraph >/dev/null 2>&1; then
    cg_state="available"
    CG="$(al_have_codegraph)"
    # `|| true`: index yang belum siap tidak boleh mematikan pembuatan record.
    cg=$("$CG" query "$QUERY" --json 2>/dev/null | head -60 || true)
  fi

  deps=""
  for m in package.json composer.json go.mod Cargo.toml pyproject.toml requirements.txt Gemfile; do
    [ -f "$AL_REPO_ROOT/$m" ] && deps="$deps $m"
  done

  if [ "${AL_DRY_RUN:-0}" = 1 ]; then
    al_info "DRY-RUN: tulis $AL_DISCOVERY_DIR/$TASK.md"
    exit 0
  fi
  mkdir -p "$DIR"

  {
    printf '# Discovery — %s\n\n' "$TASK"
    printf '## Query\n%s\n\n' "$QUERY"

    printf '## Searches performed\n'
    printf -- '- `git grep -rn -i -- %s`\n' "'$QUERY'"
    printf -- '- token split: %s\n' "$(printf '%s' "$tokens" | tr '\n' ' ')"
    printf -- '- `git log -S %s` (implementasi yang pernah ada)\n' "'$QUERY'"
    printf -- '- codegraph: %s\n\n' "$cg_state"

    printf '## Raw hits\n\n### exact\n'
    if [ -n "$hits_exact" ]; then printf '```\n%s\n```\n' "$hits_exact"
    else printf '(tidak ada)\n'; fi
    printf '\n### by token\n'
    if [ -n "$hits_token" ]; then printf '%s\n' "$hits_token"
    else printf '(tidak ada)\n'; fi
    printf '\n### git history\n'
    if [ -n "$hist" ]; then printf '```\n%s\n```\n' "$hist"
    else printf '(tidak ada)\n'; fi
    if [ -n "$cg" ]; then printf '\n### codegraph\n```json\n%s\n```\n' "$cg"; fi

    printf '\n## Closest existing patterns\n'
    printf '<!-- WAJIB DIISI MANUSIA/AGENT: minimal dua entri, atau satu\n'
    printf '     justifikasi eksplisit kenapa tidak ada kandidat sama sekali.\n'
    printf '     Format: `path:line` — kenapa cocok / kenapa tidak. -->\n'
    printf -- '- \n- \n\n'

    printf '## Installed dependency check\n'
    printf 'Manifest ditemukan:%s\n' "${deps:- (tidak ada)}"
    printf '<!-- WAJIB: sebut dependency terpasang yang mungkin sudah punya\n'
    printf '     kapabilitas ini tetapi belum dipakai. -->\n\n'

    printf '## Conclusion\n'
    printf '<!-- reuse | extend | no-suitable-reuse -->\n\n'

    printf '## Confidence\n'
    if [ "$cg_state" = available ]; then
      printf 'symbol-graph-assisted\n\n'
    else
      printf 'command-fallback\n\n'
    fi
    printf '<!-- command-fallback TIDAK membuktikan tidak ada kode serupa.\n'
    printf '     Ia hanya membuktikan pencarian yang terdaftar di atas tidak\n'
    printf '     menemukan hasil yang cocok. -->\n\n'

    printf '## Evidence references\n'
    printf -- '- commit: %s\n' "$(git -C "$AL_REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
    printf -- '- generated: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$REC"

  al_ok "discovery: $AL_DISCOVERY_DIR/$TASK.md"
  al_info "isi bagian 'Closest existing patterns' dan 'Conclusion' sebelum membuka PR"
  ;;

verify)
  if [ ! -f "$REC" ]; then
    printf 'discovery: record tidak ada untuk %s\n' "$TASK" >&2
    printf 'discovery: jalankan `al discovery start --query "<fitur>"` lebih dulu\n' >&2
    exit 2
  fi

  bad=0
  need() { grep -q "^## $1" "$REC" || { printf 'discovery: bagian hilang: %s\n' "$1" >&2; bad=1; }; }
  for s in "Query" "Searches performed" "Closest existing patterns" \
           "Installed dependency check" "Conclusion" "Confidence"; do
    need "$s"
  done

  # Isi, bukan hanya heading. Template yang belum diisi harus gagal, karena
  # record kosong yang lolos gate justru mengajari agent bahwa gate ini teater.
  #
  # `|| true` di akhir sec() wajib: grep -v mengembalikan 1 kalau semua baris
  # tersaring, dan di bawah set -e itu mematikan script di tengah pemeriksaan
  # tanpa pesan apa pun.
  #
  # Komentar HTML disaring per-blok, bukan per-baris berawalan `<!--`. Teks
  # instruksi di dalam template membentang beberapa baris dan kebetulan memuat
  # frasa yang dicari pemeriksaan di bawah, jadi filter per-baris membuat
  # template yang belum diisi lolos sebagai "sudah dijustifikasi".
  sec() {
    awk -v s="^## $1\$" '
      $0 ~ s {f=1; next}
      f && /^## / {exit}
      f {
        if (/<!--/) c=1
        if (!c) print
        if (/-->/) c=0
      }
    ' "$REC" | grep -v '^[[:space:]]*$' || true
  }

  cand=$(sec "Closest existing patterns" | grep -cE '^- .+' || true)
  if [ "$cand" -lt 2 ]; then
    # Justifikasi harus berupa item daftar yang benar-benar ditulis, bukan
    # kalimat mana pun yang memuat frasanya.
    just=$(sec "Closest existing patterns" \
             | grep -cE '^- .*(tidak ada kandidat|no candidate)' || true)
    if [ "$just" -eq 0 ]; then
      printf 'discovery: butuh >=2 kandidat diperiksa, atau item justifikasi eksplisit (ada: %s)\n' "$cand" >&2
      bad=1
    fi
  fi

  concl=$(sec "Conclusion" | head -1)
  case "$concl" in
    reuse|extend|no-suitable-reuse) : ;;
    *) printf 'discovery: Conclusion harus reuse|extend|no-suitable-reuse, dapat: %s\n' "${concl:-<kosong>}" >&2
       bad=1 ;;
  esac

  conf=$(sec "Confidence" | head -1)
  case "$conf" in
    command-fallback|symbol-graph-assisted) : ;;
    *) printf 'discovery: Confidence harus command-fallback|symbol-graph-assisted, dapat: %s\n' "${conf:-<kosong>}" >&2
       bad=1 ;;
  esac

  searches=$(sec "Searches performed" | grep -cE '^- ' || true)
  if [ "$searches" -lt 2 ]; then
    printf 'discovery: butuh >=2 pencarian tercatat (ada: %s)\n' "$searches" >&2
    bad=1
  fi

  if [ "$bad" -ne 0 ]; then
    printf 'discovery: record cacat: %s\n' "$AL_DISCOVERY_DIR/$TASK.md" >&2
    exit 1
  fi
  al_ok "discovery: record lengkap ($concl, confidence=$conf)"
  ;;

show)
  [ -f "$REC" ] || { printf 'discovery: tidak ada record untuk %s\n' "$TASK" >&2; exit 2; }
  cat "$REC" ;;

*) al_die "usage: al discovery [start|verify|show] [--task ID] [--query TEXT]" ;;
esac
