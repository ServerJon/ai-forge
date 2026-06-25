# autoskills — Reference Summary

> **Source:** [github.com/midudev/autoskills](https://github.com/midudev/autoskills) · [autoskills.sh](https://autoskills.sh)
> **License:** CC BY-NC 4.0 — midudev · **Node.js >= 22 required**

---

## What it is

A CLI tool that scans your project's tech stack and auto-installs curated AI agent skill files (SKILL.md / AGENTS.md style) into your local repository. Think of it as a package manager for AI prompts/skills.

```bash
npx autoskills          # interactive install
npx autoskills -y       # skip confirmation
npx autoskills --dry-run  # preview without writing
```

---

## How it works

1. **Detect** — scans `package.json`, Gradle files, and config files to identify the tech stack.
2. **Match** — selects the best skills from the audited registry for the detected technologies.
3. **Verify** — downloads only matched skill files; every file is checked against a SHA-256 manifest.
4. **Write** — installs skill files locally and records a `skills-lock.json` entry (source + bundle hash).

No config needed. The registry is maintained by project maintainers — skills are never pulled live from arbitrary third-party repos.

---

## Security model

- Skills are **pre-audited** by maintainers for prompt-injection and supply-chain risks before entering the registry.
- Each file is recorded with a **SHA-256 hash** in a manifest — tamper-evident installs.
- `skills-lock.json` tracks installed source + bundle hash (analogous to `package-lock.json`).
- Does **not** fetch from random upstream repos at runtime.

---

## Supported tech stack (as of Jun 2026)

| Category | Technologies |
|---|---|
| Frameworks & UI | React, Next.js, Vue, Nuxt, Svelte, Angular, Astro, Tailwind CSS, shadcn/ui, GSAP, Three.js |
| Languages & Runtimes | TypeScript, Node.js, Go, Bun, Deno, Dart |
| Backend & APIs | Express, Hono, NestJS, Spring Boot |
| Mobile & Desktop | Expo, React Native, Flutter, SwiftUI, Android, KMP, Tauri, Electron |
| Data & Storage | Supabase, Neon, Prisma, Drizzle ORM, Zod, React Hook Form |
| Auth & Billing | Better Auth, Clerk, Stripe |
| Testing | Vitest, Playwright |
| Cloud & Infra | Vercel, Vercel AI SDK, Cloudflare (Workers/DO/AI), AWS, Azure, Terraform |
| Tooling | Turborepo, Vite, oxlint |
| Media & AI | Remotion, ElevenLabs |

---

## Relationship to ai-forge

| Concern | ai-forge | autoskills |
|---|---|---|
| Skill authoring | ✅ Manual, project-specific SKILL.md files | ❌ Managed by registry maintainers |
| Skill discovery | Manual | ✅ Auto-detected from project config |
| Install workflow | `install.sh` symlinks / copies | `npx autoskills` one-liner |
| Verification | None (trust git) | ✅ SHA-256 manifest lock |
| Custom/private skills | ✅ Full control | ❌ Registry-only |
| Agent-agnostic output | ✅ (Cursor, Claude, etc.) | ✅ |

**Recommended workflow:** use `autoskills` to bootstrap common tech-stack skills into a project, then layer ai-forge's project-specific skills (hexagonal-architecture, custom agents, etc.) on top.

---

## Gaps / skills autoskills does NOT currently cover

Based on the ai-forge skill inventory, the following have **no autoskills equivalent** and should continue to be maintained here:

- Hexagonal architecture patterns (entities, Alembic migrations, error codes, endpoint docs)
- Python/pytest conventions
- GitLab (`glab`) workflow
- SQL review & optimization
- `context7` CLI integration
- MR/PR creation workflow
- AI doc sync (`sync-ai`, `sync-ai-doc`)
- Chrome DevTools debugging

---

## Usage notes for this project

1. Run `npx autoskills --dry-run` first in any client project to preview what would be installed.
2. Skills installed by autoskills land in `.cursor/skills/` or `.claude/skills/` depending on the agent — **do not conflict** with ai-forge's `skills/` directory.
3. After an autoskills run, cross-check `skills-lock.json` to audit what was installed and at what hash.
4. For projects using React, TypeScript, Astro, Playwright, or Vitest — autoskills will likely cover the same ground as ai-forge's built-in skills; prefer autoskills there to avoid duplication.
