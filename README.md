# agentic-loop

Evidence gate, risk gate, and secret safety for coding agents. Installs as skills
into Claude Code, Codex, Cursor, opencode, Hermes Agent, or anything that reads
`AGENTS.md` — one source, no per-agent edits.

Portable Bash. No runtime beyond `git`, `jq`, and a POSIX shell.

## Why

A coding agent that says "tests pass" is making a claim you cannot check later.
This toolkit turns that claim into an artifact: which commands ran, on which
commit, with which exit codes and log hashes. It also draws two lines the agent
cannot cross — it never merges its own work, and secrets never reach a log.

Three outcomes, and the third is the point:

| Outcome | Meaning | Exit |
|---|---|---|
| `PASS` | required commands exited 0, artifact complete | 0 |
| `FAIL` | a command failed — the code is wrong | 1 |
| `UNKNOWN` | the result could not be proven | 2 |

`UNKNOWN` is never `PASS`. Runner crash, timeout, missing scanner, dirty
worktree — all `UNKNOWN`, all blocking, and they spend the infrastructure
recovery budget rather than the code-retry budget. Conflating the two means a
broken runner looks like a broken feature.

## Install toolkit vs initialize project

`install.sh` installs portable skills and the `al` CLI into agent harnesses. It
must run from the agentic-loop checkout and does not bootstrap project evidence
contracts.

```bash
git clone git@github.com:Hasban-Fardani/agentic-loop.git ~/.agentic-loop
cd ~/.agentic-loop
./install.sh --dry-run     # inspect harness installation
./install.sh               # install into detected Hermes/Claude/Codex/etc.
```

`project-init.sh` initializes one target project. It writes `.agent/`, evidence
adapters, `GOALS.md`, and Goal/Plan/Tasklist contracts. It does not install global
skills. `al init` is the underlying command; wrapper exists to make intent explicit.
The wrapper resolves `AL_HOME` from its own checkout, so it works when invoked
from a different project directory.

```bash
cd /path/to/your-project
~/.agentic-loop/project-init.sh              # core project contract
~/.agentic-loop/project-init.sh --aep         # contract + AEP docs
~/.agentic-loop/project-init.sh --dry-run    # inspect, write nothing
```

Use `install.sh` once per machine/harness. Use `project-init.sh` once per project.
Both are idempotent; existing files stay unless `--force`/`AL_FORCE=1` is explicit.

## Harness install

```bash
./install.sh claude codex        # only these
./install.sh --mode copy         # frozen snapshot instead of symlink
AL_BIN_DIR=- ./install.sh        # skip linking `al` into PATH
./install.sh --uninstall         # remove installed skills
```

The `agents` target is the exception: it writes the open-standard `AGENTS.md` to
`AL_REPO_ROOT` only when absent. It never overwrites an existing project file.
Use `project-init.sh` for the complete project contract.

Every install/init prints a non-production warning. This toolkit is for
**development, testing, and staging only**. Never connect it to production or
provide production secrets.

## Hermes GitHub automation

GitHub event ingress uses Hermes Agent's existing webhook platform, not a second
server inside this repository:

```text
GitHub event → Hermes webhook subscription → Hermes session/tools
  → draft review/patch → human confirmation → decision artifact + event index
  → Goal/Plan/Tasklist validation → independent CI
```

Pilot contract:

```bash
al github validate
al github decision .agent/decisions/DEC-<id>.json
```

Use `docs/HERMES-GITHUB-RUNBOOK.md`. Official Hermes references:
[GitHub PR webhook guide](https://hermes-agent.nousresearch.com/docs/guides/webhook-github-pr-review)
and [automation blueprints](https://hermes-agent.nousresearch.com/docs/guides/automation-blueprints#github-event-automations).
RBAC allowlist, explicit confirmation, separate worktree, no production secrets,
and current-HEAD SHA binding are mandatory. GitHub App permission stays minimal;
no merge, approve, force-push, branch-protection, or deploy permission.

Default dynamic subscription shape:

```bash
hermes webhook subscribe agentic-loop-github \
  --events pull_request,issue_comment,pull_request_review,pull_request_review_comment,workflow_run \
  --skills github-code-review --deliver github_comment
```

Use installed Hermes `--help` for exact flags. Webhook secrets live in Hermes
secret/config storage, never repository `.env`.

Default is symlink: one source of truth, updated by `git pull`. `--mode copy`
freezes a snapshot instead.

## Use

```bash
cd your-repo
al init                # scaffold .agent/ + evidence adapters
al doctor              # effective config, tools, harnesses, .env safety
al run standard        # the gate: 0=PASS 1=FAIL 2=UNKNOWN
```

Full workflow commands follow below.


## Goal → Plan → Tasklist

Workflow contracts are separated by responsibility:

```text
GOALS.md + .agent/goal.json
  → one active .agent/plan.json
  → .agent/tasklist.json (DAG; serial by default, parallel only when paths,
    outputs, dependencies, and shared state are mechanically disjoint)
```

`GOALS.md` states outcome, non-goals, boundaries, allowed/forbidden paths, risk,
and freshness requirements. JSON contracts are machine-validated. `al goals start`
records SHA-256 hashes before coding; mutation after start returns `UNKNOWN`.
Low risk can proceed after evidence PASS. Medium requires human review. High
requires human approval tied to the approved commit SHA. Pending approval returns
`UNKNOWN`; chat is not an approval channel.

```bash
al goals validate
al goals start
al goals verify
```

Each task needs executable Definition-of-Done checks (`command` + expected exit,
path/artifact assertions, and scope). A task with failed or unknown dependencies
is blocked. Ambiguous parallelism returns `UNKNOWN`, never an agent guess.

## Freshness and external reuse

This repository does not vendor third-party skill bodies or pretend upstream tools
are local implementations. Existing local skills provide mechanical enforcement:
`evidence-gate`, `risk-gate`, `secret-safety`, `reuse-first-discovery`, and
`complexity-budget`. Upstream reasoning skills remain attributed external references:
[obra/superpowers](https://github.com/obra/superpowers) (planning/TDD/review/worktrees),
[DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (YAGNI and
over-engineering review), and [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)
(ADR/source-driven/adversarial review). Optional code intelligence is documented
separately; `al discovery` remains the local forcing function.

[Agent-Reach](https://github.com/Panniantong/agent-reach) is an MIT, Python CLI/skill
for routed web, GitHub, video, RSS, and social-source research. [Context7](https://github.com/upstash/context7)
is an MIT MCP/CLI/skill set for current, version-specific library documentation.
Both are optional freshness sources, not evidence-gate replacements: unavailable
required freshness is `UNKNOWN`, optional freshness is an explicit no-op. Integrations
are recorded with `al integrate` as pinned, non-vendored manifests under
`$AL_CONFIG_HOME/integrations/`.

See `docs/research/2026-08-02-skill-collections-and-code-intelligence.md` and
`docs/AEP-v2.1-STATUS.md` for verified boundaries and open claims.

Profiles come from `.agent/evidence.yaml`:

| Profile | Steps |
|---|---|
| `smoke` | setup, test |
| `standard` | setup, build, test, lint, security |
| `full` | + healthcheck |

CI and automation call `al run` directly. Do **not** wrap it in `make`: `make`
collapses every failure to exit 2 and erases the FAIL-vs-UNKNOWN distinction the
gate exists to preserve.

## Configuration

Every tunable is an environment variable. Nothing is hardcoded, and no file needs
editing per agent or per repo.

```text
built-in default  <  ~/.config/agentic-loop/config.env  <  ./.env  <  environment
```

Environment wins deliberately — CI secret stores export real environment
variables, so they must beat any on-disk file. See `.env.example` for the full
list; copy it to `.env` and fill in what you need.

`.env` is parsed as data, never sourced. `EVIL=$(rm -rf /)` in a `.env` is a
literal string, not a command.

Stack detection covers Node/Deno, PHP, Python, Ruby, Go, Rust, Java (Maven),
Gradle/Android, Scala, .NET, Elixir, Dart/Flutter, Swift, CMake, Zig, and
Makefile repos, plus framework detection for Laravel, Symfony, Rails, Django,
Phoenix, Next.js, Nuxt, SvelteKit, Astro, Angular, NestJS, Expo, Spring Boot and
others. Override any guess with `AL_CMD_TEST`, `AL_CMD_BUILD`, and friends rather
than editing an adapter.

Two properties matter more than the length of that list:

- **A framework marker beats a generic manifest.** Laravel 11 ships a
  `package.json` for Vite; Rails ships one for jsbundling; Django ships one for
  Tailwind. Detecting `artisan`, `bin/rails`, or `manage.py` decides the primary
  stack, so a Laravel repo runs Pest rather than `npm test`.
- **A command is only emitted if the tool is actually there.** `npm run lint` in
  a repo with no `lint` script exits 1, which looks like failing code rather than
  an absent linter. Laravel 11 ships Pest, not PHPUnit, so guessing
  `vendor/bin/phpunit` exits 127 and the gate reports UNKNOWN — spending the
  infrastructure-recovery budget on our own bad guess. When nothing is found the
  step declares a `no_op` and names the variable to set.

Frontend assets in a backend repo are handled as a secondary stack: setup and
build run for both, tests do not. Mixing PHP and JS test output obscures which
one failed.

## Secrets

`.env` is git-ignored; only `.env.example` is committed. `al doctor` reports
secret **names and lengths, never values**.

Redaction runs in two independent layers, because either alone leaks: by value
for names listed in `AL_SECRET_VARS`, and by pattern for credential shapes from
tools you do not control. It applies at the write boundary, so unredacted values
never reach disk.

Before making any repo public:

```bash
git check-ignore -q .env                          # must succeed
git ls-files --error-unmatch .env 2>/dev/null     # must fail
al scan                                           # must exit 0
```

Being listed in `.gitignore` does nothing if the file was committed before the
rule existed. Check history, not just the working tree.

## Skills

| Skill | Loads when |
|---|---|
| `evidence-gate` | proving a change works; reading an artifact; classifying a red CI check |
| `risk-gate` | deciding autonomous merge vs human approval; approval validity after a push |
| `secret-safety` | handling tokens; wiring env config; scanning before publishing |
| `reuse-first-discovery` | before writing new code; proving you looked for existing code first |
| `complexity-budget` | measuring cyclomatic complexity against a budget; recording an exception |

Each is a single `SKILL.md` with `name` + `description` frontmatter — the format
Claude Code, Codex, opencode, and Hermes all read. Cursor gets a generated
`.cursor/rules/agentic-loop.mdc` pointer instead, because its rule format
differs; the skill bodies stay the single source.

## What is reused rather than rebuilt

Several problems are already solved well elsewhere, so this toolkit does not
duplicate them. It provides the mechanical half and defers the judgment half:

| Concern | Upstream to install | What stays here |
|---|---|---|
| Planning, TDD, worktree guidance, verification-before-completion | [obra/superpowers](https://github.com/obra/superpowers) | evidence artifacts, worktree lifecycle, tri-state gate |
| YAGNI, over-engineering review, deliberate-shortcut ledger | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | `al complexity` — measurement only |
| ADRs, source-backed decisions, adversarial review | [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | artifact validation (planned) |
| Symbol navigation, impact analysis | [colbymchenry/codegraph](https://github.com/colbymchenry/codegraph) (optional) | `al discovery` — the forcing function |

The split is deliberate. Prose can judge whether an abstraction is speculative; it
cannot stop the model that wrote the code from calling it simple. A number can.
Conversely a number cannot tell you a dependency was unnecessary.

See `docs/research/2026-08-02-skill-collections-and-code-intelligence.md` for what
was verified in each repo, and `docs/AEP-v2.1-STATUS.md` for which gates are built
versus still open.

## What this does not do

- It does not prove your product is correct. It proves specific commands exited 0
  on a specific commit. Business acceptance still needs a human.
- It does not replace CI. It gives CI a contract to run.
- It does not manage secrets. It keeps them out of logs and out of git.

## Layout

```text
bin/al                    CLI entry point
core/lib/                 config, redaction, portable helpers, stack detection
core/cmd/                 run, verify, scan, event, init, doctor, clean, decision
core/templates/           manifest, policy, acceptance map, adapters, AGENTS.md
skills/<name>/SKILL.md    the portable skills
install.sh                multi-harness installer
docs/HARNESS-MATRIX.md    per-harness paths and where they were verified
```

## Status

Early. Verified by hand on macOS 15.6 with Bash 3.2 across five stacks: the
installer, config cascade, redaction, tri-state ladder, scanner, event log, and
retention behaviour have all been exercised against real repos. There is no
automated test suite yet — see `docs/HARNESS-MATRIX.md` for what was checked
where, and what remains unverified.

MIT.
