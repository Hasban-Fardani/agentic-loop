# shellcheck shell=bash
# Config layer — SATU sumber untuk semua tunable. Tidak ada nilai yang di-hardcode
# di script lain, dan tidak ada yang perlu diedit manual per-agent/per-harness.
#
# PRESEDENSI (rendah -> tinggi):
#   1. default di file ini
#   2. $AL_CONFIG_HOME/config.env          (default ~/.config/agentic-loop/config.env)
#   3. <repo>/.env                          (git-ignored, JANGAN pernah di-commit)
#   4. environment variable sungguhan        (CI secret store menang atas file)
#
# Presedensi ini disengaja: file .env untuk kenyamanan lokal, environment untuk
# CI. Loader hanya mengisi variabel yang BELUM ter-set, jadi `AL_X=1 al run`
# dan secret CI selalu menang atas file apa pun.
#
# Semua nama variabel berawalan AL_ kecuali yang memang milik tool lain
# (GITHUB_TOKEN, GH_TOKEN). Lihat .env.example untuk daftar lengkap.

[ -n "${_AL_CONFIG_LOADED:-}" ] && return 0
_AL_CONFIG_LOADED=1

# ---------------------------------------------------------------- primitives

# al_set_default KEY VALUE — set hanya bila belum ter-set (termasuk belum ada
# di environment). String kosong dianggap "sudah di-set" secara sengaja.
al_set_default() {
  eval "[ -n \"\${$1+x}\" ]" && return 0
  eval "export $1=\"\$2\""
}

# Nama variabel yang sudah ada di environment sungguhan SEBELUM file apa pun
# dibaca. Ini yang membuat environment selalu menang: file tidak boleh menimpa
# nama yang terkunci, tetapi file berikutnya boleh menimpa file sebelumnya.
if command -v compgen >/dev/null 2>&1; then
  _AL_LOCKED=" $(compgen -e | tr '\n' ' ')"
else
  _AL_LOCKED=" $(env | sed 's/=.*//' | tr '\n' ' ')"
fi

_al_locked() { case "$_AL_LOCKED" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# al_load_env_file FILE — baca KEY=VALUE. File yang dibaca lebih akhir menimpa
# yang lebih awal, tetapi tidak pernah menimpa environment sungguhan.
# Tidak memakai `source`: file .env bukan script, dan tidak boleh bisa
# menjalankan perintah arbitrer.
al_load_env_file() {
  [ -f "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      ''|'#'*) continue ;;
      export\ *) line="${line#export }" ;;
    esac
    case "$line" in
      *=*) : ;;
      *) continue ;;
    esac
    key="${line%%=*}"
    val="${line#*=}"
    # trim spasi di sekitar key
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    case "$key" in
      ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;;   # tolak nama variabel tak valid
    esac
    _al_locked "$key" && continue
    # buang quote pembungkus dan komentar trailing pada nilai unquoted
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
      *)     val="${val%%[[:space:]]#*}"; val="${val%"${val##*[![:space:]]}"}" ;;
    esac
    eval "export $key=\"\$val\""
  done < "$1"
  unset key val line
}

# al_require KEY... — gagal cepat bila variabel wajib kosong.
al_require() {
  missing=''
  for k in "$@"; do
    eval "v=\${$k:-}"
    [ -n "$v" ] || missing="$missing $k"
  done
  if [ -n "$missing" ]; then
    printf 'ERROR: variabel wajib belum di-set:%s\n' "$missing" >&2
    printf 'Set lewat environment atau %s/.env (lihat .env.example).\n' "${AL_REPO_ROOT:-.}" >&2
    return 1
  fi
}

# ---------------------------------------------------------------- root detect

# AL_HOME = lokasi instalasi agentic-loop (tempat core/ berada).
if [ -z "${AL_HOME:-}" ]; then
  _al_lib_dir="$(cd "${BASH_SOURCE[0]%/*}" 2>/dev/null && pwd)"
  AL_HOME="$(cd "$_al_lib_dir/../.." && pwd)"
  unset _al_lib_dir
fi
export AL_HOME

# AL_REPO_ROOT = repository yang sedang dikerjakan (bukan AL_HOME).
if [ -z "${AL_REPO_ROOT:-}" ]; then
  AL_REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
export AL_REPO_ROOT

al_set_default AL_CONFIG_HOME "${XDG_CONFIG_HOME:-$HOME/.config}/agentic-loop"

# ---------------------------------------------------------------- file cascade

al_load_env_file "$AL_CONFIG_HOME/config.env"
al_load_env_file "$AL_REPO_ROOT/.env"

# ---------------------------------------------------------------- defaults

# Layout di dalam repo target. Semua path relatif terhadap AL_REPO_ROOT.
al_set_default AL_AGENT_DIR       ".agent"
al_set_default AL_ARTIFACT_DIR    "$AL_AGENT_DIR/artifacts"
al_set_default AL_LOG_DIR         "$AL_AGENT_DIR/logs"
al_set_default AL_EVENT_LOG       "$AL_AGENT_DIR/events.jsonl"
al_set_default AL_MANIFEST        "$AL_AGENT_DIR/evidence.yaml"
al_set_default AL_ACCEPTANCE_MAP  "$AL_AGENT_DIR/acceptance-evidence.yaml"
al_set_default AL_POLICY_FILE     "$AL_AGENT_DIR/agent-policy.yaml"
al_set_default AL_ADAPTER_DIR     "scripts/evidence"

# Evidence behaviour.
al_set_default AL_PROFILE            "standard"
al_set_default AL_POLICY_VERSION     "policy-v7.1"
al_set_default AL_CONTRACT_VERSION   "evidence-v1"
al_set_default AL_TIMEOUT_DEFAULT    "900"
al_set_default AL_RISK_TIER          "low"
al_set_default AL_TASK_ID            "TASK-000"
al_set_default AL_STRICT_WORKTREE    "1"     # 1 = worktree kotor -> UNKNOWN
al_set_default AL_STRICT_ACCEPTANCE  "1"     # 1 = human_only tanpa approval -> UNKNOWN

# Retention. Artifact TIDAK ikut dihapus oleh cleanup log.
al_set_default AL_LOG_RETENTION_DAYS      "7"
al_set_default AL_ARTIFACT_RETENTION_DAYS "365"
al_set_default AL_LEGAL_HOLD              "0"

# Scanner. Pola bisa ditambah tanpa mengubah script.
al_set_default AL_SECRET_PATTERN "(AKIA[0-9A-Z]{16})|(ghp_[A-Za-z0-9]{36})|(github_pat_[A-Za-z0-9_]{22,})|(sk-[A-Za-z0-9]{20,})|(-----BEGIN [A-Z ]*PRIVATE KEY-----)|(xox[baprs]-[A-Za-z0-9-]{10,})|(AIza[0-9A-Za-z_-]{35})"
al_set_default AL_PII_PATTERN    "([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})|(\+[0-9]{10,15})"
# Bentuk yang TAMPAK seperti PII tetapi memang bukan: domain yang direservasi
# RFC 2606/6761 untuk dokumentasi, dan user VCS pada URL SSH (git@, hg@, svn@).
# Boundary di depan `git@` wajib, kalau tidak alamat sungguhan seperti
# "digit@foo.com" ikut ter-allowlist karena berakhiran "git@".
# Hanya diterapkan pada pass PII, tidak pada pass secret, supaya sebuah baris
# tidak bisa menyembunyikan credential dengan menyelipkan alamat contoh.
al_set_default AL_PII_ALLOW      "@example\.(com|net|org)|@[A-Za-z0-9.-]*\.(test|invalid|localhost|example)([^A-Za-z0-9.-]|\$)|(^|[^A-Za-z0-9._%+-])(git|hg|svn)@|noreply@|@localhost"
al_set_default AL_SCAN_EXCLUDE   ".git|node_modules|vendor|dist|build|target|.venv|$AL_ARTIFACT_DIR|$AL_LOG_DIR"
al_set_default AL_SCAN_MAX_FILE_KB "1024"
al_set_default AL_FIXTURE_DIR    "tests/fixtures"
al_set_default AL_ALLOW_FIXTURE_SECRETS "0"

# Nama variabel yang nilainya WAJIB diredaksi dari log/output/artifact.
# Daftar nama, bukan nilai. Tambah di sini atau lewat AL_SECRET_VARS di .env.
al_set_default AL_SECRET_VARS "GITHUB_TOKEN GH_TOKEN AL_GITHUB_TOKEN GITLAB_TOKEN NPM_TOKEN AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY XAI_API_KEY OPENROUTER_API_KEY HF_TOKEN SLACK_TOKEN TELEGRAM_BOT_TOKEN DATABASE_URL"

# Git/forge. Token TIDAK punya default — memang harus dari environment.
al_set_default AL_GIT_REMOTE       "origin"
al_set_default AL_PROTECTED_BRANCH "main"
al_set_default AL_BRANCH_PREFIX    "agent"
al_set_default AL_FORGE            "github"
# GITHUB_TOKEN / GH_TOKEN / AL_GITHUB_TOKEN: sengaja tanpa default.

# Harness install target. Installer memakai ini; nol edit manual per agent.
al_set_default AL_CLAUDE_HOME   "$HOME/.claude"
al_set_default AL_CODEX_HOME    "$HOME/.codex"
al_set_default AL_HERMES_HOME   "$HOME/.hermes"
al_set_default AL_OPENCODE_HOME "$HOME/.config/opencode"
al_set_default AL_CURSOR_DIR    "$AL_REPO_ROOT/.cursor"
al_set_default AL_INSTALL_MODE  "symlink"   # symlink | copy
# Direktori tujuan symlink CLI. Kosongkan (AL_BIN_DIR=) untuk melewati langkah itu.
al_set_default AL_BIN_DIR       ""

# Output.
al_set_default AL_COLOR   "auto"    # auto | always | never
al_set_default AL_QUIET   "0"
al_set_default AL_DRY_RUN "0"

unset -f al_load_env_file 2>/dev/null || true
