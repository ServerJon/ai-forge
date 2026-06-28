# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## How to Use This Guide

- Start here for cross-project norms.
- Each component/folder can have an `AGENTS.md` file with specific guidelines (e.g., `athletics-tech-api/AGENTS.md`, `functions/AGENTS.md`).
- Component/folder docs override this file when guidance conflicts.

## Repository Layout (relevant for tooling)

- `.agents/` — source-of-truth for skills and project subagents. `.agents/skills/<name>/SKILL.md` and `.agents/agents/<name>.md`.
- `.<claude|gemini|cursor>/` — read by specific agent. For example, if you use Claude Code: `.claude/skills` and `.claude/agents` are **symlinks** from `.agents/`. Editing a file under either path edits the same inode; git tracks only `.agents/`.

## External Dependencies

Tools an agent (or a developer pairing with one) needs on the machine to use the workflows below. Verify with the listed check; install only what's missing.

### Runtime baseline

TODO: create a table to show the Runtime baseline dependencies like the next example, the example is for a based node project, but could be other type of project like a `python` one.

```markdown
**example table**

| Tool    | Why                                                   | Check / install                                  |
| ------- | ----------------------------------------------------- | ------------------------------------------------ |
| Node.js | Runtime for the repo + all CLIs (current: 22.21)      | `node -v` · install via `nvm install 22`         |
| pnpm 9  | Package manager; runs `eslint`/`jest` via `pnpm exec` | `pnpm -v` · `corepack enable` or `npm i -g pnpm` |
| `npx`   | Runs `ctx7` / `mcp-remote` on demand                  | ships with Node                                  |

Run `pnpm install` first — ESLint, Prettier, Stylelint, Jest, and TypeScript come from the workspace dev-dependencies (the lint-format hook calls `pnpm exec eslint`).
```

### AI documentation & automation CLIs

TODO: create a table to show the AI documentation (skills, agents, command, etc...) dependencies like the next example.

```markdown
**example table**

| Tool             | Why / used by                                                                                | Check / install                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `ctx7`           | Up-to-date library docs ([`context7-cli`](.agents/skills/context7-cli/SKILL.md))             | `ctx7 --version` · `npm i -g ctx7` (or `npx ctx7@latest`); optional `ctx7 login` / `CONTEXT7_API_KEY` |
| `glab`           | All GitLab operations ([`glab`](.agents/skills/glab/SKILL.md))                               | `glab --version` · `brew install glab`, then `glab auth login`                                        |
| `playwright-cli` | Agent-driven browser automation ([`playwright-cli`](.agents/skills/playwright-cli/SKILL.md)) | `playwright-cli --version` · `npm i -g @playwright/cli`, then `playwright-cli install` for browsers   |
| `gh`             | All Github operations ([`gh`](.agents/skills/glab/SKILL.md))                                 | `glab --version` · `brew install glab`, then `glab auth login`                                        |
```

### Hook & MCP dependencies

TODO: create a table to show the hook & MCP dependencies like the next example.

```markdown
**example table**

| Tool             | Why / used by                                                                   | Check / install                                       |
| ---------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `jq`             | Parses hook payloads in `devtools/hooks/lint-format.sh`                         | `jq --version` · `brew install jq`                    |
| Atlassian plugin | Jira/Confluence MCP + skills on **Cursor** (`plugin-atlassian-atlassian`)       | Install from Cursor → plugins; authorize on first use |
| `mcp-remote`     | **Claude-only** fallback transport for the Atlassian MCP (see `sync-ai` Step 6) | `npx -y mcp-remote@latest <url>` (no install needed)  |
```

## AI Assistant Guidelines

TODO: review each section and remove the section that has no the skill and the dependency installed. For example, check the `Context7 CLI`, if the `.agents/skills/context7-cli` is not added and we have no installed dependency (`ctx7` or the `context7 MCP`) we will remove that section. The same for the rest.

**Context7 CLI (`ctx7`)**: Always use the `ctx7` CLI (via Bash) to fetch up-to-date library / framework / SDK documentation when working with:

- Code generation against external APIs (FastAPI, SQLAlchemy, Pydantic, Angular, Ionic, Nx, …)
- Setup or configuration steps for a library
- Migration questions between library versions
- Any "how does X work in library Y" question

Two-step pattern:

1. **Resolve the library ID**: `ctx7 library "<query>"` returns the canonical `/org/project` ID plus snippet counts and source reputation.
2. **Fetch focused docs**: `ctx7 docs /org/project "<specific question>"` returns the most relevant snippets. Library IDs always start with `/`. Use `--json` for structured output, or pipe to `head -N` to keep responses small.

```bash
ctx7 library "angular signals"
ctx7 docs /angular/angular "How to use signal-based inputs in standalone components"

ctx7 library "alembic migrations"
ctx7 docs /sqlalchemy/alembic "Adding a NOT NULL column with backfill on a populated table" --json
```

**Setup** (per machine, one-off): `npm install -g ctx7`, optionally `ctx7 login` for higher rate limits, or `export CONTEXT7_API_KEY=...` for non-interactive use. Anonymous use works at a lower rate limit.

**Fallback chain** (use the first option that is available, in order):

1. **`ctx7` CLI** (preferred): the two-step `library` → `docs` pattern above. Verify with `ctx7 --version`.
2. **Context7 MCP** (if the CLI is missing but the MCP server is installed): use the Context7 MCP tools (`mcp__*context7*__*`, e.g. `resolve-library-id` then `get-library-docs`). Same two-step flow — resolve the `/org/project` ID first, then fetch focused docs.
3. **`fetch` / WebFetch** (last resort, if neither the CLI nor the MCP is available): fetch the library's official documentation directly. Prefer canonical sources (official docs site, GitHub repo) and pin to the relevant version when the API is version-sensitive.

**Best practices**:

- Phrase queries as full sentences ("How to clean up `useEffect` with async operations") rather than keywords ("useEffect cleanup"). The retrieval is dramatically better.
- Always prefer `ctx7` (or the Context7 MCP) over WebFetch / WebSearch for library docs; only drop to a raw `fetch` when neither Context7 path is available.
- Library IDs are stable (`/facebook/react`, `/fastapi/fastapi`, `/sqlalchemy/alembic`) — once you have one, reuse it directly rather than re-resolving.

**GitHub CLI (`gh`)**: Always use the `gh` CLI (via Bash) for any GitHub remote operation:

- Creating or managing pull requests (`gh pr create`, `gh pr view`, `gh pr merge`, …)
- Creating or managing issues (`gh issue create`, `gh issue list`, …)
- Searching repositories, code, or users (`gh search`)
- Viewing repository information (`gh repo view`)
- Managing labels, milestones, or releases (`gh label`, `gh release`, …)
- Reading review comments and check statuses (`gh pr view --comments`, `gh pr checks`)
- Any operation that interacts with GitHub remote repositories

`gh` authenticates over HTTPS using a token stored by `gh auth login`, which sidesteps networks that block SSH (port 22) and avoids needing a personal access token in `git` config. Use local `git` commands for purely local operations: commits, status checks, diffs, local branch management, stashing, rebasing.

**Fallback**: if the `gh` command is not installed (verify with `gh --version`), use `git` directly. Local operations (commit, status, diff, branch, stash, rebase, push/pull) work natively with `git`. For remote-only features that `gh` would normally handle (PRs, issues, reviews, checks), `git` cannot replace them — push the branch with `git push -u origin <branch>` and tell the user to open/manage the PR or issue manually in the GitHub web UI, or to install `gh` (`brew install gh`, then `gh auth login`) to re-enable the automated flow.

Git workflow conventions are defined in the `git-workflow` skill (`.agents/skills/git-workflow/SKILL.md`), which AI Assistant follows automatically. Use `gh` for remote operations.

**GitLab CLI (`glab`)**: Always use the `glab` CLI (via Bash) for all GitLab operations, following the [`glab` skill](.agents/skills/glab/SKILL.md). Use it when working with:

- Merge requests (create, view, update, review comments)
- Issues (create, view, list, comment)
- CI/CD pipelines (status, logs, retries, job traces)
- Any other GitLab resource

`glab` is pre-configured in your environment. Prefer it over raw GitLab API calls; use `--output json` (pipe to `jq`) for machine-readable results.

```bash
glab mr create --push --title "feat: add OCL profile form" --description "$(cat /tmp/desc.md)"
glab mr view <iid>
glab ci status --output json
```

**Fallback**: if the `glab` command is not installed (verify with `glab --version`), use `git` directly. Local operations (commit, status, diff, branch, stash, rebase, push/pull) work natively with `git`. For remote-only features that `glab` would normally handle (MRs, issues, CI/CD pipelines, discussions), `git` cannot replace them — push the branch with `git push -u origin <branch>` and tell the user to open/manage the MR or issue manually in the GitLab web UI, or to install `glab` (`brew install glab`, then `glab auth login`) to re-enable the automated flow.

**Why CLI + skill**: the `glab` skill documents the project's MR/issue templates, comment/discussion subcommands, and reference syntax — read it before running multi-step GitLab workflows so output stays consistent and reproducible in PRs / commits.

**Playwright CLI (`playwright-cli`)**: Always use the `playwright-cli` (via Bash) for agent-driven browser automation, following the [`playwright-cli` skill](.agents/skills/playwright-cli/SKILL.md). Use it when working with:

- Browser automation and manual web UI flows
- Taking screenshots or accessibility snapshots of web pages
- Interacting with web forms and elements (`click`, `fill`, `type`, `select`)
- Debugging frontend behavior, console output, and network requests

Prefer the CLI over the Playwright MCP: the agent runs shell commands and the CLI streams concise, ref-based page snapshots into the Bash result (cheaper on context than MCP tool schemas), with skills loaded on demand and a persistent daemon (no per-command startup cost).

```bash
playwright-cli open http://localhost:<port>/telephony/security
playwright-cli snapshot
playwright-cli fill <ref> "Profile name"
playwright-cli click <ref>
playwright-cli screenshot
```

**Fallback**: if the `playwright-cli` command is not installed (verify with `playwright-cli --version`), use the Playwright MCP instead if it is available (`mcp__plugin_playwright_playwright__*` — `browser_navigate`, `browser_snapshot`, `browser_click`, `browser_fill_form`, etc.); it covers the same browser-automation flows at a higher context cost. If neither the CLI nor the MCP is available, tell the user to install one (`npm i -g @playwright/cli`, then `playwright-cli install` for browsers) to enable browser automation.

**Why CLI + skill**: read the `playwright-cli` skill for the full command reference (sessions, network mocking, storage, tracing) before multi-step browser workflows so interactions stay deterministic and reproducible.

## Project Subagents

There are project-level subagents live under `.agents/agents/`. Use them when their domain matches the request.

TODO: create a table to list the agents on the `.agents/agents/` folder like the following example:

```markdown
| Subagent                | Use for                                                                                                                                                                       |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `architecture-reviewer` | Verifying hexagonal-architecture import boundaries (`domain → application → infrastructure`). Run after large refactors or before merging API PRs that touch multiple layers. |
| `security-reviewer`     | High-confidence security audit on FastAPI / JWT / RBAC / SQLAlchemy / file-upload code paths. Use on PRs that change auth, query construction, or upload handling.            |
| `i18n-reviewer`         | Hardcoded user-facing strings, missing `$localize`, locale parity (`en.json` vs `es.json`), error-code translations, aria-label coverage. Use after frontend feature work.    |
```

Invoke via the `Agent` tool with `subagent_type: <name>`.

## Available Skills

Use these skills for detailed patterns on-demand:

TODO: create sub-section for this `Available Skills` section where: 1. `Generic skills` table to list the generic skills table on the `.skills/skills/` folder; 2. A sub-section for each scope that you find (front, api, for each app if it's a monorepo, etc); 3. Create a summary table with all the added skills on the sub-section `Auto-invoke skills`. You have the following example:

```markdown
### Generic Skills (Any Project)

| Skill             | Description                                                          | URL                                                 |
| ----------------- | -------------------------------------------------------------------- | --------------------------------------------------- |
| `git-workflow`    | Branch naming, commit format, PR conventions                         | [SKILL.md](.agents/skills/git-workflow/SKILL.md)    |
| `start-feature`   | Create feature branch from develop with sync                         | [SKILL.md](.agents/skills/start-feature/SKILL.md)   |
| `quality-check`   | Run full quality checks (format, lint, type-check, tests)            | [SKILL.md](.agents/skills/quality-check/SKILL.md)   |
| `setup-ci`        | Generate GitHub Actions CI/CD workflows                              | [SKILL.md](.agents/skills/setup-ci/SKILL.md)        |
| `sync-env`        | Compare .env and .env.example, report drift                          | [SKILL.md](.agents/skills/sync-env/SKILL.md)        |
| `api-gen-test`    | Generate unit and integration tests                                  | [SKILL.md](.agents/skills/api-gen-test/SKILL.md)    |
| `changelog`       | Maintain changelogs with keepachangelog.com format and emoji headers | [SKILL.md](.agents/skills/changelog/SKILL.md)       |
| `sync-agent-docs` | Keep CLAUDE.md and AGENTS.md files in sync with path translation     | [SKILL.md](.agents/skills/sync-agent-docs/SKILL.md) |

### API-Specific Skills (`athletics-tech-api`)

| Skill                  | Description                                       | URL                                                      |
| ---------------------- | ------------------------------------------------- | -------------------------------------------------------- |
| `api-architecture`     | Hexagonal architecture rules and layer boundaries | [SKILL.md](.agents/skills/api-architecture/SKILL.md)     |
| `api-domain-model`     | Domain entities, value objects, business rules    | [SKILL.md](.agents/skills/api-domain-model/SKILL.md)     |
| `api-database-schema`  | PostgreSQL tables, constraints, seed data         | [SKILL.md](.agents/skills/api-database-schema/SKILL.md)  |
| `api-testing`          | Testing conventions, patterns, coverage goals     | [SKILL.md](.agents/skills/api-testing/SKILL.md)          |
| `api-doc`              | Scan FastAPI routes and generate ENDPOINTS.md     | [SKILL.md](.agents/skills/api-doc/SKILL.md)              |
| `api-create-migration` | Create and review Alembic database migrations     | [SKILL.md](.agents/skills/api-create-migration/SKILL.md) |
| `api-new-entity`       | Scaffold entity across all hexagonal layers       | [SKILL.md](.agents/skills/api-new-entity/SKILL.md)       |
| `error-codes`          | API error codes registry and handling conventions | [SKILL.md](.agents/skills/error-codes/SKILL.md)          |

### Web-Specific Skills (`athletics-tech-web`)

| Skill               | Description                                                           | URL                                                   |
| ------------------- | --------------------------------------------------------------------- | ----------------------------------------------------- |
| `web-ui-patterns`   | UI components, page patterns, select rules, i18n                      | [SKILL.md](.agents/skills/web-ui-patterns/SKILL.md)   |
| `web-design-system` | Design tokens, styling, dark mode, accessibility                      | [SKILL.md](.agents/skills/web-design-system/SKILL.md) |
| `angular-component` | Angular 21 component patterns, signals, host bindings, OnPush         | [SKILL.md](.agents/skills/angular-component/SKILL.md) |
| `angular-testing`   | Vitest + TestBed testing patterns for Angular components and services | [SKILL.md](.agents/skills/angular-testing/SKILL.md)   |
| `playwright-e2e`    | Playwright E2E testing patterns, page objects, selectors              | [SKILL.md](.agents/skills/playwright-e2e/SKILL.md)    |

### Auto-invoke Skills

When performing these actions, ALWAYS invoke the corresponding skill FIRST:

| Action                                                                    | Skill                                  |
| ------------------------------------------------------------------------- | -------------------------------------- |
| Creating a new domain entity                                              | `api-new-entity`                       |
| Creating or modifying API endpoints                                       | `api-architecture`                     |
| Creating or modifying domain entities or business logic                   | `api-domain-model`                     |
| Creating or modifying SQLAlchemy models                                   | `api-database-schema`                  |
| Creating database migrations                                              | `api-create-migration`                 |
| Writing or modifying API tests                                            | `api-testing`, `api-gen-test`          |
| Writing or modifying frontend unit tests                                  | `angular-testing`                      |
| Writing or modifying E2E tests                                            | `playwright-e2e`                       |
| Adding new API error responses                                            | `error-codes`                          |
| Starting work on a new feature branch                                     | `git-workflow`, `start-feature`        |
| Creating a commit or pull request                                         | `git-workflow`, `changelog`            |
| Generating API documentation                                              | `api-doc`                              |
| Handling frontend error responses                                         | `error-codes`                          |
| Setting up CI/CD pipelines                                                | `setup-ci`                             |
| Checking .env file drift                                                  | `sync-env`                             |
| Running pre-PR quality checks                                             | `quality-check`                        |
| Creating or modifying pages or components in any `athletics-tech-web` app | `web-ui-patterns`, `angular-component` |
| Creating or modifying SCSS styles in any `athletics-tech-web` app         | `web-design-system`                    |
| Working with design tokens, colors, typography, or spacing                | `web-design-system`                    |
| Adding i18n to frontend components                                        | `web-ui-patterns`                      |
| Updating changelog entries                                                | `changelog`                            |
| Editing any CLAUDE.md or AGENTS.md file                                   | `sync-agent-docs`                      |
```

## MCP Server Tools Summary

TODO: review the MCP server tools on this section and remove the sections where we won't use the MCP, for example: if we have no PostgresSQL database for this project, we will remove the section `PostgresSQL MCP Integration`.

### Chrome DevTools (Advanced Browser Debugging & Performance)

Use Chrome DevTools MCP tools when working with:

- Deep browser debugging and DevTools inspection
- Performance profiling and trace analysis
- Console message debugging and error tracking
- Network request monitoring and analysis
- DOM interaction with Chrome-specific features
- Web vitals and performance insights (LCP, CLS, FID)
- Emulating different network conditions or device capabilities

This means you should automatically use Chrome DevTools MCP tools (`mcp__chrome-devtools__*`) for advanced debugging, performance analysis, and Chrome-specific browser automation tasks. Use this over Playwright when you need DevTools-specific features like performance tracing, Lighthouse audits, heap snapshots, or detailed console/network inspection (e.g. `performance_start_trace`, `lighthouse_audit`, `take_heapsnapshot`).

**Prefix**: `mcp__chrome-devtools__*`
**Key capabilities**:

- Navigation: `navigate_page`, `new_page`, `select_page`, `close_page`, `list_pages`
- Interaction: `click`, `fill`, `fill_form`, `hover`, `drag`, `press_key`, `upload_file`
- Inspection: `take_snapshot`, `take_screenshot`, `list_console_messages`, `get_console_message`
- Network: `list_network_requests`, `get_network_request`
- Performance: `performance_start_trace`, `performance_stop_trace`, `performance_analyze_insight`
- Advanced: `evaluate_script`, `emulate`, `resize_page`, `handle_dialog`, `wait_for`

**Example workflow (Performance Analysis)**:

1. User: "Analyze the performance of my web app"
2. Use: `navigate_page(url: "http://localhost:4200", type: "url")`
3. Use: `performance_start_trace(reload: true, autoStop: true)`
4. Use: `performance_analyze_insight(insightSetId: "...", insightName: "LCPBreakdown")`

**Example workflow (Debug Console Errors)**:

1. User: "Check what console errors are happening"
2. Use: `navigate_page(url: "http://localhost:4200", type: "url")`
3. Use: `list_console_messages(types: ["error", "warn"])`
4. Use: `get_console_message(msgid: 123)` for detailed error info

**When to use over Playwright**:

- Need performance tracing and Core Web Vitals analysis
- Debugging specific console errors or warnings
- Analyzing network requests with detailed timing information
- Emulating network conditions (Slow 3G, 4G, etc.) or CPU throttling
- Chrome DevTools-specific features

### PostgreSQL (Direct Database Access)

**PostgreSQL MCP Integration**: Always use PostgreSQL MCP tools when working with:

- Inspecting database schema, tables, columns, and constraints
- Running read queries to understand current data state
- Debugging data issues or verifying migration results
- Exploring table relationships and foreign keys

This means you should automatically use PostgreSQL MCP tools (`mcp__postgres__*`) for direct database inspection and read queries without requiring explicit user requests. Use this for quick data checks instead of writing Python scripts or Docker exec commands. For write operations (INSERT, UPDATE, DELETE), prefer Alembic migrations or the application layer to maintain data integrity.

**Prefix**: `mcp__postgres__*`
**Primary tool**:

- `query`: Execute SQL queries directly against the AthleticsTech PostgreSQL database

**Connection**: `postgresql://athleticstech:changeme123@localhost:5432/athleticstech_db`

**Example workflow**:

1. User: "Check what roles exist in the database"
2. Use: `query(sql: "SELECT id, name, display_name, level FROM roles ORDER BY level")`

**Best practices**:

- Use for read queries (SELECT) and schema inspection
- Prefer Alembic migrations for schema changes (not raw DDL)
- Prefer application layer for data writes (not raw INSERT/UPDATE)
- Useful for debugging: verify migration results, check FK constraints, inspect data state

### Memory (Persistent Knowledge Graph)

**Memory MCP Integration**: Use Memory MCP tools when working with:

- Storing and retrieving entities and their relationships across conversations
- Building a persistent knowledge graph of project concepts, decisions, and patterns
- Tracking cross-session context that doesn't fit in CLAUDE.md or skills
- Remembering user preferences, project-specific terminology, or recurring patterns

This means you should automatically use Memory MCP tools (`mcp__memory__*`) for persistent context management. Use `create_entities` and `add_observations` to store important discoveries, and `search_nodes` or `read_graph` to recall them in future sessions.

**Prefix**: `mcp__memory__*`
**Key capabilities**:

- Entity management: `create_entities`, `delete_entities`
- Observations: `add_observations`, `delete_observations`
- Relations: `create_relations`, `delete_relations`
- Retrieval: `read_graph`, `search_nodes`, `open_nodes`

**Example workflow**:

1. User discusses a complex architectural decision
2. Use: `create_entities([{name: "RBAC Decision", entityType: "architecture_decision", observations: ["Chose role-based access with JWT", "Roles stored as entities not enums"]}])`
3. Later session: `search_nodes(query: "RBAC")` to recall the decision

### Docker (Container Management)

**Docker MCP Integration**: Use Docker MCP tools when working with:

- Managing Docker containers (start, stop, inspect, logs)
- Deploying or updating services via docker-compose
- Inspecting container health, resource usage, and networking
- Debugging containerized services (database, app, etc.)

This means you should automatically use Docker MCP tools (`mcp__docker__*`) for container management operations without requiring explicit user requests. Use this instead of raw `docker` CLI commands for better structured output and safer operations.

**Prefix**: `mcp__docker__*`
**Key capabilities**:

- Container operations: `create-container`, `list-containers`, `get-logs`
- Compose: `deploy-compose`

**Example workflow**:

1. User: "Check if the database container is running"
2. Use: `list-containers()` to see all containers and their status
3. Use: `get-logs(container_id: "athleticstech-db")` to inspect database logs

### Claude Context (Semantic Code Search)

**Claude Context MCP Integration**: Use Claude Context MCP tools when working with:

- Semantic code search across the monorepo (find code by meaning, not just text)
- Locating prior implementations of a concept when you don't know the exact identifiers
- Exploratory questions like "where do we handle X?" or "is there similar logic elsewhere?"
- Complementing Grep/Glob when pattern-based search is insufficient

This means you should automatically use Claude Context MCP tools (`mcp__claude-context__*`) for conceptual / natural-language code search. Use `index_codebase` once per codebase, then `search_code` for queries. For exact symbol or pattern lookups, continue to prefer Grep.

**Prefix**: `mcp__claude-context__*`
**Key capabilities**:

- Indexing: `index_codebase`, `get_indexing_status`, `clear_index`
- Search: `search_code` — natural-language semantic queries over the indexed code

**Backend**: Local Milvus (vector DB, via `docker-compose.tooling.yml`) + local Ollama embeddings (`nomic-embed-text`, 768-dim). Fully local, no API keys required. Server config lives in user-local `~/.claude.json` (scope `local`).

**Prerequisite**: Both Milvus and Ollama must be running before the MCP server can index or search:

```bash
docker-compose -f docker-compose.tooling.yml up -d   # Milvus stack
brew services start ollama                            # Ollama (one-time; auto-starts on login)
```

**New machine?** Follow the step-by-step setup in [`docs/CLAUDE_CONTEXT_SETUP.md`](./docs/CLAUDE_CONTEXT_SETUP.md).

**Example workflow**:

1. First-time setup (one per codebase): `index_codebase(path: "/Users/jonatanlucasmolina/Projects/AthleticsTech")`
2. Check progress: `get_indexing_status(path: "...")`
3. Search: `search_code(path: "...", query: "where do we validate JWT tokens?")`

**When to use over Grep**:

- Query is conceptual ("auth token refresh logic") rather than a known string
- You don't know the exact identifier / file name
- Exploring unfamiliar parts of the monorepo

**When Grep is still better**:

- Exact symbol, route path, or env var lookup
- You need every match, not the top-k most relevant
- A regex captures the intent precisely

**Re-indexing**: After large refactors, run `index_codebase` with `force: true` to rebuild. Incremental sync runs automatically every 5 minutes once the server is up.

### Playwright MCP (Browser Automation)

**Prefix**: `mcp__plugin_playwright_playwright__*`
**Key capabilities**:

- Navigation: `browser_navigate`, `browser_navigate_back`, `browser_tabs`
- Interaction: `browser_click`, `browser_type`, `browser_fill_form`
- Inspection: `browser_snapshot`, `browser_take_screenshot`, `browser_console_messages`
- Testing: `browser_evaluate`, `browser_wait_for`, `browser_network_requests`

**Example workflow**:

1. User: "Test the login form on localhost:4200"
2. Use: `browser_navigate(url: "http://localhost:4200")`
3. Use: `browser_snapshot()` to see the page
4. Use: `browser_fill_form(fields: [{name: "email", value: "test@example.com"}, ...])`
5. Use: `browser_click(element: "Submit button", ref: "...")`

### Astro Docs (Official Astro Documentation)

**Astro Docs MCP Integration**: Use Astro Docs MCP tools when working with:

- Any Astro framework questions, APIs, or configuration
- Looking up Astro components, directives, integrations, or adapters
- Verifying Astro syntax, lifecycle, or project structure conventions
- Checking migration guides or release-specific changes

**Prefix**: `mcp__astro-docs__*`
**Server**: HTTP at `https://mcp.docs.astro.build/mcp`
**Primary tools**:

- `search_astro_docs`: Search official Astro documentation by query

**Example workflow**:

1. User asks about Astro's View Transitions API
2. Search: `search_astro_docs(query: "view transitions")`
3. Use: returned documentation to answer or generate code

**When to use**:

- Before writing any Astro-specific code or configuration
- When uncertain about Astro API signatures, directives, or integration options
- Prefer this over fetching docs.astro.build directly — same content, no extra browser call

### Greptile (Code Review & Context Analysis)

**Prefix**: `mcp__plugin_greptile_greptile__*`
**Key capabilities**:

- PR analysis: `get_merge_request`, `list_merge_request_comments`
- Code reviews: `trigger_code_review`, `get_code_review`, `list_code_reviews`
- Custom context: `create_custom_context`, `search_custom_context`
- Comment search: `search_greptile_comments`

**Example workflow**:

1. User: "Check which review comments on PR #42 haven't been addressed"
2. Use: `get_merge_request(name, remote, defaultBranch, prNumber: 42)`
3. Use: `list_merge_request_comments(name, remote, defaultBranch, prNumber: 42, addressed: false)`

### Atlassian Rovo (Jira / Confluence)

**Prefix**: `mcp__atlassian__*`
**Transport**: remote HTTP server at `https://mcp.atlassian.com/v1/mcp/authv2` (browser-based OAuth 2.1 on first use — no secrets in config). The legacy `…/v1/sse` endpoint is unsupported after 30 Jun 2026.
**Config**:

- Cursor → install the first-party **Atlassian plugin** (registers as `plugin-atlassian-atlassian`; also ships Jira/Confluence skills). Authorize on first call.
- Claude → project-root `.mcp.json`, installed via `/sync-ai` Step 6 (not committed)

**Key capabilities**:

- Jira: search/JQL, view, create, and update issues; bulk-create from notes/specs
- Confluence: search, summarize, create, and link pages
- Cross-reference: link Jira issues to Confluence pages

**Example workflow**:

1. User: "Find the open bugs linked to the OCL profile epic"
2. Use the Jira search/JQL tool, then `view` for details
3. Optionally link results to a Confluence release page

**When to use**: pulling ticket/issue context, drafting or updating Jira issues from a
diff or spec, or syncing decisions to Confluence — instead of leaving the editor. Data
access always respects your existing Atlassian permissions.

## Enabled Plugins

TODO: add on this section a sub-section for each plugin that you are using and it's not a hook or MCP server. Here you have an example for a Claude Code plugin:

```markdown
### Pyright LSP (`pyright-lsp@claude-plugins-official`)

**Purpose**: Type-aware Python development via Pyright (Microsoft's static type checker, used as a language server). Replaces the older `python@claude-plugins-official` plugin.
**Use automatically for**:

- Type checking and inference across `athletics-tech-api/`
- SQLAlchemy 2.0 typed mappings (`Mapped[T]`, `mapped_column`)
- Pydantic v2 type-checked schemas
- FastAPI dependency-injection signatures
- Poetry dependencies and virtual environments
- Pytest fixtures with type hints
- Alembic migration workflows
```

## Tool Selection Strategy

TODO: for this section review the whole configuration to create this section. Here you have an example of content of this section, you must create a similar one after reviewing the rest of `TODO` tasks:

```markdown
**Prefer specialized tools over generic commands**:

- ✓ Use the `ctx7` CLI for library docs instead of WebFetch / WebSearch
- ✓ Use the `gh` CLI for PR/issue operations instead of crafting raw API calls
- ✓ Use Playwright for web testing instead of manual browser interaction
- ✓ Use Chrome DevTools for performance analysis, debugging, and DevTools-specific features
- ✓ Use PostgreSQL MCP for database queries instead of `docker exec psql` commands
- ✓ Use Docker MCP for container management instead of raw `docker` CLI commands
- ✓ Use Memory MCP for cross-session context instead of ad-hoc notes
- ✓ Use Claude Context for semantic / conceptual code search; use Grep/Glob for exact pattern matching

**Use local git for**:

- Commits, status checks, diffs
- Local branch operations
- Stashing, rebasing

**Use the `gh` CLI for**:

- Creating/managing PRs and issues
- Searching code/repos/users
- Remote branch operations
- Code reviews and check status

**Use Grep/Glob for code search**:

- Pattern matching: `@router\.(get|post|put)` finds all route decorators
- File searches: `**/*.py` finds all Python files
- Text search: Find imports, function definitions, class declarations
- Fast and reliable for codebases under 10,000 files
- No indexing required, works immediately

**Use Task/Explore agents for**:

- Comprehensive codebase exploration
- Understanding architecture and patterns
- Multi-step code analysis workflows
- When you need context beyond simple pattern matching
```

## Project Overview

For a complete main README with project overview, architecture, development instructions, and documentation links, see [README.md](./README.md).
