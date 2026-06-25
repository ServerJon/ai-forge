---
name: context7-cli
description: Context7 CLI to look up libraries / frameworks and other documentations
user-invocable: false
---

# context7-cli

Look up **current** library / framework / SDK / CLI documentation by invoking the `ctx7` CLI. Prefer this explicit, reproducible shell command over the Context7 MCP server; fall back to the MCP only when the CLI is unavailable (see [Fallback — Context7 MCP](#fallback--context7-mcp)).

## When to use

Auto-invoke this skill **before answering** whenever the user asks about:

- A specific library, framework, or SDK (FastAPI, SQLAlchemy, Alembic, Pydantic, Poetry, React, Next.js, Tailwind, ...).
- Setup / configuration steps that depend on a third-party tool's CLI flags.
- Version migration questions (e.g. "what changed in SQLAlchemy 2.0?").
- API syntax that may have changed since the model's training cutoff.

Use it even when you "think you know the answer" — the whole point is to defer to current docs over training-data recall.

## When NOT to use

- Refactoring existing project code (read the code, not the library).
- Debugging business logic in this repo (use Grep / project search).
- General programming concepts ("what is a closure?", "explain dependency injection").
- Code review or design questions (use the appropriate review skill).

## Prerequisite — Auth

The CLI is authenticated once per machine via:

```bash
ctx7 setup --cli --api-key <YOUR_API_KEY> -y
```

The key is persisted under `~/.context7/`. Verify with `ctx7 whoami`. If `ctx7 whoami` returns "not logged in", stop and ask the user to run setup — do not attempt to call `ctx7 library` or `ctx7 docs` without auth (they'll error and waste a turn).

Alternative: set `CONTEXT7_API_KEY` in `~/.zprofile`. The CLI falls back to the env var when no config file is found.

## Invocation wrapper

`ctx7` requires Node 22+. The `~/.zprofile` is patched to prepend the nvm-default node bin to PATH for any newly-spawned login shell, so a freshly-launched the agent session can invoke `ctx7` directly.

In an **already-running** session whose shell predates the `.zprofile` edit, wrap every call in a fresh login shell:

```bash
zsh -l -c 'ctx7 <subcommand> ...'
```

This works in both cases (cached or fresh environment), so default to the wrapped form if uncertain. The ~30 ms overhead is negligible compared to the network round-trip ctx7 makes.

## Two-step lookup flow

Always do steps 1 and 2 — never guess a library ID from training data, since it must come from step 1 to be guaranteed valid.

### Step 1 — Find the library ID

```bash
zsh -l -c 'ctx7 library <name> "<intent>" --json'
```

- `<name>`: the package name as the user said it (`fastapi`, `sqlalchemy`, `alembic`).
- `<intent>`: a short phrase describing what you want to look up. The intent narrows ambiguous matches (e.g. `react` could be Facebook React or another library).
- `--json`: returns a JSON array of candidates; pick `.[0].id` unless something else looks more relevant.

ID format: `/<org>/<project>` or `/<org>/<project>/<version>` (always starts with `/`).

### Step 2 — Fetch the focused docs

```bash
zsh -l -c 'ctx7 docs <library-id> "<question>" --json'
```

- `<library-id>`: from step 1.
- `<question>`: the actual question. Phrase it as a developer would search ("how to define a dependency", "what's the syntax for Annotated"), not as a vague topic ("dependencies").
- `--json`: structured output. Omit `--json` when you want to read the result yourself (terminal-formatted with code blocks).

### Example — FastAPI dependency injection

```bash
# Step 1
zsh -l -c 'ctx7 library fastapi "dependency injection with Depends" --json' | jq '.[0]'
# → { "id": "/tiangolo/fastapi", "name": "FastAPI", "description": "..." }

# Step 2
zsh -l -c 'ctx7 docs /tiangolo/fastapi "How to declare a dependency with Annotated and Depends" --json'
```

## Output handling rules

- For programmatic use (parsing version numbers, extracting code snippets to paste into edits): use `--json` and pipe to `jq`.
- For human-readable answers: omit `--json`; the terminal output is markdown-formatted.
- Cite the library version that ctx7 returned in your reply ("Per FastAPI 0.115 docs..."). The user benefits from knowing which version informed the answer.

## Telemetry

To opt out of anonymous usage data:

```bash
export CTX7_TELEMETRY_DISABLED=1
```

(Set in `~/.zprofile` if you want it permanent.)

## Failure modes — what to do

| Symptom                                 | Likely cause                                   | Fix                                                                  |
| --------------------------------------- | ---------------------------------------------- | -------------------------------------------------------------------- |
| `ctx7: command not found`               | Old shell, .zprofile patch hasn't taken effect | Use the `zsh -l -c '...'` wrapper, or restart the the agent session. |
| `SyntaxError: Unexpected token 'with'`  | ctx7 ran on Node 18 (incompatible)             | Same — wrapper or session restart.                                   |
| `Not authenticated` / `Invalid API key` | Setup not run, or key revoked                  | Ask the user to run `ctx7 setup --cli --api-key <key> -y`.           |
| Empty result from `ctx7 library`        | Library not indexed by Context7                | Fall back to `WebFetch` against the library's official docs URL.     |
| Network timeout                         | Context7 service blip                          | Retry once after 5s; if still failing, fall back to WebFetch.        |

## Fallback — Context7 MCP

Use the `ctx7` CLI as the **primary** method. Fall back to the **Context7 MCP server** only when the CLI cannot be used — e.g. `ctx7: command not found` persists after the `zsh -l -c` wrapper, Node < 22 with no upgrade path, or auth cannot be completed in the current environment.

The MCP exposes the same two-step flow as the CLI:

| Step | CLI command            | Context7 MCP tool                     |
| ---- | ---------------------- | ------------------------------------- |
| 1    | `ctx7 library <name>`  | `mcp__context7__resolve-library-id`   |
| 2    | `ctx7 docs <id> <q>`   | `mcp__context7__get-library-docs`     |

- Requires the `context7` MCP server configured in the project (`.mcp.json` / `.cursor/mcp.json`). See `assets/MCPs/.mcp.json` for a template.
- Once the CLI is healthy again, return to it — the MCP is a stopgap, not the default.

## Why CLI over MCP for this project

- Reproducibility: every lookup is a shell command visible in tool-call logs, easy to grep.
- No MCP server lifecycle to manage (no stale connection, no separate auth dance).
- The CLI works the same way for me, for cron jobs, and for the user typing it themselves.
- The MCP remains available as a fallback (above) when the CLI can't run.
