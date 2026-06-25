---
name: git-workflow
description: Git conventions and workflow rules
user-invocable: false
---

# Git Workflow Conventions

Claude MUST follow these conventions for all git operations in this repository.

## Branching Strategy

- **`main`** — Production-ready code (protected, never force push)
- **`dev`** — Development integration branch (base for all feature work)
- **`feature/*`** — New features (branch from `dev`)
- **`fix/*`** — Bug fixes (branch from `dev`, or `main` for hotfixes)
- **`docs/*`** — Documentation updates
- **`refactor/*`** — Code refactoring
- **`test/*`** — Test improvements

When creating branches, use kebab-case: `feature/judge-admin-rights`, `fix/email-validation`.

## Start Feature Branch

Automate the creation of a properly named feature branch from an up-to-date `dev`.

### Arguments

- `name` (required) — Short kebab-case description of the feature (e.g., `judge-filtering`, `event-registration`)
- `type` (optional) — Branch prefix type. Defaults to `feature`. Check the accepted values from the `Branching Strategy` section on this file

### Steps

1. **Check for uncommitted changes** — Run `git status`. If there are uncommitted changes, warn the user and ask whether to stash them before proceeding.

2. **Sync dev** — Switch to `dev` and pull latest:

   ```bash
   git checkout dev
   git pull origin dev
   ```

3. **Create the branch** — Using the correct prefix:

   ```bash
   git checkout -b <type>/<name>
   ```

   Example: `git checkout -b feature/judge-filtering`

4. **Confirm** — Print a summary:
   - Branch name created
   - Current base commit (short hash + message)
   - Reminder of the commit format: `type(scope): description`

## Commit Message Format

**Conventional Commits**: `type(scope): description`

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `style`

Scope should identify the module/area affected (e.g., `judge`, `api`, `admin`, `deps`).

## Pull Request Rules

- PRs target `dev` (unless hotfix targeting `main`)
- PR title follows conventional commit format
- Use this PR body template:

```markdown
## Description
Brief description of what this PR does.

## Changes
- [list of changes]

## Testing
- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] All tests passing
- [ ] Manual testing completed

## Related Issues
Closes #NNN

## Checklist
- [ ] Code follows project style
- [ ] Tests pass
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
```

## Pre-commit Checks

Before committing, run the appropriate checks:

- **API (athletics-tech-api/)**: `poetry run pre-commit run --all-files` then `poetry run pytest`
- **Web (athletics-tech-web/)**: `npm run lint && npm run format` then `npm test`

## Hotfix Process

For critical production bugs:

1. Branch from `main` (not `dev`)
2. Create `fix/<name>` branch
3. PR targets `main`
4. After merge to `main`, merge `main` back into `dev`

## Safety Rules

- NEVER force push to `main` or `dev`
- Use `--force-with-lease` (not `--force`) on feature branches when needed
- Keep branches updated by rebasing onto `dev` regularly nto `dev` regularly
