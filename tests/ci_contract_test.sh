#!/usr/bin/env bash
. "${BASH_SOURCE[0]%/*}/lib.sh"

WF="$AL/.github/workflows/evidence.yml"
assert "CI memanggil bin/al run" grep -q 'bin/al.*run' "$WF"
refute "CI tidak memakai make gate" grep -qE '^ *make +(gate|test)' "$WF"
assert "CI menjalankan selftest" grep -q 'bin/al.*selftest' "$WF"
assert "CI memanggil scope bila ada" grep -q 'bin/al.*scope check' "$WF"
assert "CI memanggil goals bila ada" grep -q 'bin/al.*goals validate' "$WF"
assert "CI checkout head SHA" grep -q 'pull_request.head.sha' "$WF"

test_summary
