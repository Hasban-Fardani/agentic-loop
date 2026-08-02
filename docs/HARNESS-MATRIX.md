# Harness matrix

Where each harness reads skills and project rules, and how confident we are.
Paths are configurable — the env var in the last column overrides the default,
so an unusual layout never requires editing `install.sh`.

Verified against upstream docs and reference repos on 2026-08-02.

## Skill and rule locations

| Harness | Skills path | Format | Verified from | Override |
|---|---|---|---|---|
| Claude Code | `~/.claude/skills/<name>/SKILL.md` (personal), `.claude/skills/<name>/SKILL.md` (project), `<plugin>/skills/<name>/SKILL.md` (plugin) | `SKILL.md` + YAML frontmatter | `docs.claude.com/en/docs/claude-code/skills.md` — explicit three-row scope table | `AL_CLAUDE_HOME` |
| Hermes Agent | `~/.hermes/skills/<name>/SKILL.md` | `SKILL.md` + frontmatter, optional `metadata.hermes` block | Hermes docs + local install at `~/.hermes/skills` | `AL_HERMES_HOME` |
| Codex CLI | `~/.codex/skills/<name>/` | `SKILL.md`; also reads `AGENTS.md` | `obra/superpowers` ships `.codex-plugin/plugin.json` with `"skills": "./skills/"`; Codex is a founding `AGENTS.md` adopter | `AL_CODEX_HOME` |
| opencode | `~/.config/opencode/skills/<name>/` | `SKILL.md` via native `skill` tool; also `AGENTS.md` | `superpowers/.opencode/INSTALL.md` documents `~/.config/opencode/skills/` and a `skills.paths` key in `opencode.json` | `AL_OPENCODE_HOME` |
| Cursor | `.cursor/rules/*.mdc` | **different format**: frontmatter is `description` / `globs` / `alwaysApply` | `superpowers/.cursor-plugin/plugin.json`; `.cursorrules` is deprecated in favour of `.cursor/rules/` | `AL_CURSOR_DIR` |
| Everything else | `AGENTS.md` at repo root | plain Markdown, no required fields | `agents.md` — nearest file wins, explicit user prompts override everything | `AL_REPO_ROOT` |

`AGENTS.md` is the widest net. Per agents.md, adopters include Codex, Cursor,
Jules, Factory, Aider, goose, opencode, Zed, Warp, VS Code, Devin, Junie, Amp,
RooCode, Gemini CLI, Kilo Code, Copilot coding agent, Windsurf, and Augment
Code. That is why `install.sh` writes it for every target.

## Why Cursor is handled differently

Cursor's `.mdc` frontmatter (`description`, `globs`, `alwaysApply`) is not
`SKILL.md` frontmatter (`name`, `description`). Symlinking a `SKILL.md` into
`.cursor/rules/` would produce a rule Cursor cannot parse correctly.

So the installer generates one thin `.cursor/rules/agentic-loop.mdc` that points
at the skill sources by absolute path. The skill bodies remain the single source
of truth; only the pointer is per-harness. Verified: the generated file has
`.mdc` frontmatter and names every shipped skill.

## Frontmatter: what is actually required

The portable subset — every harness above accepts it:

```yaml
---
name: skill-name          # lowercase, hyphens; matches directory name
description: Use when ... # trigger first; this is what the model sees
---
```

Everything else is harness-specific and deliberately omitted from our skills:

- Claude Code additionally supports `when_to_use`, `allowed-tools`,
  `disallowed-tools`, `model`, `effort`, `context: fork`, `agent`, `background`,
  `hooks`, `paths`, `shell`, `argument-hint`, `arguments`,
  `disable-model-invocation`, `user-invocable`. All optional. `name` itself is
  optional there — it defaults to the directory name — but we set it because
  other harnesses are less forgiving.
- Hermes additionally reads a `metadata.hermes` block with `tags` and
  `related_skills`.

Anthropic's own reference skills (`anthropics/skills`) ship only `name`,
`description`, and sometimes `license`. Their `template/SKILL.md` is `name` +
`description` and nothing else. We match that.

`description` carries the whole trigger, because that is often all the model sees
before deciding to load the skill. Claude Code truncates the combined
`description` + `when_to_use` at 1,536 characters in its skill listing; put the
key use case first.

## Distribution formats we deliberately skipped

`obra/superpowers` — the most complete cross-harness precedent, 234 files —
maintains **five** parallel plugin manifests: `.claude-plugin/`,
`.codex-plugin/`, `.cursor-plugin/`, `.kimi-plugin/`, `.agents/plugins/`, plus
`.opencode/plugins/superpowers.js`, `gemini-extension.json`, and sync scripts
(`sync-to-codex-plugin.sh`, `package-codex-plugin.sh`) to keep them aligned.

That buys one-line marketplace installs (`/plugin install …`,
`gemini extensions install …`, `pi install git:…`) at the cost of a build step
and five manifests drifting out of sync.

We chose a single `install.sh` instead: one source directory, symlinked into
whichever harness is present. No build step, no sync scripts, no per-harness
copies of the skill text. The tradeoff is no marketplace one-liner. If that
becomes worth it, `.claude-plugin/marketplace.json` is the smallest next step —
its verified shape is:

```json
{
  "name": "...",
  "owner": { "name": "...", "email": "..." },
  "metadata": { "description": "...", "version": "1.0.0" },
  "plugins": [
    { "name": "...", "description": "...", "source": "./",
      "strict": false, "skills": ["./skills/evidence-gate"] }
  ]
}
```

(Read from `anthropics/skills/.claude-plugin/marketplace.json`. Plugin objects
there use exactly `description`, `name`, `skills`, `source`, `strict`.)

## Verified on this machine

macOS 15.6.1, Bash 3.2, no GNU coreutils.

| Check | Result |
|---|---|
| Install to 6 targets, idempotent, uninstall clean | pass |
| Symlink resolves to single source; no nested links | pass |
| `--dry-run` writes zero files | pass |
| `--mode copy` produces a real snapshot | pass |
| Existing `AGENTS.md` never overwritten | pass |
| Config cascade: env beats `.env` beats `config.env` | pass |
| `.env` parsed as data — command substitution never executes | pass |
| Redaction by value and by pattern; secrets absent from logs and artifacts | pass |
| Tri-state ladder: FAIL=1, UNKNOWN=2, UNKNOWN outranks FAIL | pass |
| Scanner: findings=1, clean=0, tool-missing=2, values never printed | pass |
| Fixture allowlist does not mask a leak outside the fixture directory | pass |
| Portable timeout returns 124 and kills the child (perl fallback) | pass |
| Stack detection: Node, Go, PHP, Python, Rust | pass |
| Event log idempotent by content hash; values redacted | pass |
| `AL_LEGAL_HOLD` and dry-run block deletion; artifacts survive `clean` | pass |
| `al verify` reports live Hermes config drift as FAIL, unknown fields as SKIP | pass |

## Not verified

Honest gaps, in rough order of how much they matter:

- **No harness was driven end to end.** We verified the files land in the right
  place with the right shape. We did not start Claude Code, Codex, Cursor, or
  opencode and confirm each one loads and invokes the skill.
- **Linux and Windows untested.** Only macOS + Bash 3.2. The perl timeout
  fallback exists precisely because macOS lacks GNU `timeout`; on Linux the
  coreutils path is used and is less exercised here.
- **Codex skills directory is inferred**, not read from Codex documentation. It
  comes from how `superpowers` packages its Codex plugin. `AGENTS.md` is the
  reliable Codex path; treat `~/.codex/skills/` as best-effort.
- **opencode `skills.paths`** in `opencode.json` is documented upstream but our
  installer does not write it. Skills land in the conventional directory only.
- **No automated test suite.** Everything above was ad-hoc verification, run and
  discarded. Regressions will not be caught automatically.
- **Only Hermes has a `harness_mapping`** in `agent-policy.yaml`. Claude, Codex,
  Cursor, and opencode entries are empty, so `al verify` reports SKIP for them
  rather than checking anything.
