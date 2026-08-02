# AEP v2.1 — Implementation Status

Updated: 2026-08-02.

This status lists only behavior backed by commands/tests. Upstream skill bodies
are not copied into this repository.

## Implemented

| Area | Command | Evidence |
|---|---|---|
| Evidence tri-state | `al run <profile>` | `tests/evidence_test.sh` |
| Scope | `al scope check` | `tests/scope_test.sh` |
| Discovery | `al discovery start\|verify` | `tests/discovery_test.sh` |
| Complexity | `al complexity check` | `tests/complexity_test.sh` |
| Goal/Plan/Tasklist schema | `al goals validate` | `tests/goals_test.sh` |
| Contract lock | `al goals start` | `tests/goals_test.sh` |
| Hash/scope/approval verification | `al goals verify` | `tests/goals_test.sh` |
| AEP templates | `al init --aep` | `tests/aep_templates_test.sh` |
| Project initializer | `project-init.sh [--aep]` | `tests/project_init_test.sh` |
| CI contract | `.github/workflows/evidence.yml` | `tests/ci_contract_test.sh` |
| Upstream manifest | `al integrate list\|doctor\|add\|sync` | `tests/integrate_test.sh` |

## Goal hierarchy

```text
Goal readiness → one active Plan → Tasklist DAG → task DoD/evidence
```

- Goal contract: `.agent/goal.json` plus human `GOALS.md`.
- Plan contract: `.agent/plan.json`; one active Plan is the default.
- Tasklist contract: `.agent/tasklist.json`; serial default, DAG parallel only
  after dependency/path/output validation.
- Contract hash mutation after `al goals start` returns `UNKNOWN`.
- Low risk can proceed after PASS.
- Medium requires human review.
- High requires explicit approval tied to current head SHA.

## Optional / degraded

- `lizard` is optional. Required unavailable tool returns `UNKNOWN`; optional
  unavailable tool creates explicit no-op evidence.
- Agent-Reach and Context7 are optional freshness sources. They supplement stale
  model knowledge; they do not replace local evidence gates.
- Upstream planning/review reasoning is referenced, not vendored. See README and
  `docs/research/2026-08-02-skill-collections-and-code-intelligence.md`.

## Manual / still open

- GitHub branch protection and required checks: human setup in
  `docs/GITHUB-SETUP.md`.
- Final risk-path policy for each adopting repository: owner decision.
- Semantic judgment of Goal readiness and Plan approach: human review where policy
  requires it; schema validator only checks observable structure.
- End-to-end loading proof for every external harness: not claimed until exercised.
- Live upstream network integration: not used as deterministic permanent test.

## Verification

```bash
./bin/al selftest
make check
bash core/cmd/scan.sh .
```

CI must call `bin/al` directly for tri-state evidence. `make` is only a local
suite wrapper and must not be the branch-protection signal.

## Reuse attribution

- [obra/superpowers](https://github.com/obra/superpowers)
- [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail)
- [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)
- [Panniantong/agent-reach](https://github.com/Panniantong/agent-reach)
- [upstash/context7](https://github.com/upstash/context7)

Their licenses, versions, install contracts, and current pins must be recorded in
`al integrate` manifests before automated installation. No source body is copied.

MIT.
---

Content is project status, not a claim that every optional integration is installed.
