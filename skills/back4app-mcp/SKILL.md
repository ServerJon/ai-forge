---
name: back4app-mcp
description: Operate the live Back4App (Parse Server) backend of the GastrOleum app through the Back4App MCP server — inspect real data and schema, run Parse REST operations, check ACLs/CLPs/roles, and deploy Cloud Code / web-hosting files. Use when you need to talk to the actual backend (query production/test data, verify a class schema, deploy a Cloud Function, debug a server-side behavior) rather than write local SDK code. For routine local code use the `angular-service` (frontend Parse SDK) and `cloud-code` (functions/) skills instead.
user-invocable: false
---

# Back4App MCP (`back4app` server)

The Back4App MCP server lets you operate the **live Back4App backend** that powers
GastrOleum (the same Parse Server the app and `functions/` Cloud Code run against). It is
the bridge between this environment and the real backend: querying actual data, reading
the deployed schema, and — unlike the local `cloud-code` skill — **deploying Cloud Code
without the dashboard**.

It complements, it does not replace, the local skills:

| Want to…                                            | Use                                    |
| --------------------------------------------------- | -------------------------------------- |
| Write frontend data-access code (Parse SDK, DTOs)   | `angular-service`                      |
| Write/edit Cloud Code in `functions/` locally       | `cloud-code`                           |
| Inspect/query the **live** data or schema           | **this skill** (`call_parse_server_rest_api`)      |
| **Deploy** Cloud Code / web hosting to the backend  | **this skill** (`deploy_*` tools)      |

## ⚠️ Safety — read before using

The MCP authenticates with a Back4App **account key**: a personal access token with
**full read / write / delete access to every app on the account**. It is configured in
`.agents/mcp/mcp.json` (the git-tracked source of truth, symlinked to repo-root
`.mcp.json`).

- **Prefer a test app.** Point destructive work at a non-production app first; the same
  token reaches production, so name the target app explicitly in every call.
- **Confirm destructive operations.** Deleting objects/classes, editing CLP/ACL, and
  `deploy_*` are irreversible against the live backend — confirm with the user first and
  never run them speculatively.
- **Never echo the key** into prompts, code, commits, or logs. If it leaks, rotate it
  (Dashboard → Account Keys → revoke + recreate). Because the key lives in git history,
  rotate it when a collaborator with repo access leaves.
- **`deploy_cloud_code_files` overrides the `cloud-code` skill's "deploy is manual via the
  dashboard" caveat.** You *can* deploy from here — which means you can also clobber the
  live backend. Treat a deploy as a production change: confirm, and tell the user it is
  now live.

## Setup

1. Back4App Dashboard → hover your username → **Account Keys** → create a key (e.g.
   `gastroleum-mcp`). The token is shown **once** — copy it immediately.
2. Paste it into `.agents/mcp/mcp.json`, replacing `__PASTE_BACK4APP_ACCOUNT_KEY_HERE__`.
3. Restart Claude Code, then verify with `claude mcp list` (the `back4app` server should
   connect) or call `get_parse_apps`.

```json
{
  "mcpServers": {
    "back4app": {
      "command": "npx",
      "args": ["-y", "@back4app/mcp-server-back4app", "--account-key", "<your key>"]
    }
  }
}
```

Requires Node.js (≥16) with a working `npx`.

## Tools

App management:

- `get_parse_apps` — list all Parse apps on the account.
- `get_parse_app` — details for one app.
- `create_parse_app` — create a new Parse app (rarely needed here).
- `set_current_app` / `get_current_app` — set/read the default app the other tools act on.
  **Set this first** so subsequent calls hit the GastrOleum app, not another one.

Backend operations:

- `call_parse_server_rest_api` — the workhorse: a thin wrapper over the **Parse REST API**. Use it for
  schema design, CRUD, rich queries (filter/sort/skip/limit/aggregate), users / roles /
  ACLs / CLPs, file storage, and invoking Cloud Functions. Reason in Parse REST terms
  (`GET /classes/<Class>`, `POST /functions/<name>`, `GET /schemas`, …).

Cloud Code & web hosting:

- `list_cloud_code_and_web_hosting_files` — list deployed files.
- `get_file_content` — read a deployed file's contents.
- `deploy_cloud_code_files` — deploy Cloud Code (mirrors `functions/`). **Destructive** —
  see safety rules.
- `deploy_web_hosting_files` — deploy static web-hosting bundle. **Destructive.**
- `activate_web_hosting` — enable web hosting for the app. **Destructive.**

## Typical flows

**Inspect live data / schema**

1. `set_current_app` → the GastrOleum app.
2. `call_parse_server_rest_api` → `GET /schemas/<Class>` to read fields, or `GET /classes/<Class>`
   with a `where` filter to sample real rows. Use this to ground `angular-service` /
   `cloud-code` work in the actual schema instead of guessing.

**Deploy a Cloud Code change**

1. Edit/verify locally per the `cloud-code` skill.
2. `set_current_app` → the target app (test first).
3. Confirm with the user → `deploy_cloud_code_files`.
4. Tell the user it is now **live**; suggest a smoke test via the app or Parse Dashboard.

**Verify access control**

`call_parse_server_rest_api` → `GET /schemas/<Class>` and inspect CLP, or read an object's ACL —
useful when debugging "why can't this user read X" before touching `functions/`.
