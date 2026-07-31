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

| Tool              | Why                                        | Check / install                                                         |
| ----------------- | ------------------------------------------ | ----------------------------------------------------------------------- |
| Bash ≥ 3.2        | Runs `install.sh` on Linux/macOS           | preinstalled — on Windows use [`install.ps1`](#windows)                 |
| Node.js ≥ 22.20   | Runs `npx`-based tools                     | `node -v` · `nvm install 22`                                            |
| `jq` (optional)   | Merges MCP configs when layering `--extra` | `brew install jq` · `apt install jq`                                    |
| `ctx7` (optional) | Up-to-date library docs inside the agent   | `npx ctx7@latest --version`                                             |
| `glab` (optional) | GitLab operations skill                    | `brew install glab && glab auth login`                                  |
| `gh` (optional)   | GitHub operations skill                    | `brew install gh && gh auth login`                                      |

Linux and macOS run `install.sh`; Windows runs `install.ps1` natively (WSL 2 and
Git Bash also work — see [Windows](#windows)).

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

| Flag                | Effect                                                                             |
| ------------------- | ---------------------------------------------------------------------------------- |
| `-p <path>`         | Target project path (skips the interactive prompt)                                 |
| `-e`, `--extra <p>` | Layer another project on top (see [below](#layering-another-project-on-top---extra)) |
| `-a`, `--list-all`  | Non-interactive: select **all** available skills/agents (no TTY/menu needed)       |
| `-y`, `--yes`       | Assume "yes" for confirmation prompts                                              |
| `-n`, `--dry-run`   | Preview what would be installed without writing anything                           |
| `-h`, `--help`      | Show usage                                                                          |

> [!TIP]
> Run `npx autoskills --dry-run` in your project first to cover common framework skills, then use `install.sh` to layer on the ai-forge extras that autoskills doesn't provide.

### Windows

Windows has a native installer, `install.ps1`, so no Bash environment is
required:

```powershell
# Windows PowerShell 5.1 or PowerShell 7+
.\install.ps1 -Path C:\src\my-project
```

It is a port of `install.sh`, not a wrapper: same checkbox menu, same
dependency tables, same `.agents/` payload, same `manifest.json`. It also
accepts Git Bash (`/c/src/app`) and WSL (`/mnt/c/src/app`) path spellings, and
merges MCP configs with the built-in JSON parser so **jq is not needed** on
Windows. A CI job installs with both scripts and diffs the result, so the two
stay in step — see [Installer parity](#installer-parity).

| Bash flag        | PowerShell parameter |
| ---------------- | -------------------- |
| `-p <path>`      | `-Path <path>`       |
| `-e <path>`      | `-Extra <path>`      |
| `-a`             | `-ListAll`           |
| `-y`             | `-Yes`               |
| `-n`             | `-DryRun`            |
| (n/a)            | `-NoColor`           |

The short aliases work too (`.\install.ps1 -p C:\src\app -a -y`), and
`Get-Help .\install.ps1 -Full` prints the usage.

> [!NOTE]
> If PowerShell refuses to run the script, unblock it for the current session:
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`.

#### Windows with WSL 2 or Git Bash

Prefer WSL 2 if you already use it: the shell hooks some skills install (for
example `sync-ai`'s `.agents/hooks/lint-format.sh`) need a POSIX shell at
runtime, whatever installed them.

```bash
wsl --install -d Ubuntu          # PowerShell, once
# then, inside the Ubuntu shell:
git clone https://github.com/your-org/ai-forge && cd ai-forge
./install.sh -p /path/to/your-project
```

> [!TIP]
> Keep both the repo and the target project inside the Linux filesystem
> (`~/projects/...`). Working across `/mnt/c/...` is slow and loses the execute
> bit on installed hook scripts.

**Git Bash** (bundled with [Git for Windows](https://gitforwindows.org)) also
works if you would rather run the Bash installer. Mind these four points:

1. **Line endings.** The repository's `.gitattributes` pins `*.sh` to LF, so a
   fresh clone is safe even with `core.autocrlf=true`. An older clone may still
   hold CRLF copies, which make Bash fail with
   `bad interpreter: /usr/bin/env bash^M`; renormalise it once:

   ```bash
   git rm --cached -r . && git reset --hard
   ```

2. **No execute bit.** NTFS does not carry it, so invoke the interpreter
   explicitly instead of `./install.sh`:

   ```bash
   bash install.sh -p /c/Users/you/projects/your-project
   ```

3. **Paths must be POSIX-style.** Use `/c/Users/...`, not `C:\Users\...` —
   backslashes are consumed as escape characters by the shell.
4. **Run it from Git Bash / Windows Terminal, not from `cmd.exe` or PowerShell.**
   The checkbox menu reads raw keystrokes and ANSI escape sequences, which is
   unreliable when `bash.exe` is launched from a non-MSYS console. If the arrow
   keys misbehave, skip the menu entirely with `--list-all -y` (see the
   [next section](#non-interactive-install---list-all)).

### Non-interactive install (`--list-all`)

`--list-all` skips the interactive menu and selects every available **local**
skill and agent — handy for scripted setups and CI (no TTY required). Remote
installs and helper commands (autoskills, MCP merge, recommendation scans) are
not auto-run; select those from the menu when you want them.

```bash
# Install every local skill and agent, unattended
./install.sh -p /path/to/project --list-all -y

# CI smoke test: verify the plan without writing anything
./install.sh -p /tmp/aiforge-ci --list-all --dry-run
```

```powershell
# The same two runs on Windows
.\install.ps1 -Path C:\src\my-project -ListAll -Yes
.\install.ps1 -Path $env:TEMP\aiforge-ci -ListAll -DryRun
```

### Installer parity

`install.sh` and `install.ps1` are two hand-maintained implementations of the
same behaviour, so **a change to one must be made in the other**. Two things
keep them honest:

```bash
# Install with both and diff the results (needs bash + pwsh + network)
./tests/parity/compare-installers.sh

# Unit tests for the PowerShell modules
pwsh -c "Invoke-Pester ./tests/powershell -Output Detailed"
```

The `installers` GitHub Actions workflow runs the Bash installer on Linux and
macOS (including under macOS's Bash 3.2 and through `sh`), the PowerShell
installer on Linux, macOS, Windows PowerShell 5.1 and PowerShell 7, plus
PSScriptAnalyzer, Pester and the parity diff.

### Install manifest

Every real install writes `<target>/.agents/manifest.json` recording what was
installed, from which **source** (`ai-forge` or an `--extra` layer), and the
upstream **commit** of each source. This makes later updates/uninstalls
deliberate rather than guesswork.

```json
{
  "schema": "ai-forge/install-manifest@1",
  "generatedAt": "2026-07-19T14:00:00Z",
  "target": "/path/to/project",
  "sources": [
    { "name": "ai-forge", "root": "…/ai-forge", "commit": "2da81ae…" }
  ],
  "skills": [ { "name": "gh", "source": "ai-forge", "path": ".agents/skills/gh" } ],
  "agents": [],
  "remoteSkills": [],
  "commands": []
}
```

### Post-install

After the installer completes, open your AI assistant and run:

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
├── install.sh                  # Interactive skill/agent installer (Linux/macOS)
├── install.ps1                 # Same installer, native to Windows PowerShell
│
├── scripts/powershell/         # Modules backing install.ps1 (console, catalog, menu, ...)
├── tests/powershell/           # Pester tests for those modules
├── tests/parity/               # Diffs a bash install against a PowerShell install
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

Skills that have special setup instructions include a `README.md` in their
folder (e.g. `skills/angular/`, `skills/hexagonal-architecture/`,
`skills/playwright/webapp-testing/`). A remote bundle also provides
`install.args`, with one executable or argument per line. The installer displays
that command, requires confirmation, and invokes it directly without evaluating
shell syntax.

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

## Layering another project on top (`--extra`)

You can reuse this installer as an **engine** for a downstream "layer" project — one
that adds its own skills/agents on top of ai-forge — without forking `install.sh`.
Pass the layer project's path with `--extra`:

```bash
./install.sh -p /path/to/target-project --extra /path/to/layer-project
```

When `--extra <path>` is given, the installer:

1. **Loads the layer's config file** — `<layer>/.ai-forge.env`, a shell snippet that
   sets any of the `AIFORGE_*` variables below (labels, superseded items, ...).
2. **Lists the layer's skills** from `<layer>/skills/` alongside ai-forge's.
3. **Lists the layer's agents** from `<layer>/agents/` alongside ai-forge's.
4. **Merges MCP configs** — `<layer>/assets/MCPs/mcp.json` is merged with ai-forge's
   into the target's `.agents/mcp/mcp.json` (deep-merge via `jq`; copy fallback).
5. **Hides superseded items** — any skill/agent named in `AIFORGE_HIDE_SKILLS` /
   `AIFORGE_HIDE_AGENTS` is dropped from ai-forge's own list (the layer's version
   wins). Layer items always appear first.

### `.ai-forge.env` — the layer config file

A plain shell snippet at the layer project's root. All variables are optional; unset
means stock behaviour. `$AIFORGE_EXTRA_ROOT` is set to the layer path before it loads,
so you can build paths from it.

| Variable                 | Effect                                                                                        |
| ------------------------ | --------------------------------------------------------------------------------------------- |
| `AIFORGE_SELF_LABEL`     | Label suffix next to items from ai-forge itself (e.g. `" (shared)"`).                         |
| `AIFORGE_EXTRA_LABEL`    | Label suffix next to items from the layer project.                                            |
| `AIFORGE_HIDE_SKILLS`    | Space-separated ai-forge skill names the layer supersedes (hidden from the menu).             |
| `AIFORGE_HIDE_AGENTS`    | Space-separated ai-forge agent names the layer supersedes.                                     |
| `AIFORGE_MCP_OVERLAY`    | Extra `mcp.json` file(s) to merge (defaults to `<layer>/assets/MCPs/mcp.json`).               |
| `AIFORGE_AGENTS_TEMPLATE`| Path to an `AGENTS.md` template overriding the bundled one.                                    |
| `AIFORGE_EXTRA_ROOTS`    | Extra source roots to scan (advanced; `--extra` adds the layer path automatically).           |

Example `.ai-forge.env`:

```bash
# ai-forge layer config
AIFORGE_SELF_LABEL=" (shared)"     # tag ai-forge's own items in the menu
AIFORGE_HIDE_SKILLS="git-workflow"  # this layer's gitlab-workflow supersedes it
```

> These variables can also be exported directly in the environment for advanced/CI
> use; `--extra` is just the convenient path-driven front-end that populates them.

---

## Resources

- [autoskills](https://github.com/midudev/autoskills) — auto-install community skills from a curated registry
- [awesome-copilot](https://github.com/github/awesome-copilot) — GitHub's curated collection of Copilot instructions, prompts, and chat modes
- [AUTO-SKILLS.md](./AUTO-SKILLS.md) — how ai-forge and autoskills relate, gap analysis
- [AGENTS.template.md](./AGENTS.template.md) — full project AGENTS.md template with all sections
