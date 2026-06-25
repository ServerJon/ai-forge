---
name: e2e-testing
description: Structured end-to-end test suite authoring using Playwright Test. Covers test organization, assertions, Page Object Model, fixtures, configuration, and CI integration. Builds on the webapp-testing skill for browser automation primitives.
---

# E2E Testing with Playwright Test

This skill covers writing structured, maintainable end-to-end test suites using the **Playwright Test** runner. It complements the `webapp-testing` skill, which handles ad-hoc browser automation and debugging.

Use this skill when you need repeatable, reportable, CI-ready test suites — not one-off scripts.

## Execution Strategy

Use the **Playwright CLI** as the primary way to run tests. Fall back to the Playwright MCP Server only when the CLI is not available.

### Detecting the CLI

```bash
npx playwright --version 2>/dev/null && echo "CLI available" || echo "CLI not found"
```

### CLI Available (preferred)

```bash
# Run all tests
npx playwright test

# Run a specific file
npx playwright test e2e/tests/auth.spec.ts

# Run in headed mode (useful for local debugging)
npx playwright test --headed

# Run a specific browser only
npx playwright test --project=chromium

# Run tests matching a tag or title pattern
npx playwright test --grep @smoke

# Open the interactive UI mode
npx playwright test --ui

# Show the HTML report after a run
npx playwright show-report
```

### CLI Not Available (fallback)

Use the Playwright MCP Server tools to drive the browser and execute test steps when `npx playwright` cannot be found on the system.

## When to Use This Skill

- Writing regression or smoke test suites
- Validating critical user flows (auth, checkout, onboarding)
- Running tests in CI pipelines (GitHub Actions, GitLab CI, etc.)
- Generating HTML test reports
- Organizing tests across multiple pages or user roles
- Parallelizing test execution

## Prerequisites

```bash
# New project
npm init playwright@latest

# Existing project
npm install -D @playwright/test
npx playwright install

# Verify CLI is available
npx playwright --version
```

## Project Structure

```
e2e/
├── playwright.config.ts        # Global config (baseURL, retries, reporters)
├── fixtures/
│   └── base.ts                 # Custom fixtures (auth state, shared helpers)
├── pages/                      # Page Object Models
│   ├── LoginPage.ts
│   └── DashboardPage.ts
├── tests/
│   ├── auth.spec.ts
│   └── dashboard.spec.ts
└── assets/
    └── test-helper.js          # Shared utilities (copy from main assets folder)
```

## Configuration

### `playwright.config.ts`

```typescript
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e/tests",
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0, // Retry flaky tests on CI only
  workers: process.env.CI ? 1 : undefined,
  reporter: [["html", { open: "never" }], ["list"]],

  use: {
    baseURL: process.env.BASE_URL ?? "http://localhost:3000",
    trace: "on-first-retry", // Capture trace on first retry
    screenshot: "only-on-failure",
    video: "retain-on-failure",
  },

  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
    { name: "mobile-chrome", use: { ...devices["Pixel 5"] } },
  ],

  // Start dev server automatically when running locally
  webServer: {
    command: "npm run dev",
    url: "http://localhost:3000",
    reuseExistingServer: !process.env.CI,
  },
});
```

## Test Structure

### Basic Test

```typescript
import { test, expect } from "@playwright/test";

test.describe("Homepage", () => {
  test("displays the hero headline", async ({ page }) => {
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
  });
});
```

### Hooks

```typescript
test.describe("Dashboard", () => {
  test.beforeEach(async ({ page }) => {
    // Runs before each test in this describe block
    await page.goto("/dashboard");
  });

  test.afterEach(async ({ page }, testInfo) => {
    // Capture screenshot on failure for debugging
    if (testInfo.status !== testInfo.expectedStatus) {
      await page.screenshot({ path: `failures/${testInfo.title}.png` });
    }
  });
});
```

## Assertions

Prefer Playwright's built-in `expect` matchers — they auto-retry until the assertion passes or times out:

```typescript
// Element state
await expect(page.locator("#submit")).toBeVisible();
await expect(page.locator("#submit")).toBeEnabled();
await expect(page.locator("#submit")).toBeDisabled();

// Text content
await expect(page.locator(".title")).toHaveText("Welcome");
await expect(page.locator(".title")).toContainText("Welcome");

// Input value
await expect(page.locator("input#email")).toHaveValue("user@example.com");

// URL
await expect(page).toHaveURL("/dashboard");
await expect(page).toHaveURL(/.*dashboard/);

// Count
await expect(page.locator("li.item")).toHaveCount(5);

// Attribute
await expect(page.locator("img.logo")).toHaveAttribute("alt", "Logo");
```

> **Avoid** `page.locator().count() > 0` for assertions — use `toBeVisible()` or `toHaveCount()` so Playwright can auto-retry on failure.

## Page Object Model (POM)

Encapsulate page interactions to keep tests readable and maintainable.

### `pages/LoginPage.ts`

```typescript
import { type Page, type Locator, expect } from "@playwright/test";

/**
 * Page Object for the login flow.
 * Encapsulates selectors and interactions to keep tests clean.
 */
export class LoginPage {
  readonly page: Page;
  readonly emailInput: Locator;
  readonly passwordInput: Locator;
  readonly submitButton: Locator;
  readonly errorMessage: Locator;

  constructor(page: Page) {
    this.page = page;
    this.emailInput = page.getByLabel("Email");
    this.passwordInput = page.getByLabel("Password");
    this.submitButton = page.getByRole("button", { name: "Sign in" });
    this.errorMessage = page.getByRole("alert");
  }

  async goto() {
    await this.page.goto("/login");
  }

  async login(email: string, password: string) {
    await this.emailInput.fill(email);
    await this.passwordInput.fill(password);
    await this.submitButton.click();
  }

  async expectError(message: string) {
    await expect(this.errorMessage).toContainText(message);
  }
}
```

### Test using POM

```typescript
import { test, expect } from "@playwright/test";
import { LoginPage } from "../pages/LoginPage";

test.describe("Authentication", () => {
  test("redirects to dashboard after login", async ({ page }) => {
    const login = new LoginPage(page);
    await login.goto();
    await login.login("user@example.com", "password123");
    await expect(page).toHaveURL("/dashboard");
  });

  test("shows error for invalid credentials", async ({ page }) => {
    const login = new LoginPage(page);
    await login.goto();
    await login.login("bad@example.com", "wrong");
    await login.expectError("Invalid credentials");
  });
});
```

## Fixtures

Use fixtures to share authenticated state or reusable setup across tests.

### `fixtures/base.ts`

```typescript
import { test as base } from "@playwright/test";
import { LoginPage } from "../pages/LoginPage";

type Fixtures = {
  authenticatedPage: ReturnType<typeof base.extend> extends { use: infer U }
    ? U
    : never;
};

/**
 * Extended test fixture that provides a pre-authenticated page.
 * Avoids repeating the login flow in every test.
 */
export const test = base.extend({
  page: async ({ page }, use) => {
    const login = new LoginPage(page);
    await login.goto();
    await login.login(
      process.env.TEST_USER_EMAIL ?? "user@example.com",
      process.env.TEST_USER_PASSWORD ?? "password123",
    );
    await use(page);
  },
});

export { expect } from "@playwright/test";
```

### Using the fixture

```typescript
import { test, expect } from "../fixtures/base";

test("dashboard loads for authenticated user", async ({ page }) => {
  await page.goto("/dashboard");
  await expect(page.getByRole("heading", { name: "Dashboard" })).toBeVisible();
});
```

## Network Interception

```typescript
// Mock an API response
await page.route("**/api/users", (route) =>
  route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify([{ id: 1, name: "Test User" }]),
  }),
);

// Wait for a real API call before asserting
const [response] = await Promise.all([
  page.waitForResponse(
    (res) => res.url().includes("/api/users") && res.status() === 200,
  ),
  page.click("#load-users"),
]);
const users = await response.json();
```

## Responsive Testing

```typescript
test("renders mobile nav on small screens", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto("/");
  await expect(page.locator("[data-testid='mobile-nav']")).toBeVisible();
});
```

## CI Integration (GitHub Actions)

```yaml
# .github/workflows/e2e.yml
name: E2E Tests

on: [push, pull_request]

jobs:
  e2e:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: npx playwright test
        env:
          BASE_URL: http://localhost:3000
          CI: true
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: playwright-report/
```

## Selector Priority

Prefer selectors in this order (most to least resilient):

| Priority | Selector    | Example                                   |
| -------- | ----------- | ----------------------------------------- |
| ✅ Best  | Role-based  | `getByRole("button", { name: "Submit" })` |
| ✅ Best  | Label-based | `getByLabel("Email")`                     |
| ✅ Best  | Test ID     | `getByTestId("submit-btn")`               |
| ⚠️ OK    | Text        | `getByText("Welcome back")`               |
| ❌ Avoid | CSS class   | `.btn-primary`                            |
| ❌ Avoid | XPath       | `//button[@class='btn']`                  |

## Guidelines

1. **One concern per test** — each test validates a single behavior
2. **Never share state between tests** — tests must be independently runnable
3. **Use `data-testid` attributes** — coordinate with frontend developers to add them
4. **Keep POM methods action-focused** — `login()`, `submitForm()`, not implementation details
5. **Use environment variables** — never hardcode credentials or URLs
6. **Trace on retry** — keep `trace: "on-first-retry"` in config for debugging CI failures
7. **Tag tests** — use `test.tag()` or naming conventions (`smoke`, `regression`) for selective runs

## Helper Utilities

The shared helpers from `webapp-testing` are fully compatible:

```typescript
import { captureConsoleLogs, waitForResponse } from "../assets/test-helper";

test("logs no errors on load", async ({ page }) => {
  const logs = captureConsoleLogs(page);
  await page.goto("/");
  const errors = logs.filter((l) => l.type === "error");
  expect(errors).toHaveLength(0);
});
```

## Limitations

- Not a unit test replacement — test behavior, not implementation
- Slow compared to unit tests — keep the suite focused on critical paths
- Authentication flows requiring MFA or OAuth need additional setup (storage state or mocking)
- WebSocket testing requires explicit `waitForEvent` handling
