---
name: gh
description: >
  GitHub CLI (gh) for managing GitHub resources from the command line.
  Use this skill when you need to work with pull requests, issues, GitHub
  Actions workflows, releases, repositories, or any other GitHub resource.
  Prefer gh over raw API calls for all GitHub operations.
user-invocable: false
---

# GitHub CLI (gh)

`gh` is pre-configured and available in your environment. Use it for all
GitHub operations. Run `gh <command> --help` for detailed flag information.

## Quick reference

```shell
# Issues
gh issue view <number>
gh issue list --label "bug,help wanted" --state open
gh issue create --title "title" --body "$(cat /tmp/desc.md)"
gh issue comment <number> --body "comment text"

# Pull requests
gh pr create --title "fix: title" --body "$(cat /tmp/desc.md)" --base main
gh pr view <number>
gh pr list --assignee "@me"
gh pr edit <number> --body "$(cat /tmp/desc.md)"
gh pr review <number> --approve
gh pr merge <number> --squash --delete-branch

# GitHub Actions
gh workflow run triage.yml --ref main -f env=production
gh workflow list
gh run list --workflow triage.yml
gh run view <run-id>
gh run watch <run-id>

# Repositories
gh repo clone owner/repo
gh repo fork owner/repo --clone
gh repo create my-project --public --clone

# Machine-readable output
gh pr list --json number,title,state | jq '.[].title'
gh issue list --json number,title --jq '.[].number'
```

**Templates:** Check `.github/PULL_REQUEST_TEMPLATE.md` and
`.github/ISSUE_TEMPLATE/` for project-specific templates. Pass them with
`--template path/to/template.md`.

**References:** Link issues with `#123`, users with `@username`, cross-repo
with `owner/repo#123`.

## Comments and reviews

### Short, inline bodies — pass `--body`

```shell
gh issue comment <number> --body "comment text"
gh pr review <number> --comment --body "review comment"
```

### Long or Markdown bodies — pipe via `--body-file`

Use `--body-file -` to read from stdin, or `--body-file /tmp/body.md` for a
file. Avoids shell-quoting pitfalls with backticks, `$`, and backslashes.

```shell
# From a file
gh pr create --title "fix: title" --body-file /tmp/body.md

# Inline heredoc — safe for multi-line, no shell expansion inside quoted EOF
gh issue comment 42 --body-file - << 'EOF'
Your **markdown** comment.
Code blocks and `inline code`, $variables, and \backslashes are literal.
EOF
```

### PR review with inline comments

```shell
gh pr review <number> --request-changes --body "Needs work"
gh pr review <number> --approve
gh pr review <number> --comment --body "LGTM, minor nit below"
```

## API calls

`gh api` auto-resolves `{owner}` and `{repo}` placeholders from the current
repository context. Defaults to GET; switches to POST when parameters are
added.

```shell
gh api repos/{owner}/{repo}/releases
gh api repos/{owner}/{repo}/issues/123/comments -f body='Hi from CLI'
gh api -X PATCH repos/{owner}/{repo}/pulls/456 -f state=closed

# GraphQL
gh api graphql -f query='
  query {
    viewer { login }
  }
'

# Paginate REST
gh api repos/{owner}/{repo}/issues --paginate | jq '.[] | .title'

# Paginate GraphQL
gh api graphql --paginate -f query='
  query($endCursor: String) {
    repository(owner: "{owner}", name: "{repo}") {
      pullRequests(first: 100, after: $endCursor) {
        nodes { number title }
        pageInfo { hasNextPage endCursor }
      }
    }
  }
'
```

### Content-type guidance

```shell
# -f / --raw-field — literal string (always a string)
gh api repos/{owner}/{repo}/issues/1/comments -f body="comment"

# -F / --field — typed value (booleans, numbers, @file paths)
gh api gists -F 'files[myfile.txt][content]=@myfile.txt'

# --input — raw request body from file or stdin
gh api repos/{owner}/{repo}/rulesets --input ruleset.json
```

## GitHub Actions

```shell
# Trigger a workflow_dispatch event
gh workflow run deploy.yml --ref main -f environment=prod

# Follow a run in real time (blocks until complete)
gh run watch <run-id>

# Download artifacts from a run
gh run download <run-id> --name artifact-name

# Re-run failed jobs only
gh run rerun <run-id> --failed
```

## Releases

```shell
gh release create v1.2.3 --title "Release v1.2.3" --notes "$(cat CHANGELOG.md)"
gh release create v1.2.3 dist/*.tar.gz --generate-notes
gh release view v1.2.3
gh release list
gh release download v1.2.3 --pattern "*.tar.gz"
```

## Common mistakes

- **`--body` is required for non-interactive use** — without it, `gh issue
  create`, `gh pr create`, and `gh issue comment` open `$EDITOR`, which
  hangs in non-interactive environments. Always pass `--body` or
  `--body-file`.
- **`gh pr create` pushes the branch automatically** — unlike `glab mr
  create`, `gh pr create` will push the current branch if it's not already
  on the remote. Pass `--head` to skip forking/pushing behaviour.
- **Use `--json` + `--jq` for scripting, not `--output`** — `gh` doesn't
  have a `--output json` flag; use `--json <fields>` to select fields, then
  pipe to `jq` or use `--jq` inline.
- **`gh run watch` blocks** — it streams until the run finishes. For agents,
  poll with `gh run view <run-id> --json status,conclusion` instead.
- **`--paginate` returns a JSON array per page** — combine with `--slurp`
  on GraphQL or `jq -s 'add'` on REST to merge pages into one array.
- **No `--description` flag** — `--description` is a `glab` flag. `gh` uses
  `--body` for issue/PR body text.
- **`{owner}` and `{repo}` in `gh api`** — these are literal placeholders
  that `gh` resolves from the current git remote. They are NOT shell
  variables; do not quote or escape them.
- **Always use `--delete-branch` on merge** — `gh pr merge` does not delete
  the remote branch by default; pass `--delete-branch` to clean up.
