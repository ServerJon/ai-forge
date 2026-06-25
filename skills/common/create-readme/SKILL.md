---
# Adapted from github/awesome-copilot
# Original: https://github.com/github/awesome-copilot
# License: MIT — Copyright GitHub, Inc.
name: create-readme
description: >-
  Creates comprehensive, well-structured README.md files for repositories by analyzing
  the full project workspace. Use when the user asks to create, generate, write, or
  update a README, document a project for new developers, or improve repository
  documentation.
---

# Create README

## Role

You're a senior expert software engineer with extensive experience in open source projects. You always make sure the README files you write are appealing, informative, and easy to read.

## When to Use

Use this skill when the request involves:

- Creating a new `README.md` for a project
- Rewriting or improving an existing README
- Documenting a repository for new developers or users
- Any phrasing like "write a readme", "generate documentation", or "document this project"

## Workflow

Follow these steps **in order**:

### Step 1 — Discover

Review the **entire project and workspace** before writing. Gather information from:

| Source         | What to extract                                                                                                                |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Root manifests | `package.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`, `pom.xml`, etc. — name, description, scripts, dependencies, versions |
| Existing docs  | `README.md`, `AGENTS.md`, `docs/`, wiki links                                                                                  |
| Source layout  | Folder structure, entry points, config files                                                                                   |
| CI/CD          | `.github/workflows/`, build badges, test commands                                                                              |
| Logo / icon    | `assets/`, `docs/images/`, root — `logo.svg`, `icon.png`, etc.                                                                 |

If present, also scan project-specific AI documentation:

- `.github/copilot/` — Architecture, Technology_Stack, Project_Folder_Structure, Workflow_Analysis, Coding_Standards, Unit_Tests, Code_Exemplars
- `.github/copilot-instructions.md`

### Step 2 — Analyze

Synthesize what a new developer or user needs to know:

- **What** the project does and who it's for
- **How** to install, configure, and run it
- **Why** it exists (problem solved, key differentiators)
- **Where** things live in the codebase (only if non-trivial)

Skip sections that don't apply. A CLI tool needs usage examples; a library needs import snippets; an internal toolkit may need less ceremony.

### Step 3 — Write

Create `README.md` following the structure and style rules below. Write to the project root unless the user specifies another path.

## README Structure

Adapt sections to the project. Include only what adds value — do not pad with boilerplate.

### Header

```markdown
<!-- If a logo exists, center it above the title -->
<p align="center">
  <img src="./path/to/logo.svg" alt="Project name" width="120" />
</p>

# Project Name

[![Build Status](...)](...) <!-- only when CI info is available -->
[![License](...)](LICENSE) <!-- badge OK; do not add a License section -->

> One-line description of what the project does.

[Overview](#overview) • [Getting started](#getting-started) • [Usage](#usage) • [Resources](#resources)

<!-- Optional demo GIF/screenshot when available -->
```

### Recommended sections (pick what fits)

| Section                   | Include when                                           |
| ------------------------- | ------------------------------------------------------ |
| **Overview**              | Always — 1–3 paragraphs explaining purpose and context |
| **Features**              | Project has distinct capabilities worth highlighting   |
| **Getting started**       | Prerequisites, installation, first-time setup          |
| **Usage**                 | Runnable examples, CLI commands, API snippets          |
| **Project structure**     | Non-obvious folder layout worth documenting            |
| **Architecture**          | Multi-component or layered design                      |
| **Configuration**         | Environment variables, config files                    |
| **Development**           | Local dev workflow, branching, coding conventions      |
| **Testing**               | Test commands and approach                             |
| **Troubleshooting / FAQ** | Known issues or common questions                       |
| **Resources**             | Links to docs, tutorials, related projects             |

### Do NOT include

These belong in dedicated files — never add these as README sections:

- LICENSE
- CONTRIBUTING
- CHANGELOG

A license **badge** in the header linking to `LICENSE` is fine.

## Style Guide

Take inspiration from the structure, tone, and content of these READMEs:

- https://github.com/Azure-Samples/serverless-chat-langchainjs
- https://github.com/Azure-Samples/serverless-recipes-javascript
- https://github.com/sinedied/run-on-output
- https://github.com/sinedied/smoke

### Formatting

- Use **GFM** (GitHub Flavored Markdown) — tables, fenced code blocks, task lists
- Use **GitHub admonition syntax** where it helps scanability:

```markdown
> [!TIP]
> Helpful shortcut or recommended path.

> [!NOTE]
> Additional context the reader should know.

> [!IMPORTANT]
> Critical prerequisite or warning.
```

### Tone and length

- Concise and to the point — every sentence should earn its place
- Developer-focused: show commands and code, not prose about commands
- Do **not** overuse emojis — one in the title is fine for small tools; skip them for enterprise samples
- Use badges (build status, version, runtime) only when accurate information is available
- Add quick-nav links (`[Overview](#overview) • ...`) for READMEs with 4+ sections
- Link to deeper docs (`docs/`, wiki) instead of duplicating content

### Code blocks

Match the project's primary language. Include copy-pasteable commands:

```bash
npm install
npm start
```

## Quality Checklist

Before finishing, verify:

- [ ] Title and description accurately reflect the project
- [ ] A new user can install and run from README instructions alone
- [ ] All commands were sourced from actual project files (not invented)
- [ ] No LICENSE / CONTRIBUTING / CHANGELOG sections
- [ ] Logo used in header if one exists in the repo
- [ ] Admonitions used sparingly and only where they add clarity
- [ ] Links and badge URLs are valid paths in this repository
