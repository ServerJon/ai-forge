# Contributing to ai-forge

Thanks for helping improve **ai-forge**! This repo is a curated library of
`SKILL.md` and agent definition files for AI coding assistants. Contributions —
new skills, new agents, fixes, and docs — are welcome.

---

## Contribution & review model

This is a **public** repository. To keep the library consistent and trustworthy,
merging is reserved for the maintainer.

- **You (contributors)** may **open Pull Requests**, but **cannot merge** them.
- **The maintainer** ([@ServerJon](https://github.com/ServerJon)) reviews every PR
  and merges it once it meets the rules below.

Because contributors work from **forks** (no write access to this repo), you
inherently cannot push to protected branches or merge PRs — you can only propose
changes. Please don't request write access; the fork + PR flow is the intended path.

### What "ready to merge" means

A PR is merged only when **all** of these hold:

1. It targets `main` and follows the structure/commit conventions below.
2. CI / basic checks pass (see [Testing](#testing-your-changes)).
3. The maintainer has reviewed and approved it.
4. Discussion threads are resolved and the branch is up to date with `main`.

---

## Ways to contribute

| Type          | Where it lives                             |
| ------------- | ------------------------------------------ |
| New skill     | `skills/<group>/<skill-name>/SKILL.md`     |
| New agent     | `agents/<group>/<agent-name>.md`           |
| Fix / improve | Existing skill, agent, or installer        |
| Docs          | `README.md`, this file, skill `README.md`s |

If unsure whether an idea fits, **open an issue first** to discuss it before
investing time in a PR.

---

## Local setup

```bash
# 1. Fork the repo on GitHub, then clone YOUR fork
git clone git@github.com:<your-username>/ai-forge.git
cd ai-forge

# 2. Add the upstream remote to keep your fork in sync
git remote add upstream https://github.com/ServerJon/ai-forge.git

# 3. Create a topic branch off an up-to-date main
git fetch upstream
git switch -c feat/my-change upstream/main
```

Keep your branch current before pushing:

```bash
git fetch upstream && git rebase upstream/main
```

---

## Branching & commit conventions

**Branch names:** `<type>/<short-summary>` — e.g. `feat/add-vue-skill`,
`fix/installer-tty-check`, `docs/clarify-mcp-merge`.

**Commits: [Conventional Commits](https://www.conventionalcommits.org/).**

```
type(scope): short imperative description
```

- Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `style`.
- Scope (optional): the area touched, e.g. `install`, `skills`, `agents`.
- Keep the subject ≤ 72 chars; add a body explaining the **why** when useful.

Examples:

```
feat(skills): add a Vue 3 composition-API testing skill
fix(install): handle project paths containing spaces
docs: document the --extra layering flow
```

---

## Adding a skill

1. Create `skills/<group>/<skill-name>/SKILL.md`.
2. Start with YAML frontmatter — at minimum `name` and `description`:

   ```markdown
   ---
   name: my-skill
   description: One-line, action-oriented summary the agent uses to decide when to apply this skill.
   ---

   ## When to use
   ...

   ## Steps
   ...
   ```

3. Write a clear `description` — the agent uses it to decide *when* to trigger the
   skill, so make it specific and outcome-oriented.
4. If the skill needs external tools, document them so the installer's dependency
   tables stay accurate.
5. Keep skills **generic and cross-project**. Company- or client-specific content
   belongs in a downstream layer, not here.

## Adding an agent

1. Create `agents/<group>/<agent-name>.md` (agents must live in a subfolder for the
   installer to discover them).
2. Follow the frontmatter convention (`name`, `description`) used by existing agents.
3. Reference existing skills rather than duplicating their content.

---

## Testing your changes

Before opening a PR:

```bash
# Installer must stay syntactically valid
bash -n install.sh

# Preview installation without writing anything
./install.sh -p /tmp/aiforge-test --dry-run
```

- New/edited skills and agents should appear correctly in the installer menu.
- Verify Markdown renders and frontmatter is valid YAML.

---

## Code style

- Respect [`.editorconfig`](.editorconfig) (indentation, final newline, charset).
- Match the tone and formatting of existing `SKILL.md` / agent files.
- Prefer clear, concise Markdown; avoid trailing whitespace.

---

## Pull request checklist

- [ ] Branch is based on an up-to-date `upstream/main`.
- [ ] Commits follow Conventional Commits.
- [ ] New skills/agents follow the folder layout and frontmatter convention.
- [ ] `bash -n install.sh` passes and `--dry-run` lists the change correctly.
- [ ] README / docs updated if behaviour or catalog changed.
- [ ] PR description explains the motivation and what you tested.

Open the PR against `main`. The maintainer will review, request changes if needed,
and merge once everything checks out. Thanks for contributing!

---

## License

ai-forge is licensed under **CC BY 4.0** (see [`LICENSE.md`](LICENSE.md)). By
submitting a contribution, you agree it is licensed under the same terms.
