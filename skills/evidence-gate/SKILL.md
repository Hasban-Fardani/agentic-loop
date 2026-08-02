---
name: evidence-gate
description: Use when you must prove a code change actually works before merge — running build/test/lint/security as a repeatable gate that returns PASS, FAIL, or UNKNOWN with a signed artifact. Also use when asked to interpret an evidence artifact, when a CI check is red and you need to tell a real code failure apart from broken infrastructure, or when a repo needs its evidence contract set up. Do not use for exploratory local test runs where no audit trail is needed.
version: 0.1.0
license: MIT
metadata:
  agentic-loop:
    tags: [evidence, ci, verification, gate, audit]
    requires_commands: [git, jq, bash]
---

# Evidence Gate

## Overview

An evidence gate answers one narrow question: **did the required commands succeed on this exact commit, in a defined environment, with logs you can verify?**

It does not prove the product is correct. It proves specific commands passed. Business acceptance still needs a human. Keeping that boundary explicit is the whole point — a green gate that implies more than it measured is worse than no gate.

Three outcomes, and the third is the one that matters:

| Outcome | Meaning | Exit | Merge |
|---|---|---|---|
| `PASS` | every required command exited 0, artifact complete | 0 | allowed by policy |
| `FAIL` | a command failed — the code is wrong | 1 | blocked |
| `UNKNOWN` | the result could not be proven | 2 | blocked |

`UNKNOWN` is not `FAIL` and never `PASS`. Runner crash, timeout, missing scanner, absent artifact, commit mismatch, uncommitted work — all `UNKNOWN`. They consume the infrastructure recovery budget, not the code-retry budget. Conflating them means a broken runner looks like a broken feature, and you burn retries fixing code that was never wrong.

## When to Use

- Before opening or merging a PR that must be auditable
- CI check is red and you must classify it: code defect vs infrastructure
- Reading an `.agent/artifacts/*.json` artifact to explain a decision
- Setting up the evidence contract in a repo that has none
- A gate reported `PASS` and you need to state precisely what that did and did not cover

Don't use for: a quick local `npm test` while iterating. The gate costs a commit and an artifact; iteration doesn't need either.

## Commands

```bash
al run [smoke|standard|full]   # 0=PASS 1=FAIL 2=UNKNOWN
al decision                    # decision + flags of latest artifact
al scan [path]                 # secret/PII scan alone
al init                        # scaffold .agent/ + adapters
al doctor                      # effective config, tools, harnesses
```

Profiles come from `.agent/evidence.yaml`, not from this skill:

| Profile | Steps | Use |
|---|---|---|
| `smoke` | setup, test | fast local feedback |
| `standard` | setup, build, test, lint, security | PR gate |
| `full` | + healthcheck | high-risk, migration, release |

## Interpreting the result

Never report a gate outcome from the exit code alone — read `quality_flags`:

```bash
al decision
jq -r '.verifier_decision, (.quality_flags|join(","))' \
  "$(ls -t .agent/artifacts/*.json | head -1)"
```

| Flag | Cause | Correct response |
|---|---|---|
| `STEP_FAIL_<step>` | command exited 1 | fix the code; counts against code retry |
| `MISSING_ADAPTER_<step>` | adapter script absent | repo defect — fix the repo, not the runner |
| `STEP_TIMEOUT_<step>` | exceeded manifest timeout | one infra recovery, then escalate |
| `STEP_UNAVAILABLE_<step>` | tool/scanner missing | install the tool or escalate; never call it PASS |
| `ACCEPTANCE_MAP_MISSING` | no acceptance mapping | write `.agent/acceptance-evidence.yaml` |
| `HUMAN_ONLY_APPROVAL_PENDING` | human-only AC has no `approval_ref` | get the review; do not bypass |
| `DIRTY_WORKTREE` | uncommitted changes before the run | commit, then rerun |

Retry budgets are separate and both are small: **3 code retries, 1 infra recovery.** Exhausted infra recovery means `escalated` — a human decides. Never retry the same command with no new information; that is a loop, not a strategy.

## Making a repo pass honestly

1. `al init` — writes `.agent/evidence.yaml`, `.agent/acceptance-evidence.yaml`, and adapters under `scripts/evidence/`. Idempotent; existing files are kept unless `AL_FORCE=1`.
   Done when `al doctor` lists all three files as present.
2. Set `environment_mode` in the manifest truthfully — `exact`, `approximate`, `hybrid`, or `ci_only`. If your laptop is not the CI runner, it is not `exact`. Lying here means a local `PASS` that CI contradicts.
   Done when the value matches reality, not aspiration.
3. Map every acceptance criterion to evidence in `.agent/acceptance-evidence.yaml`. Criteria only a human can judge get `type: human_only` **and** a real `approval_ref`. `PENDING` keeps the gate at `UNKNOWN` — that is the mechanism working, not a bug to route around.
   Done when each AC id appears with either a test path or a filled `approval_ref`.
4. `al run standard`. Read the flags, not just the exit code.
   Done when the decision is `PASS`, or you can name the exact flag blocking it.
5. Commit before the final run. A dirty worktree unbinds the result from a commit and yields `UNKNOWN`.
   Done when `git status --porcelain` is empty.

Adapters are ordinary shell scripts and read commands from stack detection or `AL_CMD_*` overrides, so a Node/Go/PHP/Python/Rust repo needs no edits. Set `AL_CMD_TEST` in `.env` when the guess is wrong.

## Declaring a no-op vs skipping

A step with nothing to do must say so and exit 0:

```bash
echo "build: no_op (no build step for this stack)"
exit 0
```

Silent skipping is how a gate lies. If a step is genuinely irrelevant, record the reason in the manifest so the artifact shows *why* it was absent. Skipping a flaky test with no quarantine policy is `FAIL`, not `PASS`.

## Common Pitfalls

1. **Treating `UNKNOWN` as `FAIL`.** Fixing code because a runner died wastes the code-retry budget and hides an infrastructure problem that will recur.
2. **Reading the exit code only.** `2` tells you nothing was proven; `quality_flags` tells you what to do. Always print them.
3. **Bypassing `HUMAN_ONLY_APPROVAL_PENDING`** by editing the acceptance map to remove the human-only entry. That deletes the audit trail. Get the approval.
4. **Claiming the gate proves the feature works.** It proves commands exited 0 on one commit. Say exactly that.
5. **Setting `environment_mode: exact` when local differs from CI.** CI then contradicts your local `PASS` and nobody trusts either.
6. **Running with a dirty worktree, then reporting the artifact.** The artifact's `head_sha` does not describe the code that ran.
7. **Adding a step to the manifest without an adapter.** Yields `MISSING_ADAPTER_*` → `UNKNOWN` for every future run.
8. **Using `make` in CI for the gate.** `make` collapses every failure to exit 2, destroying the FAIL-vs-UNKNOWN distinction. Automation calls `al run` directly.

## Verification Checklist

- [ ] `al doctor` exits 0 and shows manifest, acceptance map, and policy present
- [ ] `al run standard` was actually executed — outcome quoted from real output, not predicted
- [ ] Decision reported together with `quality_flags`
- [ ] `head_sha` in the artifact equals `git rev-parse HEAD`
- [ ] `artifact_hash` recomputes: `jq -S 'del(.artifact_hash)' ART | shasum -a 256`
- [ ] `UNKNOWN` was escalated or recovered once — not retried as a code failure
- [ ] Any `no_op` step states its reason in the log
- [ ] Claims about what the gate proved are limited to the commands that ran
