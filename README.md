# ai-forge

[![License: CC BY 4.0](https://img.shields.io/badge/License-CC%20BY%204.0-lightgrey.svg)](LICENSE.md)

> A structured toolkit of skills, agents, and configuration for AI coding assistants — works with Cursor, Claude Code, and other agent runtimes.

[Overview](#overview) • [Getting started](#getting-started) • [Project structure](#project-structure) • [Skills catalog](#skills-catalog) • [Agents catalog](#agents-catalog) • [What to build next](#what-to-build-next) • [Resources](#resources)

---

## Overview

**ai-forge** is a curated library of reusable `SKILL.md` and agent definition files you can install into any project. Once installed, your AI assistant (Cursor, Claude Code, etc.) gains deep, project-aware capabilities — from running hexagonal-architecture scaffolding to performing security reviews and managing GitLab MRs.

The skills are AI-runtime agnostic: they follow the `AGENTS.md` / `SKILL.md` convention, so the same file works across Cursor, Claude Code, and any tool that reads agent context files.

---

## Getting started

### Prerequisites

| Tool              | Why                                      | Check / install                        |
| ----------------- | ---------------------------------------- | -------------------------------------- |
| Node.js ≥ 22      | Runs `npx`-based tools                   | `node -v` · `nvm install 22`           |
| `ctx7` (optional) | Up-to-date library docs inside the agent | `npx ctx7@latest --version`            |
| `glab` (optional) | GitLab operations skill                  | `brew install glab && glab auth login` |
| `gh` (optional)   | GitHub operations skill                  | `brew install gh && gh auth login`     |

### Install skills into a project

```bash
# Clone or add as a submodule
git clone https://github.com/your-org/ai-forge
cd ai-forge

# Ensure the installer is executable (only needed once)
chmod +x install.sh

# Run the interactive installer, targeting your project
./install.sh -p /path/to/your-project
```

> [!IMPORTANT]
> `install.sh` must have execute permission. If you see `permission denied`, run `chmod +x install.sh` (or invoke it with `bash install.sh -p /path/to/your-project`).

The installer presents a checkbox menu. Select any combination of skills and agents, checks dependencies, then copies the selected `SKILL.md` files into your project's `.agents/` folder and drops a pre-filled `AGENTS.md` at the project root.

Useful flags:

| Flag              | Effect                                                     |
| ----------------- | ------------------------------------------------------------ |
| `-p <path>`       | Target project path (skips the interactive prompt)         |
| `-y`, `--yes`     | Assume "yes" for confirmation prompts                       |
| `-n`, `--dry-run` | Preview what would be installed without writing anything    |
| `-h`, `--help`    | Show usage                                                  |

> [!TIP]
> Run `npx autoskills --dry-run` in your project first to cover common framework skills, then use `install.sh` to layer on the ai-forge extras that autoskills doesn't provide.

### Post-install

After `install.sh` completes, open your AI assistant and run:

```
From the `AGENTS.md` file, review it and complete all TODO sections.
```

This customises the generated `AGENTS.md` to your project's specifics.

---

## Project structure

```
ai-forge/
├── AGENTS.template.md          # Starter AGENTS.md — copied to target project on install
├── AUTO-SKILLS.md              # Reference: autoskills integration and gap analysis
├── install.sh                  # Interactive skill/agent installer
│
├── agents/                     # Agent definitions (copied to .agents/agents/)
│   ├── common/                 # Architecture reviewer, debugger, MR/PR reviewer, principal engineer
│   └── angular/                # Angular i18n reviewer
│
├── assets/
│   ├── MCPs/                   # Ready-to-use mcp.json for MCP server configuration
│   └── test-helper.js          # Shared Playwright helpers (waitForCondition, screenshots, etc.)
│
└── skills/                     # Reusable skills (copied to .agents/skills/)
    ├── common/                 # context7-cli, create-mr-pr, create-readme, gh, git-workflow, glab, security-review, sync-ai, sync-ai-doc
    ├── angular/                # Angular conventions
    ├── astro/                  # Astro framework skills (core, i18n, components, pages, testing)
    ├── back4app-mcp/           # Back4App (Parse Server) MCP operations — data, schema, Cloud Code deploys
    ├── chrome/                 # Chrome DevTools debugging
    ├── hexagonal-architecture/ # Alembic migrations, entity scaffolding, error codes, endpoint docs, testing
    ├── javascript-typescript/  # Jest, Vitest, advanced TypeScript types
    ├── playwright/             # E2E testing, playwright-cli, web design reviewer, webapp testing
    ├── python/                 # pytest conventions
    ├── react/                  # React 17 patterns
    └── sql/                    # SQL code review, query optimisation
```

Skills that have special setup instructions include a `README.md` in their folder (e.g. `skills/angular/`, `skills/hexagonal-architecture/`, `skills/playwright/webapp-testing/`).

---

## Skills catalog

### Common

| Skill             | What it does                                                                 |
| ----------------- | ---------------------------------------------------------------------------- |
| `context7-cli`    | Fetches up-to-date library docs via `ctx7` before answering any API question |
| `create-mr-pr`    | Opens a well-structured MR/PR with description, checklist, and linked issues |
| `create-readme`   | Generates or rewrites a `README.md` by analysing the full workspace          |
| `gh`              | Full GitHub CLI operations (PRs, issues, Actions, releases, API) via `gh`    |
| `git-workflow`    | Guides branch naming, commit conventions, and rebase flow                    |
| `glab`            | Full GitLab CLI operations (issues, MRs, pipelines) via `glab`               |
| `security-review` | Audits code for secrets, injection vectors, and vulnerable patterns          |
| `sync-ai`         | Syncs AI context files (AGENTS.md, .cursorrules, etc.) across tools          |
| `sync-ai-doc`     | Keeps AI documentation in sync with source changes                           |

### Framework / language

| Skill folder             | Skills                                                                            |
| ------------------------ | --------------------------------------------------------------------------------- |
| `angular`                | Angular coding conventions                                                        |
| `astro`                  | Astro core, i18n, new components, pages, testing                                  |
| `back4app-mcp`           | Back4App (Parse Server) live backend ops — data/schema inspection, Cloud Code & web-hosting deploys via MCP |
| `chrome`                 | Chrome DevTools debugging with MCP                                                |
| `hexagonal-architecture` | Alembic migrations, new entities, error codes, endpoint docs, integration testing |
| `javascript-typescript`  | Jest, Vitest, advanced TypeScript types                                           |
| `playwright`             | E2E testing, CLI automation, web-design review, webapp testing                    |
| `python`                 | pytest patterns                                                                   |
| `react`                  | React 17 patterns                                                                 |
| `sql`                    | Code review, query optimisation                                                   |

---

## Agents catalog

| Agent                         | What it does                                                          |
| ----------------------------- | --------------------------------------------------------------------- |
| `principal-software-engineer` | Senior-level code review, architecture guidance, and decision making  |
| `architecture-reviewer`       | Reviews architectural decisions and flags structural issues           |
| `debug`                       | Systematic debugging assistant for complex runtime failures           |
| `mr-pr-reviewer`              | Reviews merge/pull requests against project conventions               |
| `angular/i18n-reviewer`       | Reviews Angular i18n implementations for correctness and completeness |

---

## MCP configuration

`assets/MCPs/mcp.json` is a ready-to-use MCP server configuration (Postgres, memory, Docker, Nx). Copy it to your project root as `.mcp.json` and remove any entries you don't need.

> [!NOTE]
> The `back4app-mcp` skill is a worked example of an MCP-backed skill for a specific app (GastrOleum) — it references companion skills (`angular-service`, `cloud-code`) that live in that app's own repo, not here. Use it as a template for writing your own live-backend MCP skill rather than installing it as-is.

---

## What to build next

After the install is complete, consider extending your setup with these additional skills:

### Frontend

| Skill idea | What it would cover |
| --- | --- |
| Web design system skill | Design tokens, component naming conventions, spacing/typography rules for AI-assisted UI work |
| Web UI patterns skill | Common layout and interaction patterns (forms, modals, navigation) for consistent component generation |

> [!TIP]
> You can use the `create-skill` Cursor skill to scaffold any of these. Describe the skill's purpose and the agent will generate a ready-to-use `SKILL.md`.

---

## Resources

- [autoskills](https://github.com/midudev/autoskills) — auto-install community skills from a curated registry
- [awesome-copilot](https://github.com/github/awesome-copilot) — GitHub's curated collection of Copilot instructions, prompts, and chat modes
- [AUTO-SKILLS.md](./AUTO-SKILLS.md) — how ai-forge and autoskills relate, gap analysis
- [AGENTS.template.md](./AGENTS.template.md) — full project AGENTS.md template with all sections
