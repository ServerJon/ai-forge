---
name: new-component
description: Scaffold a new Astro component following project conventions (Props interface, design tokens, scoped styles, co-located test)
user-invocable: true
---

# New Component

Scaffold a new Astro component that follows all project conventions.

## Usage

```
/new-component ComponentName [--ui-kit] [--no-test]
```

- **ComponentName**: PascalCase name (e.g., `FeatureCard`, `PricingToggle`)
- **--ui-kit**: Place in `src/components/ui-kit/` (pure visual primitive)
- **--no-test**: Skip generating the co-located test file

Without `--ui-kit`, component goes in `src/components/` (page-specific composite).

## What Gets Generated

### 1. Component File

**ui-kit** → `src/components/ui-kit/{Name}.astro`
**composite** → `src/components/{Name}.astro`

```astro
---
/** {Name} — brief description */
// For ui-kit components: import shared types from @core/types/ui
// import type { ButtonVariant, ComponentSize } from "@core/types/ui";
interface Props {
  /** Primary prop */
  // Add props here
}

const { /* destructure props */ } = Astro.props;
---

<div class="{name}">
  <slot />
</div>

<style>
  .{name} {
    /* Use design tokens — never hardcode values */
    /* var(--fp-*) for colors, shadows, radii, spacing */
  }
</style>
```

### 2. Test File (unless `--no-test`)

Co-located as `{Name}.test.ts`:

```typescript
import { experimental_AstroContainer as AstroContainer } from "astro/container";
import { describe, it, expect } from "vitest";
import {Name} from "./{Name}.astro";

describe("{Name}", () => {
  it("should render with default props", async () => {
    const container = await AstroContainer.create();
    const result = await container.renderToString({Name}, {
      props: { /* default props */ },
    });

    expect(result).toContain("{name}");
  });
});
```

## Rules to Follow

1. **PascalCase** file name matching component name
2. **`interface Props`** with JSDoc comments on each prop
3. **Scoped `<style>`** — never `is:global`
4. **Design tokens only** — all visual values from `var(--fp-*)`, zero hardcoded colors/shadows/radii
5. **Tailwind for layout only** — flex, grid, gap, responsive breakpoints
6. **Semantic HTML** — `<button>` not `<div onclick>`, `<nav>` not `<div class="nav">`
7. **Accessibility** — `aria-label` on icon-only buttons, `role` on custom widgets
8. **Slots** — use `<slot />` for content projection, named slots for multi-area components

## Checklist Before Done

- [ ] Props interface with JSDoc
- [ ] All visual values use `var(--fp-*)` tokens
- [ ] Scoped styles (no `is:global`)
- [ ] Semantic HTML elements
- [ ] Accessibility attributes where needed
- [ ] Co-located test file renders successfully
- [ ] `pnpm build` passes
