---
name: sync-ai
description: Command to sync `.agents/` (skills, agents, hooks, mcp) into a chosen AI tool's folder (`.claude/` or `.cursor/`) by creating missing relative symlinks and wiring the tool's hook and MCP config to the shared sources under `.agents/`. Run manually; asks which AI model to target before syncing.
user-invocable: true
disable-model-invocation: true
---

# Sync AI Tooling (`/sync-ai`)

`.agents/` is the single source of truth for skills and agents. AI tools read
from their own folder (e.g. Claude Code → `.claude/`), which holds **symlinks**
back to `.agents/`. This command (re)creates the missing symlinks in one pass.

This is a **manual command** — it does not auto-invoke. Run it after creating or
installing a new skill/agent, or after cloning on a new machine.

## How each tool discovers `.agents/` (read this first)

`.agents/` holds four shared sources — `skills/`, `agents/`, `hooks/`, and
`mcp/`. The tools differ in what they read natively and in their config formats,
so the sync does different work per source and per tool. Verified against the
official Cursor docs ([skills](https://cursor.com/docs/skills),
[subagents](https://cursor.com/docs/subagents), [hooks](https://cursor.com/docs/hooks)):

| Shared source     | Claude Code                             | Cursor                               |
| ----------------- | --------------------------------------- | ------------------------------------ |
| `.agents/skills/` | symlink → `.claude/skills/`             | **native** (no action)               |
| `.agents/agents/` | symlink → `.claude/agents/`             | symlink → `.cursor/agents/`          |
| `.agents/hooks/`  | referenced from `.claude/settings.json` | referenced from `.cursor/hooks.json` |
| `.agents/mcp/`    | symlink → `.mcp.json` (repo root)       | symlink → `.cursor/mcp.json`         |

Two gotchas:

- **Subagents (Cursor)**: Cursor discovers skills from `.agents/skills/` directly,
  but **subagents are only loaded from `.cursor/agents/`** (or `.claude/`, `.codex/`),
  never from `.agents/agents/`. So for Cursor the only real work is linking agents
  into `.cursor/agents/`; skills are already picked up and symlinking them would
  just create duplicate discoveries.
- **Hooks (both)**: hook _config schemas differ_ per tool (Cursor `hooks.json`
  uses event keys; Claude `settings.json` uses a `PostToolUse` matcher array), so
  the config can't be symlinked. Only the **scripts** in `.agents/hooks/` are
  shared — each tool's config just points at them by path.

## Step 1 — Ask which AI model to sync

Before doing anything, ask the user which AI tool to sync (use the `AskQuestion`
tool).

| AI model             | Target folder | Skills sync   | Agents sync |
| -------------------- | ------------- | ------------- | ----------- |
| Claude (Claude Code) | `.claude/`    | symlink       | symlink     |
| Cursor               | `.cursor/`    | none (native) | symlink     |

To support a new tool later, add a row here mapping it to its dot-folder and
offer it as an option in the question.

## Step 2 — Ask what to sync

In the same `AskQuestion` call (a second question, `allow_multiple: true`), ask
which of the four shared sources to sync. The user can pick one or several:

- **All** — `skills`, `agents`, `hooks`, and `mcp` (default)
- **Skills** (`.agents/skills/`) — symlink sync (Step 3)
- **Agents** (`.agents/agents/`) — symlink sync (Step 3)
- **Hooks** (`.agents/hooks/`) — wire tool hook config (Step 5)
- **MCP** (`.agents/mcp/`) — wire tool MCP config (Step 6)

Carry the choices into a `SELECTED` set and run only the matching steps:

| Selected | Runs                 |
| -------- | -------------------- |
| `skills` | Step 3 (skills pass) |
| `agents` | Step 3 (agents pass) |
| `hooks`  | Step 5               |
| `mcp`    | Step 6               |

> Cursor note: if the user targets **Cursor** and selects only `skills`, there is
> nothing to do — Cursor already reads `.agents/skills/`. Say so and stop.

## Step 3 — Run the symlink sync (skills / agents)

Run this step only if `skills` and/or `agents` were selected in Step 2. Set
`TOOL` from Step 1 and `KINDS` to the **skills/agents** subset of the selection,
then run from the project root. The script derives `AI_DIR` from `TOOL` and skips
the `skills` pass for Cursor (Cursor reads `.agents/skills/` natively). `hooks`
and `mcp` are handled in Steps 5–6, not here.

Use an array for `KINDS` (works in both zsh and bash; a plain string would not
word-split under zsh).

```bash
TOOL="claude"             # <- from Step 1: claude | cursor
KINDS=(skills agents)     # <- Step 2 ∩ {skills, agents}: (skills agents) | (skills) | (agents)

case "$TOOL" in
  claude) AI_DIR=".claude" ;;
  cursor) AI_DIR=".cursor" ;;
  *) echo "unknown tool: $TOOL (expected claude|cursor)"; return 1 2>/dev/null || exit 1 ;;
esac

for kind in "${KINDS[@]}"; do
  # Cursor discovers .agents/skills/ natively — symlinking would only create
  # duplicate skill definitions, so skip the skills pass for Cursor.
  if [ "$TOOL" = "cursor" ] && [ "$kind" = "skills" ]; then
    echo "skip: Cursor reads .agents/skills/ natively — no symlink needed"
    continue
  fi

  src=".agents/$kind"
  if [ ! -d "$src" ]; then
    echo "skip: $src does not exist"
    continue
  fi
  mkdir -p "$AI_DIR/$kind"
  # Skills are directories (skill/SKILL.md); agents are single .md files —
  # iterate both, so glob without a trailing slash.
  for entry in "$src"/*; do
    [ -e "$entry" ] || continue
    name=$(basename "$entry")
    link="$AI_DIR/$kind/$name"
    if [ -L "$link" ]; then
      echo "ok:     $link"
    elif [ -e "$link" ]; then
      echo "WARN:   $link exists and is not a symlink — left untouched"
    else
      ln -sfn "../../.agents/$kind/$name" "$link"
      echo "linked: $link -> ../../.agents/$kind/$name"
    fi
  done
done
echo "Sync complete for $AI_DIR."
```

> Cursor subagents require YAML frontmatter (`name`, `description`, optional
> `model`/`readonly`/`is_background`). Make sure each `.agents/agents/*.md` source
> file has it, otherwise Cursor will ignore the linked subagent.

## Step 4 — Report

After running every selected step (3, 5, and/or 6), give one combined summary:
what was linked or wired, what already existed, and any `WARN` entries (a real
file/dir sitting where a symlink should be — resolve manually, never overwrite
blindly). List any sources skipped because they were absent or not selected.

## Step 5 — wire up hooks from `.agents/hooks/`

Run this step only if `hooks` was selected in Step 2.

`.agents/hooks/` is the single source of truth for hook **scripts** (e.g.
`lint-format.sh`, which auto-detects the Cursor vs Claude payload shape and runs
`eslint --fix` on edited `.ts`/`.tsx` files, failing open). The config that _calls_
those scripts is tool-specific and cannot be symlinked, so register it per tool.

First make the scripts executable (no-op if already set):

```bash
chmod +x .agents/hooks/*.sh 2>/dev/null || true
```

Then pick the destination by the tool from Step 1 (create the file if missing,
preserve existing keys, do **not** duplicate an identical entry):

**Cursor** → merge into `.cursor/hooks.json` (schema version 1, event-based):

```json
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [{ "command": ".agents/hooks/lint-format.sh" }]
  }
}
```

**Claude** → merge into `.claude/settings.json` (`PostToolUse` matcher array):

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": ".agents/hooks/lint-format.sh" }
        ]
      }
    ]
  }
}
```

To add more hooks later, drop the script in `.agents/hooks/` and add an entry to
each tool's config above. For any other future tool, skip until its hook format
is documented here.

## Step 6 — wire up MCP servers from `.agents/mcp/`

Run this step only if `mcp` was selected in Step 2.

`.agents/mcp/mcp.json` is the single source of truth for MCP server definitions.
Both tools use the **same** `{ "mcpServers": { … } }` schema, so the tool's MCP
file can be a symlink back to the shared source. Pick the destination by the tool
from Step 1:

| Tool   | MCP config file         | Symlink command                                    |
| ------ | ----------------------- | -------------------------------------------------- |
| Cursor | `.cursor/mcp.json`      | `ln -sfn ../.agents/mcp/mcp.json .cursor/mcp.json` |
| Claude | `.mcp.json` (repo root) | `ln -sfn .agents/mcp/mcp.json .mcp.json`           |

Non-destructive rule (same as the symlink sync): only create the link when the
destination is missing or already the correct symlink. If a **real** `mcp.json`
already exists there, leave it and merge `.agents/mcp/mcp.json` into it manually.

```bash
TOOL="claude"   # <- from Step 1: claude | cursor
case "$TOOL" in
  cursor) link=".cursor/mcp.json"; target="../.agents/mcp/mcp.json"; mkdir -p .cursor ;;
  claude) link=".mcp.json";        target=".agents/mcp/mcp.json" ;;
  *) echo "unknown tool: $TOOL"; return 1 2>/dev/null || exit 1 ;;
esac

if [ ! -e ".agents/mcp/mcp.json" ]; then
  echo "skip: .agents/mcp/mcp.json does not exist"
elif [ -L "$link" ]; then
  echo "ok:     $link"
elif [ -e "$link" ]; then
  echo "WARN:   $link exists and is not a symlink — merge manually"
else
  ln -sfn "$target" "$link"
  echo "linked: $link -> $target"
fi
```

Example contents for `.agents/mcp/mcp.json` (Atlassian Jira/Confluence). Auth is a
browser-based OAuth 2.1 flow on first use — **no secrets** go in the file:

```json
{
  "mcpServers": {
    "atlassian": {
      "type": "http",
      "url": "https://mcp.atlassian.com/v1/mcp/authv2"
    }
  }
}
```

If a tool is on an older transport that can't speak HTTP, fall back to the
`mcp-remote` proxy for that server:

```json
{
  "mcpServers": {
    "atlassian": {
      "command": "npx",
      "args": [
        "-y",
        "mcp-remote@latest",
        "https://mcp.atlassian.com/v1/mcp/authv2"
      ]
    }
  }
}
```

> Endpoint note: the legacy `…/v1/sse` endpoint is unsupported after 30 Jun 2026 —
> always use `…/v1/mcp/authv2`.

> Cursor + Atlassian caveat: Cursor's first-party **Atlassian plugin** already
> provides the Rovo server (and Jira/Confluence skills). If you use the plugin,
> omit `atlassian` from `.agents/mcp/mcp.json` (or accept it will be defined twice
> for Cursor). Other MCP servers in the shared file still sync normally.

## Rules

1. **Source of truth is `.agents/`** — `skills/`, `agents/`, `hooks/`, and `mcp/`
   all live under `.agents/`; never author them directly in a tool folder
   (`.claude/…`, `.cursor/…`); create them in `.agents/…` first, then sync.
2. **Relative symlinks only** — `../../.agents/{kind}/{name}` for skills/agents
   (correct from `{AI_DIR}/{kind}/{name}`); MCP links use `.agents/mcp/mcp.json`
   from the repo root or `../.agents/mcp/mcp.json` from `.cursor/`.
3. **One direction** — tool folders symlink to `.agents/`, never the reverse.
4. **Non-destructive** — only create missing symlinks; never overwrite a real
   file/dir found at the target path (warn and merge manually instead).
5. **Skip absent kinds** — if a source like `.agents/agents/` or `.agents/mcp/`
   doesn't exist yet, that pass is skipped without error.
6. **Cursor skills are native** — never symlink `.agents/skills/` into
   `.cursor/skills/`; Cursor reads `.agents/skills/` directly, and duplicating it
   only creates conflicting skill discoveries. Cursor only needs `.agents/agents/`
   linked into `.cursor/agents/`.
7. **Hook config is per-tool, not symlinked** — only the scripts in
   `.agents/hooks/` are shared; each tool's hook config (`.cursor/hooks.json` vs
   `.claude/settings.json`) has a different schema and must be merged, not linked.
