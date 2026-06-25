---
name: sync-ai-doc
description: Propagate changes from AGENTS.md (the source of truth) to the per-agent instruction files of other AI tools (CLAUDE.md, GEMINI.md, etc.), applying path/naming translation and skipping anything the target agent cannot use. Use whenever editing an AGENTS.md (root or nested), adding skills/agents/hooks/MCP entries to it, updating auto-invoke tables, or modifying project instruction files. Asks which AI agent(s) to target.
user-invocable: false
---

# Sync AI Docs (`/sync-ai-doc`)

`AGENTS.md` is the **single source of truth** for project instructions — it uses
the tool-agnostic `agents.md` convention and `.agents/…` paths. Other AI tools
that do **not** read `AGENTS.md` natively keep their own instruction file
(`CLAUDE.md` for Claude Code, `GEMINI.md` for Gemini, …). Those derived files
must mirror `AGENTS.md`, translated to each tool's paths and naming, and **minus
anything that tool can't actually use**.

Direction is one-way: `AGENTS.md` → derived docs. Never edit a derived doc by
hand and expect it to flow back.

> Cursor reads `AGENTS.md` (root and nested) natively — there is no `CURSOR.md`
> and nothing to generate for Cursor. It is intentionally absent from the target
> list below.

## Why both files exist (given the symlinks)

`.claude/skills` and `.claude/agents` are directory **symlinks** into
`.agents/`, so `SKILL.md` and subagent files are single-source — editing through
either path writes the same inode. Only the _instruction docs_ (`AGENTS.md` vs
`CLAUDE.md`) are distinct files, because the literal path **strings** inside them
(`[SKILL.md](.agents/skills/foo/SKILL.md)` vs `.claude/skills/foo/SKILL.md`) and
the tool naming (`AI coding agents` vs `Claude Code`) differ per tool.

## Step 1 — Ask which AI agent(s) to update

Ask the user which target AI agent(s) to sync (use `AskQuestion`,
`allow_multiple: true`). When the skill auto-fires on an `AGENTS.md` edit, you may
skip the prompt and default to **every derived doc that already exists** beside
the changed `AGENTS.md`.

| AI agent    | Doc file    | Skills path       | Agents path       | Reads `AGENTS.md` natively? |
| ----------- | ----------- | ----------------- | ----------------- | --------------------------- |
| Claude Code | `CLAUDE.md` | `.claude/skills/` | `.claude/agents/` | No → generate `CLAUDE.md`   |

To support a new tool later, add a row mapping it to its doc filename and path
prefixes, and offer it as an option in the question. Tools that read `AGENTS.md`
natively (e.g. Cursor) need no derived doc — do not add them here.

## Step 2 — Locate the paired files

For each changed `AGENTS.md` (root **or** any nested directory) and each selected
agent, the paired doc is the agent's doc file in the **same directory**:

- root `AGENTS.md` → root `CLAUDE.md`
- `<dir>/AGENTS.md` → `<dir>/CLAUDE.md` (nested, e.g. `athletics-tech-api/AGENTS.md` → `athletics-tech-api/CLAUDE.md`)

If the paired doc does not exist yet, **create it** (header from Step 5).

## Step 3 — Compatibility gate (review before copying)

Before mirroring a section, check whether what it documents is usable by the
target agent. If it is not, **omit that section** from the derived doc (or replace
it with the agent's equivalent) instead of copying it verbatim. This mirrors the
per-tool nuances in [`sync-ai`](../sync-ai/SKILL.md).

Decide per section (example target = Claude Code):

- **Skill** under `.agents/skills/` — ✅ translate path to `.claude/skills/`.
- **Subagent** under `.agents/agents/` — ✅ translate path to `.claude/agents/`.
- **Hook script** under `.agents/hooks/` — ✅ keep the script path; its config lives in `.claude/settings.json`.
- **MCP server** (HTTP/stdio) in `.agents/mcp/` — ✅ keep; config is the root `.mcp.json`.
- **Cursor-only plugin** (e.g. the Atlassian plugin) — ❌ Claude has no plugin system; skip it, or document the `.mcp.json` equivalent if one exists.
- **Cursor-only hook event** with no Claude analog — ❌ skip that entry.

Rule of thumb: if the feature has a Claude-side equivalent, **translate** it; if it
has none, **skip** it (and briefly note the skip in your final summary so the user
knows that section was intentionally not mirrored).

## Step 4 — Path & naming translation

When copying surviving content from `AGENTS.md` into a derived doc, translate:

| In `AGENTS.md`       | In `CLAUDE.md`       |
| -------------------- | -------------------- |
| `.agents/skills/`    | `.claude/skills/`    |
| `.agents/agents/`    | `.claude/agents/`    |
| `../.agents/skills/` | `../.claude/skills/` |
| `../.agents/agents/` | `../.claude/agents/` |

Also translate, beyond paths:

- `AGENTS.md` as a self-reference in prose (e.g. "this `AGENTS.md`") → `CLAUDE.md`.
- Generic naming `AI coding agents` / `the current AI` → `Claude Code` / `Claude`.

**Do not translate** (shared or tool-neutral — identical on both sides):

- `.agents/hooks/…` — hook scripts are shared across tools (only the config file
  that references them differs; see Step 3).
- `.agents/mcp/…` — the shared MCP source file.
- Tool identifiers and protocol-style names: `Cursor`, `Claude Code`,
  `mcp__plugin_*`, `claude.ai/code`.

Everything else (skill tables, auto-invoke entries, rules, integration notes)
stays identical.

## Step 5 — Headers

Root files use tool-specific headers; component/nested files reuse the component
name as header in every version (no translation there).

**`AGENTS.md` (root):**

```markdown
# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.
```

**`CLAUDE.md` (root):**

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
```

## Step 6 — Verify

After writing each derived doc, grep for the wrong prefix in the wrong file:

```bash
# Untranslated source paths must NOT survive in a derived doc:
grep -nE "\.agents/(skills|agents)/" CLAUDE.md   # expect: empty

# Derived paths must NOT leak back into the source of truth:
grep -nE "\.claude/(skills|agents)/" AGENTS.md   # expect: empty
```

`.agents/hooks/` and `.agents/mcp/` matches are expected and fine in both files.

## Workflow

1. Edit `AGENTS.md` (root or a nested folder).
2. Determine targets (Step 1) and the paired docs (Step 2).
3. For each section, run the compatibility gate (Step 3): translate if the target
   supports it, skip if it does not.
4. Apply path + naming translation (Step 4) and the right header (Step 5).
5. Save each derived doc; never skip a derived doc for a "small" change.
6. Verify with the greps (Step 6) and report what was mirrored vs intentionally
   skipped, plus any newly created docs.

## Rules

1. **`AGENTS.md` is the source of truth** — edits flow one way, into derived docs.
   Never hand-edit `CLAUDE.md`/`GEMINI.md` and expect it to propagate back.
2. **No derived doc for native readers** — tools that read `AGENTS.md` directly
   (Cursor) get nothing generated.
3. **Gate before copy** — never mirror a feature the target agent cannot use;
   translate to its equivalent or skip it.
4. **Translate paths and naming** — `.agents/{skills,agents}/` and generic AI
   wording must match the target tool; shared `.agents/{hooks,mcp}/` stay as-is.
5. **Create missing pairs** — if a nested `AGENTS.md` has no derived doc yet,
   create one with the correct header.
