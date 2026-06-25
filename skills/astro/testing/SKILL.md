---
name: testing
description: Unit tests with Vitest + Astro Container API and end-to-end tests with Playwright for the Wesog landing page
user-invocable: false
---

# Testing

Test the Wesog landing page with **Vitest** (unit/component) and **Playwright** (end-to-end).

> **Wesog Project Rules**:
>
> - Unit tests run via: `pnpm test` (Vitest)
> - E2E tests run via: `pnpm test:e2e` (Playwright)
> - Vitest uses `getViteConfig()` from `astro/config` to inherit Astro settings
> - Test Astro components with the **Container API** (`astro/container`)
> - Test files live alongside source files as `*.test.ts`
> - E2E test files live in `e2e/` directory as `*.spec.ts`
> - Use `vi.fn()` and `vi.mock()` for mocking — NEVER use Jest-style `jest.fn()`
> - Always import `describe`, `it`, `expect`, `vi` from `vitest` (globals NOT enabled)

## Running Tests

```bash
# Unit tests
pnpm test              # Run all unit tests
pnpm test -- --watch   # Watch mode
pnpm test -- --coverage # Coverage report
pnpm test -- Button    # Run tests matching "Button"

# End-to-end tests
pnpm test:e2e                    # Run all E2E tests
pnpm test:e2e -- --ui            # Open Playwright UI mode
pnpm test:e2e -- index.spec.ts   # Run single test file
npx playwright show-report       # View HTML report
```

## Test File Location

Tests live alongside their source files as `*.test.ts`. E2E tests live in `e2e/`:

```txt
src/
├── components/
│   └── ui-kit/
│       ├── Button.astro
│       ├── Button.test.ts        ← unit test
│       ├── Card.astro
│       └── Card.test.ts
├── i18n/
│   ├── utils.ts
│   └── utils.test.ts
├── pages/
│   └── index.astro
└── layouts/
    └── Layout.astro
e2e/
├── home.spec.ts                  ← E2E test
├── navigation.spec.ts
└── accessibility.spec.ts
```

## Configuration

### Vitest — `vitest.config.ts`

```typescript
/// <reference types="vitest/config" />
import { getViteConfig } from "astro/config";

export default getViteConfig({
  test: {
    include: ["src/**/*.test.ts"],
    exclude: ["node_modules", "dist", "e2e"],
    coverage: {
      provider: "v8",
      include: ["src/**/*.{ts,astro}"],
      exclude: ["src/env.d.ts", "src/**/*.test.ts"],
      reporter: ["text", "html"],
    },
  },
});
```

### Playwright — `playwright.config.ts`

```typescript
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: process.env.CI ? "github" : "html",
  use: {
    baseURL: "http://localhost:4321",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
    {
      name: "firefox",
      use: { ...devices["Desktop Firefox"] },
    },
    {
      name: "webkit",
      use: { ...devices["Desktop Safari"] },
    },
    {
      name: "mobile-chrome",
      use: { ...devices["Pixel 5"] },
    },
    {
      name: "mobile-safari",
      use: { ...devices["iPhone 12"] },
    },
  ],
  webServer: {
    command: "pnpm preview",
    url: "http://localhost:4321/",
    timeout: 120 * 1000,
    reuseExistingServer: !process.env.CI,
  },
});
```

### Package Scripts

```jsonc
{
  "scripts": {
    "test": "vitest run",
    "test:watch": "vitest",
    "test:coverage": "vitest run --coverage",
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui"
  }
}
```

## Unit Testing Astro Components (Container API)

The Container API renders `.astro` components server-side in isolation, returning HTML strings for assertion.

### Basic Component Test

```typescript
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, it, expect } from "vitest";
import Button from "./Button.astro";

describe("Button", () => {
  it("should render with default props", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Button, {
      props: { label: "Click me" },
    });

    expect(result).toContain("Click me");
    expect(result).toContain("<button");
  });

  it("should render as anchor when href is provided", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Button, {
      props: { label: "Go", href: "/about/" },
    });

    expect(result).toContain("<a");
    expect(result).toContain('href="/about/"');
  });
});
```

### Testing Props and Variants

```typescript
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, it, expect } from "vitest";
import Card from "./Card.astro";

describe("Card", () => {
  let container: InstanceType<typeof AstroContainer>;

  // Reuse container across tests for performance
  beforeAll(async () => {
    container = await AstroContainer.create();
  });

  it("should apply highlighted styles", async () => {
    const result = await container.renderToString(Card, {
      props: { highlighted: true },
      slots: { default: "Card content" },
    });

    expect(result).toContain("card--highlighted");
    expect(result).toContain("Card content");
  });

  it("should apply padding variant", async () => {
    const result = await container.renderToString(Card, {
      props: { padding: "lg" },
      slots: { default: "Content" },
    });

    expect(result).toContain("card--lg");
  });
});
```

### Testing Slots

```typescript
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, it, expect } from "vitest";
import SectionHeader from "./SectionHeader.astro";

describe("SectionHeader", () => {
  it("should render title, description, and slot content", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(SectionHeader, {
      props: {
        title: "Features",
        description: "Everything you need",
      },
      slots: {
        default: '<span class="badge">New</span>',
      },
    });

    expect(result).toContain("Features");
    expect(result).toContain("Everything you need");
    expect(result).toContain('<span class="badge">New</span>');
  });

  it("should omit description when not provided", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(SectionHeader, {
      props: { title: "Simple Header" },
    });

    expect(result).toContain("Simple Header");
    expect(result).not.toContain("<p");
  });
});
```

### Testing Named Slots

```typescript
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, it, expect } from "vitest";
import Modal from "./Modal.astro";

describe("Modal", () => {
  it("should render header and body slots", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString(Modal, {
      props: { id: "test-modal" },
      slots: {
        header: "<h2>Modal Title</h2>",
        default: "<p>Modal body content</p>",
      },
    });

    expect(result).toContain('id="test-modal"');
    expect(result).toContain("Modal Title");
    expect(result).toContain("Modal body content");
  });
});
```

### Testing with Nested Components

```typescript
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, it, expect } from "vitest";
import Section from "./Section.astro";
import SectionHeader from "./SectionHeader.astro";

describe("Section with SectionHeader", () => {
  it("should render nested components", async () => {
    const container = await AstroContainer.create();
    const headerHtml = await container.renderToString(SectionHeader, {
      props: { title: "Features" },
    });

    const result = await container.renderToString(Section, {
      props: { bg: "primary" },
      slots: { default: headerHtml },
    });

    expect(result).toContain("Features");
    expect(result).toContain("<section");
  });
});
```

## Unit Testing Utility Functions

### i18n Utils

```typescript
import { describe, it, expect } from "vitest";
import { getLangFromUrl, useTranslations } from "./utils";

describe("getLangFromUrl", () => {
  it("should extract language from URL", () => {
    expect(getLangFromUrl(new URL("https://example.com/es/about/"))).toBe("es");
  });

  it("should default to 'es' for root URL", () => {
    expect(getLangFromUrl(new URL("https://example.com/"))).toBe("es");
  });
});

describe("useTranslations", () => {
  it("should return translation for given key", () => {
    const t = useTranslations("es");
    expect(t("nav.home")).toBe("Inicio");
  });

  it("should fall back to default language", () => {
    const t = useTranslations("en");
    expect(typeof t("nav.home")).toBe("string");
  });
});
```

## Mocking

### Mock a Module

```typescript
import { describe, it, expect, vi } from "vitest";

vi.mock("../i18n/utils", () => ({
  getLangFromUrl: vi.fn(() => "es"),
  useTranslations: vi.fn(() => (key: string) => `translated:${key}`),
}));

describe("Component using i18n", () => {
  it("should use mocked translations", async () => {
    const { getLangFromUrl } = await import("../i18n/utils");
    expect(getLangFromUrl(new URL("https://example.com/"))).toBe("es");
  });
});
```

### Mock Fetch (API Calls)

```typescript
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

describe("fetchData", () => {
  beforeEach(() => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() =>
        Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ data: "test" }),
        }),
      ),
    );
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("should fetch and return data", async () => {
    const response = await fetch("/api/data");
    const json = await response.json();

    expect(json.data).toBe("test");
    expect(fetch).toHaveBeenCalledWith("/api/data");
  });
});
```

## End-to-End Tests (Playwright)

### Basic Page Test

```typescript
import { test, expect } from "@playwright/test";

test.describe("Home page", () => {
  test("should have correct title and meta", async ({ page }) => {
    await page.goto("/");

    await expect(page).toHaveTitle(/Wesog/);

    const description = page.locator('meta[name="description"]');
    await expect(description).toHaveAttribute("content", /.+/);
  });

  test("should render hero section", async ({ page }) => {
    await page.goto("/");

    const hero = page.locator("#hero");
    await expect(hero).toBeVisible();

    const cta = hero.getByRole("link", { name: /empezar|start/i });
    await expect(cta).toBeVisible();
  });
});
```

### Navigation Test

```typescript
import { test, expect } from "@playwright/test";

test.describe("Navigation", () => {
  test("should have sticky header", async ({ page }) => {
    await page.goto("/");

    const header = page.locator("header");
    await expect(header).toBeVisible();

    // Scroll down and verify header stays visible
    await page.evaluate(() => window.scrollTo(0, 500));
    await expect(header).toBeVisible();
    await expect(header).toBeInViewport();
  });

  test("should navigate to sections via nav links", async ({ page }) => {
    await page.goto("/");

    await page.getByRole("link", { name: /funcionalidades|features/i }).click();

    // Verify scroll to section
    const section = page.locator("#features");
    await expect(section).toBeInViewport();
  });
});
```

### Interactive Component Test

```typescript
import { test, expect } from "@playwright/test";

test.describe("Interactive components", () => {
  test("pricing toggle should switch between monthly and annual", async ({
    page,
  }) => {
    await page.goto("/");

    const toggle = page.locator('[data-toggle="pricing"]');
    await toggle.click();

    // Verify prices updated
    const price = page.locator("[data-price]").first();
    await expect(price).not.toHaveText(/—/);
  });

  test("modal should open and close", async ({ page }) => {
    await page.goto("/");

    // Open modal
    const trigger = page.locator("[data-modal-open]").first();
    await trigger.click();

    const modal = page.locator("[data-modal].is-open");
    await expect(modal).toBeVisible();

    // Close with backdrop click
    await page.locator("[data-modal-backdrop]").click();
    await expect(modal).not.toBeVisible();
  });
});
```

### Responsive Design Test

```typescript
import { test, expect } from "@playwright/test";

test.describe("Responsive design", () => {
  test("mobile menu should toggle", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/");

    // Desktop nav should be hidden
    const desktopNav = page.locator("nav.desktop-nav");
    await expect(desktopNav).not.toBeVisible();

    // Mobile menu button should be visible
    const menuButton = page.getByRole("button", { name: /menu/i });
    await expect(menuButton).toBeVisible();
  });

  test("hero should stack vertically on mobile", async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });
    await page.goto("/");

    const hero = page.locator("#hero");
    await expect(hero).toBeVisible();

    // Take screenshot for visual regression
    await expect(hero).toHaveScreenshot("hero-mobile.png");
  });
});
```

### Visual Regression Test

```typescript
import { test, expect } from "@playwright/test";

test.describe("Visual regression", () => {
  test("full page screenshot", async ({ page }) => {
    await page.goto("/");
    await page.waitForLoadState("networkidle");

    await expect(page).toHaveScreenshot("homepage.png", {
      fullPage: true,
      maxDiffPixelRatio: 0.01,
    });
  });

  test("card component snapshot", async ({ page }) => {
    await page.goto("/");

    const card = page.locator(".card").first();
    await expect(card).toHaveScreenshot("card.png");
  });
});
```

### Accessibility Test

```typescript
import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

test.describe("Accessibility", () => {
  test("home page should have no a11y violations", async ({ page }) => {
    await page.goto("/");

    const results = await new AxeBuilder({ page })
      .withTags(["wcag2a", "wcag2aa"])
      .analyze();

    expect(results.violations).toEqual([]);
  });

  test("interactive elements should be keyboard accessible", async ({
    page,
  }) => {
    await page.goto("/");

    // Tab through interactive elements
    await page.keyboard.press("Tab");
    const firstFocused = await page.evaluate(() =>
      document.activeElement?.tagName.toLowerCase(),
    );
    expect(["a", "button", "input"]).toContain(firstFocused);

    // Verify focus is visible
    const focusedElement = page.locator(":focus");
    await expect(focusedElement).toBeVisible();
  });

  test("images should have alt text", async ({ page }) => {
    await page.goto("/");

    const images = page.locator("img");
    const count = await images.count();

    for (let i = 0; i < count; i++) {
      const alt = await images.nth(i).getAttribute("alt");
      expect(alt, `Image ${i} missing alt text`).toBeTruthy();
    }
  });
});
```

### Performance Test

```typescript
import { test, expect } from "@playwright/test";

test.describe("Performance", () => {
  test("page should load within acceptable time", async ({ page }) => {
    const start = Date.now();
    await page.goto("/");
    await page.waitForLoadState("networkidle");
    const loadTime = Date.now() - start;

    expect(loadTime).toBeLessThan(3000); // Under 3 seconds
  });

  test("no console errors on page load", async ({ page }) => {
    const errors: string[] = [];
    page.on("console", (msg) => {
      if (msg.type() === "error") errors.push(msg.text());
    });

    await page.goto("/");
    await page.waitForLoadState("networkidle");

    expect(errors).toEqual([]);
  });
});
```

## Testing Patterns

### Reusable Container Helper

Create a shared helper to reduce boilerplate in component tests:

```typescript
// src/test-utils.ts
import { experimental_AstroContainer as AstroContainer } from "astro/container";

let container: InstanceType<typeof AstroContainer>;

export async function getContainer() {
  if (!container) {
    container = await AstroContainer.create();
  }
  return container;
}

export async function renderComponent(
  Component: any,
  options?: {
    props?: Record<string, unknown>;
    slots?: Record<string, string>;
  },
) {
  const c = await getContainer();
  return c.renderToString(Component, options);
}
```

Usage:

```typescript
import { describe, it, expect } from "vitest";
import { renderComponent } from "../../test-utils";
import Tag from "./Tag.astro";

describe("Tag", () => {
  it("should render default variant", async () => {
    const html = await renderComponent(Tag, {
      slots: { default: "Beta" },
    });

    expect(html).toContain("Beta");
  });
});
```

### HTML Assertion Helpers

```typescript
// src/test-utils.ts (continued)

/** Check that rendered HTML contains a CSS class */
export function expectClass(html: string, className: string) {
  expect(html).toMatch(new RegExp(`class="[^"]*\\b${className}\\b[^"]*"`));
}

/** Check that rendered HTML contains an element with attribute */
export function expectAttr(html: string, attr: string, value?: string) {
  if (value) {
    expect(html).toContain(`${attr}="${value}"`);
  } else {
    expect(html).toContain(attr);
  }
}
```

### E2E Page Object Pattern

```typescript
// e2e/pages/home.page.ts
import type { Page, Locator } from "@playwright/test";

export class HomePage {
  readonly hero: Locator;
  readonly header: Locator;
  readonly ctaButton: Locator;
  readonly pricingToggle: Locator;

  constructor(private page: Page) {
    this.hero = page.locator("#hero");
    this.header = page.locator("header");
    this.ctaButton = page.getByRole("link", { name: /empezar|start/i });
    this.pricingToggle = page.locator('[data-toggle="pricing"]');
  }

  async goto() {
    await this.page.goto("/");
  }

  async scrollToSection(id: string) {
    await this.page.locator(`#${id}`).scrollIntoViewIfNeeded();
  }

  async togglePricing() {
    await this.pricingToggle.click();
  }
}
```

Usage:

```typescript
import { test, expect } from "@playwright/test";
import { HomePage } from "./pages/home.page";

test("hero CTA should be visible", async ({ page }) => {
  const home = new HomePage(page);
  await home.goto();

  await expect(home.ctaButton).toBeVisible();
});
```

## What to Test

### Unit Tests (Vitest + Container API)

| Target | What to Assert |
| -------- | --------------- |
| **ui-kit components** | Correct HTML output for each prop/variant combination |
| **Slot rendering** | Default and named slots produce expected markup |
| **Conditional rendering** | Elements appear/disappear based on props |
| **CSS classes** | Correct class names applied per variant/state |
| **Accessibility attrs** | `aria-*`, `role`, `id` attributes present |
| **i18n utilities** | Language detection, translation lookup, fallback behavior |
| **Helper functions** | Pure utility logic (formatters, validators, etc.) |

### E2E Tests (Playwright)

| Target | What to Assert |
| -------- | --------------- |
| **Page load** | Title, meta tags, critical sections visible |
| **Navigation** | Links work, sticky header persists, anchor scrolling |
| **Interactivity** | Toggles, modals, dropdowns respond to clicks |
| **Responsive** | Layout adapts at mobile/tablet/desktop breakpoints |
| **Accessibility** | axe-core scan passes WCAG 2.1 AA, keyboard nav works |
| **Visual regression** | Screenshots match baseline within tolerance |
| **Performance** | No console errors, page loads under 3s |

## Rules

1. **Always import from `vitest`** — `import { describe, it, expect, vi } from 'vitest'`
2. **Use Container API for Astro components** — never try to mount `.astro` files in JSDOM
3. **Test behavior, not implementation** — assert on HTML output, not internal component state
4. **One assertion focus per test** — test one concept, multiple `expect()` calls are fine if related
5. **Descriptive test names** — `"should render as anchor when href is provided"` not `"test 1"`
6. **No hardcoded URLs in E2E** — always use `baseURL` from config, navigate with relative paths
7. **Build before E2E** — Playwright runs against `pnpm preview` (production build), not dev server
8. **Keep E2E tests independent** — no test should depend on another test's state
9. **Use Page Objects for E2E** — extract selectors and actions into reusable page classes
10. **Accessibility tests are mandatory** — every page must pass axe-core WCAG 2.1 AA scan
