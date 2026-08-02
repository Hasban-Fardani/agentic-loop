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

## Install

```bash
git clone git@github.com:Hasban-Fardani/agentic-loop.git ~/.agentic-loop
cd ~/.agentic-loop
./install.sh --dry-run     # see the plan first
./install.sh               # detect installed harnesses, install to each
```

Targets specific harnesses, or opts out of the PATH symlink:

```bash
./install.sh claude codex        # only these
./install.sh --mode copy        # frozen snapshot instead of symlink
AL_BIN_DIR=- ./install.sh       # skip linking `al` into PATH
./install.sh --uninstall        # remove
```

Default is symlink: one source of truth, updated by `git pull`. `--mode copy`
freezes a snapshot instead.

## Use

```bash
cd your-repo
al init                # scaffold .agent/ + evidence adapters
al doctor              # effective config, tools, harnesses, .env safety
al run standard        # the gate: 0=PASS 1=FAIL 2=UNKNOWN
al decision            # decision + flags of the latest artifact
al verify              # policy & permission boundary self-test
al scan                # secret/PII scan on its own
al scope check         # allowed/forbidden path contract
al discovery start --query "..."   # reuse evidence before writing code
al complexity check    # cyclomatic complexity against budget
al selftest            # this toolkit's own test suite
```

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

Stack detection covers Node, PHP, Go, Python, Rust, and Makefile repos. Override
any guess with `AL_CMD_TEST`, `AL_CMD_BUILD`, and friends rather than editing an
adapter.

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
