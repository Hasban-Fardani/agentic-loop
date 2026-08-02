---
name: risk-gate
description: Use when deciding whether a change can merge autonomously or needs human approval — classifying a PR as low/medium/high risk, checking whether an approval is still valid after a new push, or handling an emergency override. Also use when asked why a PR is blocked, or when tempted to self-approve or merge your own work. Do not use for judging code quality; this covers merge authority only.
version: 0.1.0
license: MIT
metadata:
  agentic-loop:
    tags: [risk, approval, merge, policy, governance]
    requires_commands: [git]
---

# Risk Gate

## Overview

An evidence gate says the commands passed. A risk gate says **who is allowed to merge that.** They are independent: `PASS` on a high-risk change still needs a human.

The purpose is to stop small changes from queueing behind a human while making sure dangerous ones never bypass one. A gate that blocks everything gets disabled; a gate that blocks nothing is decoration.

Absolute boundary — an agent never:

- merges its own PR
- pushes to a protected branch
- modifies branch protection
- approves its own changes
- deploys to production
- reads production secrets

These are not defaults to be argued with. If a task appears to require one, the task is wrong or the human must do it.

## When to Use

- Assigning a risk tier to a change
- A PR is blocked and you must explain precisely why
- New commits landed after an approval — is it still valid?
- Emergency/incident change that seems to justify skipping the gate
- Any impulse to merge, approve, or deploy your own work

Don't use for: reviewing code quality. This is about merge authority.

## Tiers

| Tier | Examples | Path to merge |
|---|---|---|
| Low | typo, docs, isolated test, small local refactor | autonomous after `PASS` |
| Medium | one bounded context, internal endpoint, several files | async human review |
| High | anything in the flags below | explicit human approval |

A change is **high risk** if it touches any of:

- authentication, authorization, permission, session, identity
- destructive migration or irreversible data change
- production config, deployment, rollback, or secrets
- public endpoint, external integration, webhook, egress
- payment, payroll, financial calculation, audit trail
- PII, data residency, regulatory or contractual constraint
- a new unpinned runtime dependency
- shared hotspots: schema, routing, auth, deploy, public contract
- unusually large diff relative to the repo's norm
- incomplete evidence or acceptance mapping
- provider, runner, toolchain, or policy change itself

Repo-specific paths live in `.agent/agent-policy.yaml` under `high_risk_paths`. Check the file — it beats memory.

An agent may **raise** a tier. It may never lower one. Lowering is a human decision, recorded.

## Emergency is not a tier

Incidents are a mode, not a lower bar. An emergency override still requires: incident ID, scope limited to specific commits, named approver, start time and expiry, rollback plan, follow-up evidence within 24h, and a post-incident review. "It's urgent" without those is just an unapproved merge.

## Approval validity

An approval binds to **one head SHA**, or one hour, whichever ends first. It is void when:

- new commits are pushed (the approved code no longer exists)
- the risk tier changes
- evidence is rerun with a different outcome
- a force-push rewrites the branch

After any of those, re-request. Carrying an approval across a push is how unreviewed code reaches main.

```bash
git rev-parse HEAD        # must equal the SHA on the approval record
```

## Deciding

1. Read `.agent/agent-policy.yaml` for `high_risk_paths` and `forbidden`.
2. List changed paths: `git diff --name-only origin/main...HEAD`.
   Done when every changed path is checked against the high-risk list.
3. Assign the tier. Any high-risk flag makes it high, no matter how small the diff.
   Done when the tier and the specific flag that set it are both stated.
4. Confirm evidence: `al decision`. `FAIL` or `UNKNOWN` blocks regardless of tier.
   Done when the decision and its flags are quoted from real output.
5. Record the decision:
   ```bash
   al event approval actor=<human> pr_number=<n> approval_ref=<id>
   al event merge actor=<human> pr_number=<n>
   ```
   Done when the event log holds the tier, the actor, and the head SHA.

State the tier **and its cause**: "high risk — touches `src/auth/session.ts`" is auditable. "Looks risky" is not.

## Common Pitfalls

1. **Lowering a tier because the diff is small.** A one-line auth change is high risk. Size is not the signal; blast radius is.
2. **Treating `PASS` as merge authority.** Evidence and risk are separate gates. High risk plus `PASS` still waits for a human.
3. **Reusing an approval after a push.** The approved SHA is gone. Void.
4. **Self-approving because nobody is around.** Delegate approver, or it waits. Absence is not authority.
5. **Calling an incident a tier** to skip the human. Emergency needs *more* paperwork, not less.
6. **Merging with `UNKNOWN`.** Nothing was proven. Resolve or escalate.
7. **Judging risk from the PR title.** Read the changed paths.
8. **Deciding from memory instead of `.agent/agent-policy.yaml`.** The repo's list is authoritative and changes.
9. **Batching unrelated low-risk PRs into one merge.** One bad change invalidates the batch and rollback gets ambiguous. Keep a rollback pointer per PR.

## Verification Checklist

- [ ] `.agent/agent-policy.yaml` was actually read this session
- [ ] Changed paths enumerated with `git diff --name-only`
- [ ] Tier stated together with the specific flag that caused it
- [ ] Evidence decision quoted from `al decision`, not assumed
- [ ] Approval SHA equals current `git rev-parse HEAD`
- [ ] No tier was lowered by an agent
- [ ] Merge/approval recorded via `al event`
- [ ] Nothing in the `forbidden` list was attempted
