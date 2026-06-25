---
name: create-mr-pr
description: >-
  Creates a GitLab Merge Request or GitHub Pull Request from the current branch with a
  complete, auto-generated description of everything the change does, a validation/review
  checklist for the reviewer, and — for frontend apps — per-environment preview links left
  with empty URLs for the author to fill in. Use when the user says to open/create an MR or
  PR, "raise a merge request", "submit a pull request", or asks to ship the current branch
  for review.
user-invocable: false
---

# Create MR / PR

Open a Merge Request (GitLab) or Pull Request (GitHub) for the **current branch** with a
description that fully captures the work, validation steps a reviewer can follow, and
placeholder environment links when the change touches a frontend app.

This skill **creates**; the `mr-pr-reviewer` agent **reviews**. They are complementary.

## When to Use

- "Create an MR" / "Open a PR" / "Raise a merge request" / "Submit this for review"
- Any request to publish the current branch's work for review.

## Conventions & mechanics (delegate, don't duplicate)

- Branching, commit format, PR target branch, and the base body template come from the
  **`git-workflow`** skill — follow it. PRs/MRs target `dev` unless it's a hotfix to `main`.
- GitLab CLI mechanics (heredoc bodies, `--push`, common pitfalls) come from the **`glab`**
  skill. For GitHub, use the `gh` CLI equivalently.

## Phase 0 — Detect the platform

Decide GitLab vs GitHub before anything else:

```bash
git remote get-url origin
```

- Host contains `gitlab` → use **`glab`**.
- Host contains `github.com` → use **`gh`**.

Verify the CLI is authenticated; if not, stop and tell the user exactly what to run
(`glab auth login` / `gh auth login`). Never fall back to the other platform.

## Phase 1 — Gather everything the change does

Determine the base branch (default `dev` per `git-workflow`; confirm with the user if the
branch was cut from `main`), then collect the full picture so the description is complete —
not just the latest commit.

```bash
git rev-parse --abbrev-ref HEAD                 # current (source) branch
git log --oneline <base>..HEAD                  # every commit in this branch
git diff --stat <base>...HEAD                   # files touched + churn
git diff <base>...HEAD                          # full diff for an accurate summary
```

Read the diff to understand intent. Group the work into themes (features, fixes, refactors,
tests, docs, chores) rather than parroting commit messages one-for-one.

## Phase 2 — Push the branch

The remote branch must exist before the MR/PR is created.

```bash
git push -u origin HEAD
```

## Phase 3 — Detect whether a frontend is involved

If any changed path indicates a user-facing frontend, the description MUST include the
**Preview links** section (Phase 4 template). Heuristics — treat as frontend if the diff
touches any of:

- Frontend dirs: `web/`, `frontend/`, `app/`, `src/` of a web package, `*-web/`
- Framework files: `*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.astro`, `angular.json`,
  `next.config.*`, `vite.config.*`, component/style files (`*.css`, `*.scss`)
- A `package.json` declaring a web framework (react, vue, angular, svelte, next, astro, etc.)

When unsure, ask the user whether this change has a viewable frontend. If it's a pure
backend/API/lib change, omit the Preview links section.

## Phase 4 — Build the description

Write the body to a temp file, then pass it to the CLI (avoids shell-quoting issues — see
the `glab` skill). Use this template; **drop sections that don't apply** (don't pad):

```markdown
## Description

<2–4 sentences: what this change delivers and why, in plain language>

## Changes

- <grouped, human-readable summary of everything done — one bullet per meaningful change>
- <reference modules/areas affected, e.g. `auth`, `judge-admin`, `web/dashboard`>

## Validation steps

Steps a reviewer can follow to verify the change end to end:

1. <setup / branch checkout / install / migrations if any>
2. <action to perform>
3. <expected result>

- [ ] <key behaviour 1 to confirm>
- [ ] <key behaviour 2 to confirm>
- [ ] <edge case / error path to confirm>

## Preview links

> Frontend only. URLs are intentionally empty — fill in the correct one per environment.

- [Local]()
- [Dev]()
- [Staging]()
- [Production]()

## Testing

- [ ] Unit tests added/updated
- [ ] Integration tests added/updated
- [ ] All tests passing
- [ ] Manual testing completed

## Related issues

Closes #NNN <!-- omit if none -->

## Checklist

- [ ] Code follows project style
- [ ] Tests pass
- [ ] Documentation updated
- [ ] No breaking changes (or documented)
```

Rules for the body:

- **Description / Changes** are derived from the actual commits + diff (Phase 1), never
  invented. Be specific and complete — this is the "everything we have done" the user wants.
- **Validation steps** are concrete and runnable: a reviewer should reproduce the result
  without guessing. Include data setup, migrations, or env vars when the diff implies them.
- **Preview links** use **empty `()` targets** so the user pastes the per-environment URL.
  Include the rows that match the project's real environments; default to
  Local/Dev/Staging/Production and let the user trim.
- The MR/PR **title** follows conventional-commit format (`type(scope): description`) per
  `git-workflow`.

## Phase 5 — Create the MR/PR

### GitLab

```bash
glab mr create \
  --source-branch "$(git rev-parse --abbrev-ref HEAD)" \
  --target-branch dev \
  --title "feat(scope): concise summary" \
  --description "$(cat /tmp/mr-body.md)" \
  --remove-source-branch
```

(If the branch wasn't pushed in Phase 2, add `--push`. See the `glab` skill for pitfalls —
e.g. `--description`, not `--body`.)

### GitHub

```bash
gh pr create \
  --base dev \
  --title "feat(scope): concise summary" \
  --body-file /tmp/mr-body.md
```

Use `--draft` if the user asks for a draft. Never auto-merge.

## Phase 6 — Report back

After creation, report:

- Platform, source → target branch, and the MR/PR **URL**.
- The final title.
- A one-line confirmation that Validation steps were included, and whether Preview links
  were added (and that their URLs are empty, awaiting the user).

## Guardrails

- Do not create the MR/PR if there are uncommitted changes the user expects included —
  warn and confirm first.
- Never invent issue numbers, test results, or links. Leave preview URLs empty by design.
- Never force-push to `main`/`dev`; never auto-merge or auto-approve.
- Confirm the target branch when the source branch was cut from `main` (hotfix → `main`).

## Examples

### Frontend feature on GitLab

> User: "Open an MR for this branch."
> → Detect GitLab, base `dev`, summarize commits/diff, detect `web/` changes, include
> Preview links with empty URLs, push, `glab mr create`, return the MR URL.

### Backend-only fix on GitHub

> User: "Create a PR."
> → Detect GitHub, summarize the fix and its validation steps, **omit** Preview links
> (no frontend touched), `gh pr create --body-file`, return the PR URL.
