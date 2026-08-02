#!/usr/bin/env bash
# al integrate — kelola skill upstream pinned, non-vendored.
. "${BASH_SOURCE[0]%/*}/lib.sh"

export AL_CONFIG_HOME="$(new_dir cfg)"

int() { AL_HOME="$AL" "$AL/bin/al" integrate "$@"; }

echo "# integrate help"
assert_contains "integrate help mengandung subcommand" "$(int help)" "al integrate add"
assert_rc "integrate command tak dikenal -> 64" 64 int bogus

echo "# integrate local validation"
assert_contains "integrate list tanpa network" "$(int list)" "belum ada integrasi"
assert_rc "integrate add nama invalid -> 64" 64 int add "https://github.com/foo/bar@deadbeef" "bad name"
assert_rc "integrate add non-github -> 64" 64 int add "https://gitlab.com/foo/bar@deadbeef" myname

# Resolusi GitHub dan tree sync membutuhkan API eksternal; tidak menjadi gate suite.
# Jalankan eksplisit saat ingin menguji koneksi upstream:
#   ./bin/al integrate add <github-url>@<sha> <name>
#   ./bin/al integrate sync <name>
skip "live GitHub integration" "network/ref resolution is external; run explicit smoke command"
skip "live GitHub doctor" "network/ref resolution is external; run explicit smoke command"
skip "live GitHub sync" "network/ref resolution is external; run explicit smoke command"

echo "# integrate add nama invalid"
assert_rc "integrate add nama invalid -> 64" 64 int add "https://github.com/foo/bar" "bad name"

echo "# integrate add non-github URL"
assert_rc "integrate add non-github -> 64" 64 int add "https://gitlab.com/foo/bar" myname

test_summary
