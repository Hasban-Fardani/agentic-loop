#!/usr/bin/env bash
# CLI, init, event, clean, doctor. Kontrak permukaan yang dipakai semua harness.
. "${BASH_SOURCE[0]%/*}/lib.sh"

echo "# CLI surface"
assert_eq "version cocok dengan VERSION" "agentic-loop $(cat "$AL/VERSION")" \
  "$("$AL/bin/al" version)"
assert_contains "help menampilkan usage" "$("$AL/bin/al" help)" "al <command>"
assert_contains "help menyebut aturan .env" "$("$AL/bin/al" help)" "Jangan pernah commit .env"
assert_eq "command tak dikenal -> 64" 64 "$(rc_of "$AL/bin/al" bogus)"
for c in run scan event doctor clean decision init verify scope; do
  assert "subcommand $c ada" test -f "$AL/core/cmd/$c.sh"
done
assert "selftest menunjuk runner" test -f "$AL/tests/run.sh"

echo "# init"
D="$(new_dir fresh)"; ( cd "$D" && git init -q )
( cd "$D" && AL_HOME="$AL" "$AL/bin/al" init ) >/dev/null 2>&1
for f in .agent/evidence.yaml .agent/acceptance-evidence.yaml \
         .agent/agent-policy.yaml .agent/scope.yaml scripts/evidence/test.sh; do
  assert "init membuat $f" test -f "$D/$f"
done
assert "adapter executable" test -x "$D/scripts/evidence/test.sh"
assert ".env di-ignore setelah init" bash -c 'grep -qx "/.env" "$1/.gitignore"' _ "$D"
assert ".env.example di-whitelist"   bash -c 'grep -qx "!/.env.example" "$1/.gitignore"' _ "$D"
# Lockfile justru harus di-commit untuk reproducibility.
refute "lockfile tidak di-ignore" grep -qi lock "$D/.gitignore"
assert_contains "init idempoten" \
  "$( cd "$D" && AL_HOME="$AL" "$AL/bin/al" init 2>&1 )" "0 file dibuat"

E="$(new_dir dry)"; ( cd "$E" && git init -q )
( cd "$E" && AL_DRY_RUN=1 AL_HOME="$AL" "$AL/bin/al" init ) >/dev/null 2>&1
assert_eq "AL_DRY_RUN tidak menulis apa pun" 0 \
  "$(find "$E/.agent" "$E/scripts" -type f 2>/dev/null | grep -c '' || true)"

echo "# stack detection"
det() { AL_REPO_ROOT="$1" bash -c ". $AL/core/lib/bootstrap.sh; . $AL/core/lib/detect.sh; echo \$AL_STACK"; }
for pair in node:package.json go:go.mod php:composer.json python:pyproject.toml rust:Cargo.toml; do
  want="${pair%%:*}"; file="${pair#*:}"
  d="$(new_dir "st-$want")"; echo '{}' > "$d/$file"
  assert_eq "stack $want terdeteksi" "$want" "$(det "$d")"
done
d="$(new_dir st-none)"
assert_eq "stack tak dikenal -> unknown" unknown "$(det "$d")"
d="$(new_dir st-ov)"; echo '{}' > "$d/package.json"
assert_eq "AL_CMD_TEST override mengalahkan deteksi" custom \
  "$(AL_REPO_ROOT="$d" AL_CMD_TEST=custom bash -c ". $AL/core/lib/bootstrap.sh; . $AL/core/lib/detect.sh; echo \$AL_CMD_TEST")"

echo "# event log"
V="$(new_dir ev)"; git -C "$V" init -q
ev() { AL_REPO_ROOT="$V" GITHUB_TOKEN="$FAKE_GH" bash "$AL/core/cmd/event.sh" "$@"; }
ev approval actor=h pr_number=7 >/dev/null
n1=$(grep -c '' "$V/.agent/events.jsonl")
ev approval actor=h pr_number=7 >/dev/null
assert_eq "event identik ditekan (idempotency_key)" "$n1" "$(grep -c '' "$V/.agent/events.jsonl")"
ev merge actor=human pr_number=8 >/dev/null
assert_eq "event berbeda tetap ditambah" $((n1+1)) "$(grep -c '' "$V/.agent/events.jsonl")"
assert "setiap baris event JSON valid" jq -e . "$V/.agent/events.jsonl"
refute "event_type tak dikenal ditolak" bash -c 'AL_REPO_ROOT="$1" bash "$2/core/cmd/event.sh" bogus' _ "$V" "$AL"
refute "argumen bukan key=val ditolak" bash -c 'AL_REPO_ROOT="$1" bash "$2/core/cmd/event.sh" merge nokv' _ "$V" "$AL"
ev deploy actor=ci note="tok $FAKE_GH" >/dev/null
refute "nilai event diredaksi" grep -qF "$FAKE_GH" "$V/.agent/events.jsonl"
before=$(grep -c '' "$V/.agent/events.jsonl")
AL_REPO_ROOT="$V" AL_DRY_RUN=1 bash "$AL/core/cmd/event.sh" incident actor=x >/dev/null 2>&1
assert_eq "AL_DRY_RUN tidak menulis event" "$before" "$(grep -c '' "$V/.agent/events.jsonl")"

echo "# retention"
mkdir -p "$V/.agent/logs/old"; touch -t 200001010000 "$V/.agent/logs/old"
mkdir -p "$V/.agent/artifacts"; echo '{}' > "$V/.agent/artifacts/a.json"
AL_REPO_ROOT="$V" AL_DRY_RUN=1 bash "$AL/core/cmd/clean.sh" >/dev/null 2>&1
assert "dry-run tidak menghapus log" test -d "$V/.agent/logs/old"
AL_REPO_ROOT="$V" AL_LEGAL_HOLD=1 bash "$AL/core/cmd/clean.sh" >/dev/null 2>&1
assert "AL_LEGAL_HOLD memblokir penghapusan" test -d "$V/.agent/logs/old"
AL_REPO_ROOT="$V" bash "$AL/core/cmd/clean.sh" >/dev/null 2>&1
refute "clean menghapus log kedaluwarsa" test -d "$V/.agent/logs/old"
assert "clean tidak menyentuh artifact" test -f "$V/.agent/artifacts/a.json"

echo "# doctor"
assert "doctor exit 0" bash "$AL/core/cmd/doctor.sh"
out=$(GITHUB_TOKEN="$FAKE_GH" bash "$AL/core/cmd/doctor.sh" 2>&1)
refute_contains "doctor tidak mencetak nilai secret" "$out" "$FAKE_GH"
assert_contains "doctor melaporkan panjang saja"     "$out" "char, diredaksi"
assert_contains "doctor memeriksa .env ter-track"    "$out" ".env tracked"
refute_contains "tidak ada error git mentah"         "$out" "fatal:"

echo "# repo hygiene"
refute ".env tidak ada di disk" test -f "$AL/.env"
refute ".env tidak ada di index" git -C "$AL" ls-files --error-unmatch .env
assert ".gitignore memblokir .env" bash -c 'grep -qx "\.env" "$1/.gitignore"' _ "$AL"
refute ".env.example bebas credential" \
  grep -qE '(ghp_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,})' "$AL/.env.example"
assert "semua shell parse" bash -c '
  cd "$1" || exit 1
  for s in bin/al install.sh core/lib/*.sh core/cmd/*.sh core/templates/adapters/*.sh tests/*.sh; do
    bash -n "$s" || exit 1
  done' _ "$AL"
# Regresi: runner pernah memanggil test dengan path relatif, `. lib.sh` gagal,
# TEST_TMP kosong, dan `git init` fixture mengotori tests/ dengan repo nyata.
refute "tidak ada .git nyasar di dalam repo" \
  bash -c 'find "$1" -name .git -mindepth 2 -maxdepth 3 | grep -q .' _ "$AL"

test_summary
