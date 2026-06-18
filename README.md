# ai-forge

> A structured knowledge base for working with AI tools — prompts, skills, agents, hooks, commands, and project-specific resources.

## What's in here

| Folder | Purpose |
|--------|---------|
| `skills/` | Reusable AI skills, organized by `common/` and `projects/` |
| `commands/` | Slash commands and shortcuts for AI tools |
| `hooks/` | Lifecycle hooks (pre/post actions in AI workflows) |
| `subagents/` | Specialized sub-agent definitions |
| `ai/` | AI-specific configuration (Claude, Cursor, etc.) |

## Conventions

### Skills

Each skill lives in its own folder:

```txt
ai-forge/
├── AGENTS.md                         # Root-level agent conventions
├── .agents/                          # Root-level agent files
│   └── default.md
│
├── skills/                           # Reusable skills (AI-agnostic when possible)
│   ├── common/
│   │   └── {skill-name}/
│   │       └── SKILL.md
│   └── projects/
│       └── {project-name}/
│           └── {skill-name}/
│               ├── SKILL.md          # The actual skill
│               └── PROMPT.md         # Prompt to generate/update the skill
│
├── commands/
│   ├── common/
│   └── projects/
│
├── hooks/
│   └── {hook-name}.md
│
├── subagents/
│   └── {agent-name}/
│       └── AGENTS.md
│
├── ai/                               # AI-specific configs & overrides
│   ├── claude/
│   │   ├── AGENTS.md
│   │   └── settings/
│   └── cursor/
│       ├── .cursorrules
│       └── prompts/
│
└── README.md
```
