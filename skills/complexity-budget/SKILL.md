---
name: complexity-budget
description: Use when code may be more complicated than the problem requires — measuring cyclomatic complexity against a budget, recording a justified exception, or deciding whether a function should be split. Also use when a reviewer claims code is "simple" or "already optimal" without a number. Do not use for style or formatting concerns, and do not use it as a substitute for judgment about over-engineering.
version: 0.1.0
license: MIT
metadata:
  agentic-loop:
    tags: [complexity, simplicity, yagni, measurement, budget]
    requires_commands: [al]
    optional_commands: [lizard]
    upstream_skills: [ponytail, ponytail-review, ponytail-audit]
---

# Complexity Budget

## Overview

Two different jobs, deliberately kept apart:

| Job | Who does it | Output |
|---|---|---|
| Judging *should this exist at all* | `ponytail` skills (upstream prose) | reasoned recommendation |
| Measuring *how complex is it* | `al complexity` (this) | a number and an exit code |

Models are optimised for functional correctness, not simplicity — nested
conditionals, unnecessary loops, and speculative abstraction are the predictable
result. Prose alone cannot hold that back, because the same model that wrote the
code judges whether it is simple. A number cannot be argued with.

The reverse is also true: a number cannot tell you an abstraction is speculative
or a dependency unnecessary. That is what the upstream `ponytail` skills are for,
and this skill does not duplicate them.

## When to Use

- After writing a function that grew branches while you worked
- When a reviewer says "this is simple" or "already optimal" with no measurement
- Before merging, as the mechanical half of a simplicity review
- When recording a justified exception for code that must stay complex

Don't use for: formatting, naming, or style. Don't use it to decide *whether* a
feature should exist — reach for `ponytail` for that.

## Commands

```bash
al complexity check    # 0 within budget / declared no-op, 1 over, 2 unmeasurable
al complexity show     # effective budget + engine state
```

Engine is `lizard` — the only tool covering PHP, JS/TS, Go, Python, Rust, Java,
C#, Ruby, Swift, Kotlin and more in one install with per-function thresholds and
a nonzero exit code. Install with `pipx install lizard`.

## The three modes, and why absence is not a pass

Set `mode` in `.agent/complexity.yaml` or `AL_COMPLEXITY_MODE`:

| Mode | Engine present | Engine absent |
|---|---|---|
| `off` | declared no-op | declared no-op |
| `optional` | measures and reports | `no_op COMPLEXITY_TOOL_UNAVAILABLE`, exit 0 |
| `required` | measures and reports | **exit 2** — unmeasurable, not passing |

The distinction is the whole point. `optional` announces that nothing was
measured; `required` refuses to guess. No path turns "not measured" into
"passed". Bash is not measured by lizard at all — that makes it *unmeasured*, not
*simple*.

## Candidate vs approved

`.agent/complexity.yaml` ships as `status: candidate`, which reports findings
without blocking. Promote to `approved` only after validating the thresholds
against real code in the repo.

The reason is concrete: fluent styles — Laravel query builders, chained promises,
pattern-matched dispatch — raise cyclomatic complexity without making code harder
to read. The commonly quoted 10/15 figures are a starting hypothesis, not a
property of your codebase.

```yaml
status: candidate        # candidate = report only; approved = block
mode: optional
max_ccn: 10
max_function_lines: 60
max_params: 5
exceptions: []
```

## Working the gate

1. Run `al complexity check` on your branch. Only changed files in supported
   languages are measured; old debt elsewhere is not this PR's problem.
   Done when you have a number per flagged function, or a declared no-op.
2. For each finding, try simplification first. Ask the upstream `ponytail-review`
   skill whether the complexity is essential or accidental.
   Done when the function is under budget, or you can state why it cannot be.
3. If it genuinely must stay complex, add an exception with a reason, an owner,
   and a review date. An exception without those three becomes permanent.
   Done when `al complexity check` reports `excused <function>`.
4. Once thresholds have survived real use, set `status: approved` so findings
   block instead of merely reporting.
   Done when a deliberate breach makes `al complexity check` exit 1.

```yaml
exceptions:
  - function: handleLegacyImport
    reason: "old format parser, split after v3 migration"
    owner: hasban
    review_date: 2026-11-01
```

## Common Pitfalls

1. **Treating a missing engine as a pass.** In `required` mode absence is exit 2.
   If you see exit 0 with `COMPLEXITY_TOOL_UNAVAILABLE`, nothing was measured.
2. **Calling unmeasured languages simple.** Lizard does not parse Bash. That is a
   gap in coverage, not evidence of simplicity.
3. **Promoting to `approved` on day one.** Untested thresholds either block
   legitimate fluent code or are quietly disabled. Validate first.
4. **Exceptions without owner or review date.** They stop being exceptions and
   become the new baseline.
5. **Raising `max_ccn` to make a finding disappear.** That is editing the ruler.
   Either simplify, or record a scoped exception for that one function.
6. **Using the number as a whole simplicity review.** A CCN of 3 can still be a
   needless abstraction over a dependency that already does the job.
7. **Measuring the entire repo in a PR gate.** It punishes inherited debt and
   trains people to bypass the gate.

## Verification Checklist

- [ ] `al complexity check` was actually run; outcome quoted from real output
- [ ] Exit code interpreted correctly: 0 within budget *or* declared no-op, 1
      over budget, 2 unmeasurable
- [ ] Any `no_op` result states its reason and is not reported as a pass
- [ ] Every exception has reason, owner, and review date
- [ ] Thresholds were validated against real code before `status: approved`
- [ ] Simplification was attempted before an exception was recorded
- [ ] Judgment-level over-engineering was reviewed via upstream `ponytail`, not
      inferred from the number alone
