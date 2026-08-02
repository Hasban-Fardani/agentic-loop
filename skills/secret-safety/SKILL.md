---
name: secret-safety
description: Use when handling tokens, API keys, or credentials in an agent workflow — wiring config so secrets come from env instead of hardcoded values, keeping .env out of git while publishing .env.example, redacting secrets from logs and artifacts, or scanning a repo before it goes public. Also use when a secret may already have leaked into a commit, log, or artifact. Do not use for choosing a secret manager or rotating production credentials.
version: 0.1.0
license: MIT
metadata:
  agentic-loop:
    tags: [secrets, redaction, env, gitignore, scanning, pii]
    requires_commands: [git, grep]
---

# Secret Safety

## Overview

Two rules cover almost everything:

1. **Secrets live in the environment.** Never in code, never in a committed file, never in a log, never in an artifact.
2. **`.env` is never committed; `.env.example` always is.** One documents the shape, the other holds the values.

Everything below is mechanism for making those two rules hard to break by accident.

## When to Use

- Adding a token, key, or credential to any workflow
- Setting up config so the same code runs locally and in CI without edits
- Writing logs or artifacts that could contain sensitive values
- Preparing a repo to go public, or auditing one that already is
- A secret may have leaked — into a commit, a log, an artifact, or a chat

Don't use for: picking a secret manager, or rotating production credentials. That is operations, not agent hygiene.

## Config layering

Precedence, lowest to highest:

```text
built-in default  <  ~/.config/agentic-loop/config.env  <  ./.env  <  environment
```

Environment wins deliberately. CI secret stores export real environment variables, so they must beat any committed or on-disk file. `.env` is developer convenience; the environment is authority.

```bash
al doctor        # effective config, which files loaded, which secrets are set
```

`al doctor` prints secret **names and lengths, never values**. Any config report that could paste a token into a terminal, a CI log, or a chat transcript is itself a leak.

Two properties worth relying on:

- **`.env` is data, not script.** It is parsed line by line, never sourced. `EVIL=$(rm -rf /)` in a `.env` is a literal string, not a command. Never `source` a `.env` you did not write.
- **Empty is a real value.** `AL_FOO=` means "deliberately empty" and is not replaced by the default. Unset and empty are different states.

## Adding a new setting

1. Add the default in `core/lib/config.sh` via `al_set_default`. Secrets get **no default** — absent must fail loudly, not silently fall back.
2. Document it in `.env.example` with a comment explaining what it does. Secrets appear as a bare `KEY=` with no value.
3. If it is a credential, add its **name** to `AL_SECRET_VARS` so its value is redacted everywhere.
4. `al doctor` to confirm the effective value.

Done when the setting is changeable purely by environment, with no source edit in any consuming repo.

## Redaction

Two independent layers, because either alone leaks:

- **By value** — anything in `AL_SECRET_VARS` is replaced with `[REDACTED:NAME]`. Precise, but only for names you registered.
- **By pattern** — `AL_SECRET_PATTERN` catches credential shapes (`ghp_…`, `AKIA…`, `sk-…`, PEM headers) even from tools you do not control.

Redaction applies at the write boundary, so nothing unredacted reaches disk:

```bash
some_command 2>&1 | al_redact > "$log"
rc=${PIPESTATUS[0]}   # the command's status, not sed's
```

`PIPESTATUS[0]` matters: without it the filter's exit code masks the real failure and a broken step reports success.

Values under 8 characters are intentionally not redacted — too generic, and shredding every `abc` in a log destroys the log without protecting anything.

## Scanning

```bash
al scan                    # whole repo
al scan path/to/dir        # narrower scope
```

Exit codes are tri-state and deliberate: `0` clean, `1` findings, **`2` could not be proven** (scanner or tool missing). A `2` is never a pass. A missing scanner must fail the gate, not quietly skip it.

Findings print **location only** — file and line, never the matched value. A scanner that echoes what it found copies the secret into your log.

Repos holding synthetic credentials as test fixtures set `AL_ALLOW_FIXTURE_SECRETS=1`, which allowlists findings **only** under `AL_FIXTURE_DIR`. A finding anywhere else defeats the allowlist entirely. Never widen this to silence a real leak.

## Publishing a repo safely

1. `.gitignore` contains `.env` and `!.env.example`. The negation matters — a broad `.env*` would exclude the example too.
2. Confirm `.env` was never tracked:
   ```bash
   git check-ignore -q .env && echo "ignored"
   git ls-files --error-unmatch .env 2>/dev/null && echo "DANGER: tracked"
   ```
   Being in `.gitignore` does nothing if the file was committed before the rule existed.
3. `.env.example` holds no real values — only keys, comments, and safe defaults.
4. `al scan` over the whole repo returns 0.
5. Check history, not just the working tree:
   ```bash
   git log --all --full-history -- .env
   git grep -nE 'ghp_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}' $(git rev-list --all) 2>/dev/null | head
   ```

Done when all five hold. If step 5 finds anything, treat the credential as compromised.

## If a secret leaked

Order matters — rotation first, because cleanup takes time and the credential is live throughout.

1. **Rotate immediately.** Assume compromise the moment it touches a shared log, a push, or a transcript. Scrubbing history does not un-share it.
2. Remove it from the working tree and from `AL_SECRET_VARS`-adjacent config.
3. Purge from history only after rotating — `git filter-repo`, or a fresh repo if history has no value. Force-pushing rewritten history is destructive and coordinated: every collaborator must re-clone.
4. Add the pattern to `AL_SECRET_PATTERN` so it cannot recur silently.
5. Record the incident. A rotated key with no record repeats.

## Common Pitfalls

1. **`.env*` in `.gitignore` without `!.env.example`.** The example never ships and new contributors have no idea what to set.
2. **Assuming `.gitignore` protects an already-tracked file.** It does not. Verify with `git ls-files`.
3. **Printing config for debugging.** `env | grep TOKEN` in a CI log is a public leak. Use `al doctor`.
4. **Redacting by pattern only.** A token with a novel shape sails through. Register its name in `AL_SECRET_VARS`.
5. **Redacting by name only.** A tool you do not control echoes its own credential. Keep the pattern layer.
6. **Losing the exit code through the redaction pipe.** Use `${PIPESTATUS[0]}` or the step silently passes.
7. **Treating scanner-unavailable as clean.** `2` means unproven. Fail closed.
8. **Widening `AL_ALLOW_FIXTURE_SECRETS` past the fixture directory** to quiet a finding. That is disabling the alarm because it rang.
9. **Committing `.env` "just for a moment" to share with a teammate.** It is in history immediately; rotate.
10. **Scanning the working tree only.** History and stashes hold secrets too.

## Verification Checklist

- [ ] `git check-ignore -q .env` succeeds
- [ ] `git ls-files --error-unmatch .env` fails (not tracked)
- [ ] `.env.example` exists, is tracked, and contains no real credential
- [ ] Every secret name appears in `AL_SECRET_VARS`
- [ ] `al scan` over the full repo exits 0
- [ ] `al doctor` shows secrets as name + length, never value
- [ ] Logs and artifacts grepped for the actual token value — zero hits
- [ ] Scanner-unavailable was treated as blocking, not clean
- [ ] Any leaked credential was rotated before history cleanup began
