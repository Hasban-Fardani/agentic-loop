---
name: reuse-first-discovery
description: Use before writing any new function, endpoint, or module — search the codebase for existing code to reuse or extend, and record what you searched as an auditable artifact. Also use when a reviewer asks whether similar code already exists, or when you are about to claim nothing reusable was found. Do not use for trivial one-line edits or for finding a specific known symbol.
version: 0.1.0
license: MIT
metadata:
  agentic-loop:
    tags: [reuse, discovery, duplication, search, evidence]
    requires_commands: [git, al]
    optional_commands: [codegraph]
---

# Reuse-First Discovery

## Overview

Coding agents add code far more readily than they reuse it. The measured gap is
large: AI refactoring operations target code duplication in about 1.1% of cases
and modularity in 4.6%, versus 13.7% and 12.9% for human refactoring. The cause
is structural, not laziness — code that is not in the context window effectively
does not exist, so the agent writes a second implementation of something already
present.

The fix is not better search. It is a **forcing function**. Symbol-graph tools
(Serena, codegraph, understand-anything) all answer "where is symbol X" or "who
calls X"; none has a primitive for "does functionally similar code already
exist". Better retrieval does not fire if nothing makes the agent look.

So this skill produces an artifact. `al discovery verify` refuses a PR whose
record is empty, and the record must state what was searched — not that the
search was thorough.

## When to Use

- Before writing a new function, endpoint, component, service, or module
- Before adding a dependency for a capability the repo may already have
- When a reviewer asks whether similar code exists
- When you are about to say "there's nothing to reuse" — that is a claim, and it
  needs the evidence below

Don't use for: a one-line fix, a rename, or locating a symbol whose exact name
you already know (`git grep` directly for that).

## Commands

```bash
al discovery start --query "report download" [--task TASK-123]
al discovery verify [--task TASK-123]     # 0 complete  1 malformed  2 no record
al discovery show   [--task TASK-123]
```

`start` runs layered searches and writes `.agent/discovery/<TASK>.md` with the
raw hits. It leaves two sections deliberately blank for you to fill; a template
that verifies while still empty teaches the agent that the gate is theatre.

## What the search actually covers

`start` runs three passes, all with tools already present:

| Pass | Why it exists |
|---|---|
| `git grep -rn -i` on the whole query | exact phrase, case-insensitive |
| token split, ≥4 chars, each grepped | finds `downloadReport` from `report download` |
| `git log -S <query>` | surfaces implementations deleted or moved earlier |

If `codegraph` is installed **and** `.codegraph/` exists, `query --json` results
are appended as higher-quality candidates and the record's confidence is raised
to `symbol-graph-assisted`. Without it the record says `command-fallback`.

That label matters. `command-fallback` does **not** prove no similar code exists.
It proves the listed searches found nothing matching. Never upgrade that claim in
prose.

## Filling the record honestly

1. Run `al discovery start --query "<the capability, in words>"`. Use the words a
   human would use, not the symbol name you intend to create — the point is to
   find code named differently.
   Done when `.agent/discovery/<TASK>.md` exists with raw hits.
2. Open the two or three most plausible hits and read them. Write each into
   **Closest existing patterns** as `path:line — why it fits / why it does not`.
   Done when at least two candidates are recorded with a real reason each.
3. If genuinely nothing exists, write one item beginning `tidak ada kandidat:`
   or `no candidate:` and state which terms you searched. That is the only
   accepted shortcut, and it is auditable.
   Done when the justification names the searches, not just the conclusion.
4. Check installed dependencies. A repo often already has the capability in a
   package nobody used. Name the manifest and what you found.
   Done when **Installed dependency check** names a manifest and a finding.
5. Set **Conclusion** to exactly one of `reuse`, `extend`, `no-suitable-reuse`.
   Done when `al discovery verify` exits 0.

## Common Pitfalls

1. **Searching for the name you plan to write.** You will find nothing, because
   it does not exist yet. Search the capability in plain words.
2. **Filling the record after writing the code.** Then it documents a decision
   already made instead of informing one. Run `start` first.
3. **Listing hits without opening them.** `path:line` with no reason is not a
   candidate assessment; the verifier accepts the line but a reviewer will not.
4. **Writing "no similar code exists".** You cannot know that. Write which terms
   you searched and that they returned nothing suitable.
5. **Treating `command-fallback` as weaker evidence than it is** — or stronger.
   It is exactly: these searches, this result.
6. **Skipping the dependency check.** Reinventing something a dependency already
   does is the same failure as reinventing local code.
7. **Extending the query until it finds nothing.** Narrow queries produce clean
   records and duplicate code.

## Verification Checklist

- [ ] `al discovery start` ran **before** implementation code was written
- [ ] Query used capability words, not the intended new symbol name
- [ ] At least two candidates recorded with `path:line` and a real reason, or one
      explicit `tidak ada kandidat:` / `no candidate:` item naming the searches
- [ ] Installed dependencies checked and the finding recorded
- [ ] `Conclusion` is one of `reuse` / `extend` / `no-suitable-reuse`
- [ ] `al discovery verify` exits 0
- [ ] No prose anywhere claims certainty the record does not support
