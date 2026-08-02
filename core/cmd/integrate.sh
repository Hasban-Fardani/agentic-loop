#!/usr/bin/env bash
# al integrate — kelola integrasi skill upstream pinned, non-vendored.
#
# Kontrak:
#   - Tidak pernah clone/copy isi skill upstream ke dalam repo target.
#   - Hanya catatan manifest (url, ref, nama, daftar file referensi, deps) di
#     $AL_CONFIG_HOME/integrations/<name>.json.
#   - Ref HARUS pinned (commit SHA/tag), bukan branch bergerak.
#   - Integrasi opsional; gate tetap lokal. Upstream adalah referensi perilaku,
#     bukan dependensi build.
set -Eeuo pipefail

source "$AL_HOME/core/lib/config.sh"
source "$AL_HOME/core/lib/optional.sh"
source "$AL_HOME/core/lib/redact.sh"
source "$AL_HOME/core/lib/util.sh"

INTEGRATIONS_DIR="${AL_CONFIG_HOME}/integrations"
mkdir -p "$INTEGRATIONS_DIR"

usage() {
  cat <<'EOF'
al integrate — kelola skill upstream pinned (opsional, non-vendored)

USAGE
  al integrate add <url>[@<ref>] <name>   catat upstream baru
  al integrate list                        tampilkan manifest
  al integrate doctor [<name>]             laporkan pin dan kesehatan deps
  al integrate sync <name>               tarik ulang daftar file ke cache lokal

CONTOH
  al integrate add https://github.com/Panniantong/agent-reach@b4d52c4 agent-reach
  al integrate add https://github.com/upstash/context7@594a731 context7
EOF
}

al_err() { printf 'ERROR: %s\n' "$1" >&2; }
al_info() { printf '%s\n' "$1"; }

_parse_url_ref() {
  local raw="$1"
  local url ref
  if [[ "$raw" =~ @ ]]; then
    url="${raw%@*}"
    ref="${raw##*@}"
  else
    url="$raw"
    ref=""
  fi
  printf '%s\t%s\n' "$url" "$ref"
}

_resolve_github_api() {
  local url="$1"
  local repo api
  case "$url" in
    https://github.com/*)
      repo="${url#https://github.com/}"
      printf 'https://api.github.com/repos/%s' "${repo%/}"
      ;;
    git@github.com:*)
      repo="${url#git@github.com:}"
      printf 'https://api.github.com/repos/%s' "${repo%.git}"
      ;;
    *) return 1 ;;
  esac
}

_fetch_ref_sha() {
  local api="$1" ref="$2"
  local sha
  sha=$(curl -fsSL -H "Accept: application/vnd.github+json" \
            -H "User-Agent: agentic-loop" \
            "${api}/commits/${ref}" 2>/dev/null \
        | jq -r '.sha // empty') || true
  if [ -z "$sha" ] || [ "$sha" = "null" ]; then
    # try tag
    sha=$(curl -fsSL -H "Accept: application/vnd.github+json" \
              -H "User-Agent: agentic-loop" \
              "${api}/git/refs/tags/${ref}" 2>/dev/null \
          | jq -r '.object.sha // empty') || true
  fi
  printf '%s' "$sha"
}

_integrate_add() {
  local raw="$1" name="$2"
  local url ref api default_branch pinned

  read -r url ref <<< "$(_parse_url_ref "$raw")"
  [ -n "$url" ] || { al_err "URL tidak valid: $raw"; exit 64; }
  [ -n "$name" ] || { al_err "nama integrasi wajib diisi"; exit 64; }
  case "$name" in *[!A-Za-z0-9_-]*) al_err "nama hanya boleh alphanumeric, -, _"; exit 64 ;; esac

  api=$(_resolve_github_api "$url") || { al_err "hanya GitHub URL yang didukung"; exit 64; }

  if [ -z "$ref" ]; then
    default_branch=$(curl -fsSL -H "Accept: application/vnd.github+json" \
                            -H "User-Agent: agentic-loop" \
                            "$api" 2>/dev/null \
                     | jq -r '.default_branch // empty') || true
    [ -n "$default_branch" ] || { al_err "gagal membaca default branch"; exit 2; }
    ref="$default_branch"
    al_info "ref tidak diberikan; default branch = $ref"
  fi

  pinned=$(_fetch_ref_sha "$api" "$ref")
  if [ -z "$pinned" ]; then
    al_err "gagal resolve ref '$ref' di $url"
    exit 2
  fi
  if [ "$pinned" != "$ref" ]; then
    al_info "pin ref: $ref -> ${pinned:0:12}"
  fi

  local manifest="$INTEGRATIONS_DIR/${name}.json"
  local tmp; tmp=$(mktemp)
  jq -n \
    --arg name "$name" \
    --arg url "$url" \
    --arg ref_requested "$ref" \
    --arg ref_pinned "$pinned" \
    --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{
       name: $name,
       url: $url,
       ref_requested: $ref_requested,
       ref_pinned: $ref_pinned,
       updated_at: $updated_at,
       files: [],
       deps: {}
     }' > "$tmp"
  mv "$tmp" "$manifest"
  al_info "manifest tersimpan: $manifest"
  # sync files list immediately
  _integrate_sync "$name"
}

_integrate_list() {
  local f
  if [ ! -d "$INTEGRATIONS_DIR" ] || [ -z "$(find "$INTEGRATIONS_DIR" -maxdepth 1 -name '*.json' -print -quit 2>/dev/null)" ]; then
    al_info "belum ada integrasi upstream"
    return 0
  fi
  printf '%-20s %-12s %-46s %s\n' NAME REF URL UPDATED
  for f in "$INTEGRATIONS_DIR"/*.json; do
    [ -f "$f" ] || continue
    local name url ref upd
    name=$(jq -r '.name // empty' "$f")
    url=$(jq -r '.url // empty' "$f")
    ref=$(jq -r '.ref_pinned[0:12] // empty' "$f")
    upd=$(jq -r '.updated_at // empty' "$f")
    printf '%-20s %-12s %-46s %s\n' "$name" "$ref" "$url" "$upd"
  done
}

_integrate_sync() {
  local name="$1"
  local manifest="$INTEGRATIONS_DIR/${name}.json"
  [ -f "$manifest" ] || { al_err "integrasi '$name' tidak ditemukan"; exit 2; }

  local url ref api tree_sha files_json tmp
  url=$(jq -r '.url' "$manifest")
  ref=$(jq -r '.ref_pinned' "$manifest")
  api=$(_resolve_github_api "$url") || { al_err "hanya GitHub URL yang didukung"; exit 64; }

  files_json=$(curl -fsSL -H "Accept: application/vnd.github+json" \
                        -H "User-Agent: agentic-loop" \
                        "${api}/git/trees/${ref}?recursive=1" 2>/dev/null \
               | jq '[.tree[] | select(.type=="blob") | {path: .path, size: .size, type: .type}]')

  tmp=$(mktemp)
  jq --argjson files "$files_json" --arg updated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.files = $files | .updated_at = $updated_at' "$manifest" > "$tmp"
  mv "$tmp" "$manifest"
  local count
  count=$(printf '%s' "$files_json" | jq 'length')
  al_info "'$name': $count file diindeks pada ${ref:0:12}"
}

_integrate_doctor() {
  local name="${1:-}"
  local files
  if [ -n "$name" ]; then
    files=("$INTEGRATIONS_DIR/${name}.json")
  else
    files=("$INTEGRATIONS_DIR"/*.json)
  fi
  local any=0
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    any=1
    local n url ref req files_count
    n=$(jq -r '.name' "$f")
    url=$(jq -r '.url' "$f")
    ref=$(jq -r '.ref_pinned' "$f")
    req=$(jq -r '.ref_requested' "$f")
    files_count=$(jq '.files | length' "$f")
    printf -- '--- %s ---\n' "$n"
    printf 'url:    %s\n' "$url"
    printf 'pin:    %s (requested: %s)\n' "${ref:0:12}" "$req"
    printf 'files:  %d\n' "$files_count"
    # check reachability
    local api live_sha
    api=$(_resolve_github_api "$url") || { printf 'status: unsupported URL\n'; continue; }
    live_sha=$(_fetch_ref_sha "$api" "$ref") || true
    if [ "$live_sha" = "$ref" ]; then
      printf 'status: reachable\n'
    else
      printf 'status: drift detected (remote ref resolved to %s)\n' "${live_sha:0:12}"
    fi
  done
  [ "$any" -eq 1 ] || al_info "belum ada integrasi upstream"
}

cmd="${1:-help}"
[ $# -gt 0 ] && shift || true

case "$cmd" in
  add)
    [ $# -ge 2 ] || { usage >&2; exit 64; }
    _integrate_add "$1" "$2" ;;
  list)
    _integrate_list ;;
  sync)
    [ $# -ge 1 ] || { usage >&2; exit 64; }
    _integrate_sync "$1" ;;
  doctor)
    _integrate_doctor "${1:-}" ;;
  help|--help|-h|"")
    usage ;;
  *)
    al_err "subcommand tidak dikenal: $cmd"; usage >&2; exit 64 ;;
esac
