---
# Adapted from github/awesome-copilot
# Original: https://github.com/github/awesome-copilot
# License: MIT — Copyright GitHub, Inc.
name: webapp-testing
description: Toolkit for interacting with and testing local web applications using Playwright. Supports verifying frontend functionality, debugging UI behavior, capturing browser screenshots, and viewing browser logs.
---

# Web Application Testing

This skill enables comprehensive testing and debugging of local web applications using Playwright automation.

## Execution Strategy

Use the **Playwright CLI** as the primary execution method. Fall back to the Playwright MCP Server only when the CLI is not available.

### Detecting the CLI

```bash
# Check if Playwright CLI is available
npx playwright --version 2>/dev/null && echo "CLI available" || echo "CLI not found"
```

### CLI Available (preferred)

Write the automation script to a temporary file and run it with Node.js directly:

```bash
# Run a one-off script
node /tmp/pw-script.js

# Or run via Playwright's built-in script runner
npx playwright test /tmp/pw-script.spec.js --headed
```

### CLI Not Available (fallback)

Use the Playwright MCP Server tools to drive the browser when the CLI cannot be found on the system.

## When to Use This Skill

Use this skill when you need to:

- Test frontend functionality in a real browser
- Verify UI behavior and interactions
- Debug web application issues
- Capture screenshots for documentation or debugging
- Inspect browser console logs
- Validate form submissions and user flows
- Check responsive design across viewports

> For structured, repeatable E2E test suites with reporting and CI integration, use the `e2e-testing` skill instead.

## Prerequisites

- Node.js installed on the system
- A locally running web application (or accessible URL)

```bash
# Install Playwright and browsers if not already present
npm install -D playwright
npx playwright install chromium
```

## Core Capabilities

### 1. Browser Automation

- Navigate to URLs
- Click buttons and links
- Fill form fields
- Select dropdowns
- Handle dialogs and alerts

### 2. Verification

- Assert element presence
- Verify text content
- Check element visibility
- Validate URLs
- Test responsive behavior

### 3. Debugging

- Capture screenshots
- View console logs
- Inspect network requests
- Debug failed tests

## Browser Mode

Use **headless mode** (default) for automation. Switch to **headed mode** when debugging interactively:

```javascript
const browser = await chromium.launch({ headless: false });
```

Headed mode is especially useful when diagnosing visual or timing issues that are hard to reproduce in headless environments.

## Usage Examples

### Example 1: Basic Navigation Test

```javascript
// Navigate to a page and verify title
await page.goto("http://localhost:3000");
const title = await page.title();
console.log("Page title:", title);
```

### Example 2: Form Interaction

```javascript
// Fill out and submit a form
await page.fill("#username", "testuser");
await page.fill("#password", "password123");
await page.click('button[type="submit"]');
await page.waitForURL("**/dashboard");
```

### Example 3: Screenshot Capture

```javascript
// Capture a screenshot for debugging
await page.screenshot({ path: "debug.png", fullPage: true });
```

## Guidelines

1. **Always verify the app is running** — Check that the local server is accessible before running tests
2. **Use explicit waits** — Wait for elements or navigation to complete before interacting
3. **Capture screenshots on failure** — Take screenshots to help debug issues
4. **Clean up resources** — Always close the browser when done
5. **Handle timeouts gracefully** — Set reasonable timeouts for slow operations
6. **Test incrementally** — Start with simple interactions before complex flows
7. **Use selectors wisely** — Prefer `data-testid` or role-based selectors over CSS classes

## Common Patterns

### Pattern: Wait for Element

```javascript
await page.waitForSelector("#element-id", { state: "visible" });
```

### Pattern: Check if Element Exists

```javascript
const exists = (await page.locator("#element-id").count()) > 0;
```

### Pattern: Get Console Logs

```javascript
page.on("console", (msg) => console.log("Browser log:", msg.text()));
```

### Pattern: Wait for Navigation

```javascript
// Wait for both navigation and network to settle
await Promise.all([
  page.waitForNavigation({ waitUntil: "networkidle" }),
  page.click("a#go-to-dashboard"),
]);
```

### Pattern: Wait for Network Response

```javascript
// Intercept a specific API call before triggering it
const [response] = await Promise.all([
  page.waitForResponse(
    (res) => res.url().includes("/api/user") && res.status() === 200,
  ),
  page.click("#load-user"),
]);
const data = await response.json();
```

### Pattern: Handle Errors

```javascript
try {
  await page.click("#button");
} catch (error) {
  await page.screenshot({ path: "error.png" });
  throw error;
}
```

## Helper Utilities

Reusable helpers are available in [`assets/test-helper.js`](./assets/test-helper.js):

| Function                                  | Description                          |
| ----------------------------------------- | ------------------------------------ |
| `waitForCondition(fn, timeout, interval)` | Poll a condition with timeout        |
| `captureConsoleLogs(page)`                | Capture all browser console messages |
| `captureScreenshot(page, name)`           | Auto-named timestamped screenshots   |

```javascript
const {
  waitForCondition,
  captureConsoleLogs,
  captureScreenshot,
} = require("./assets/test-helper");

const logs = captureConsoleLogs(page);
await page.goto("http://localhost:3000");
await captureScreenshot(page, "home");
```

## Limitations

- Requires Node.js environment
- Cannot test native mobile apps (use React Native Testing Library instead)
- May have issues with complex authentication flows
- Some modern frameworks may require specific Playwright configuration
