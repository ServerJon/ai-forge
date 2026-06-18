# Prompt template

`PROMPT.md` is the **source of truth** for generating a skill. If you need to recreate or update a `SKILL.md`, start here.

## Agents

This repo follows the `AGENTS` pattern:

- `AGENTS.md` at the root defines global agent conventions
- `.agents/` holds agent definition files
- Sub-folders may have their own `AGENTS.md` to scope behavior

## Project resources

Project-specific resources live under `skills/projects/{project-name}/`. Each project folder mirrors the common structure but scoped to that context.

## Supported AI tools

- **Claude** — skills, subagents, hooks (`ai/claude/`)
- **Cursor** — rules, prompt files (`ai/cursor/`)

## Contributing / evolving this repo

- When creating a new skill from a prompt, keep both `SKILL.md` and `PROMPT.md` in sync.
- Prefer general skills in `common/` unless the skill is tightly coupled to a project's domain.
- Document non-obvious decisions directly in the relevant `SKILL.md` or `AGENTS.md`.
