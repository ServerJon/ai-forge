---
name: playwright-cli
description: >
  Playwright CLI (playwright-cli) for agent-driven browser automation from the
  command line — open pages, snapshot the accessibility tree, interact with
  elements, capture screenshots, and inspect console/network. Use this skill
  for browser automation, manual UI flows, or frontend debugging. Prefer the
  CLI over the Playwright MCP. Not a unit-test runner — use Jest for that.
user-invocable: false
---

# Playwright CLI (`playwright-cli`)

Browser automation for coding agents: you run shell commands and the CLI
streams a concise, ref-based page snapshot back into the Bash result. A
persistent daemon keeps the browser alive between commands (no per-command
startup cost). Headless by default. Run `playwright-cli <command> --help` for
flag details.

## Setup (one-off, per machine)

```bash
npm install -g @playwright/cli
playwright-cli install --skills   # optional: install bundled skills
```

## This project (important)

- Example route base for this module: `/telephony/security`.
- The CLI is for **browser automation only**, not unit testing. Keep using
  Jest + Testing Library for unit/component tests.

## Core workflow

`snapshot` returns the accessibility tree with element `ref`s. Take a snapshot
first, then act on the refs it reports.

```bash
playwright-cli open http://localhost:<port>/telephony/security
playwright-cli snapshot                      # get element refs
playwright-cli fill <ref> "Profile name"
playwright-cli click <ref>
playwright-cli type "free text"              # types into focused element
playwright-cli press Enter
playwright-cli select <ref> <value>
playwright-cli check <ref>                   # uncheck / hover also available
playwright-cli screenshot [ref]              # full page or single element
```

## Navigation & tabs

```bash
playwright-cli goto <url>      playwright-cli go-back     playwright-cli reload
playwright-cli tab-new [url]   playwright-cli tab-list    playwright-cli tab-select <idx>
```

## Debugging (console, network, eval)

```bash
playwright-cli console [min-level]     # page console output
playwright-cli network                 # observed requests
playwright-cli route <pattern> [opts]  # mock / intercept requests
playwright-cli eval <func> [ref]       # run JS in page (or against a ref)
playwright-cli run-code <code>
```

## Storage & auth (reuse a logged-in session)

```bash
playwright-cli state-save [file]     # persist cookies + storage
playwright-cli state-load <file>     # restore for an authenticated run
playwright-cli cookie-list [--domain]
playwright-cli localstorage-get <key>
```

## Sessions (isolated browser instances)

```bash
playwright-cli -s=<name> open <url>  # run a command in a named session
playwright-cli list                  # list sessions
playwright-cli close-all             # close sessions
```

## Tracing & video

```bash
playwright-cli tracing-start   playwright-cli tracing-stop
playwright-cli video-start [file]   playwright-cli video-stop
```

## Notes

- Default is headless; add `open --headed` to watch, `open --browser=firefox`
  to switch engines, `open --persistent` / `open --profile=<path>` to reuse a
  profile.
- Always re-`snapshot` after navigation or a state change before using refs —
  refs are tied to the current page state.
- For DevTools-specific work (performance traces, Core Web Vitals, deep console
  inspection) prefer the Chrome DevTools MCP instead.

**Reference:** https://playwright.dev/agent-cli/introduction
