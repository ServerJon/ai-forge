---
name: core
description: Shared constants, types, icons, validation, and pricing data in src/core/ — how to use and extend the centralized module
user-invocable: false
---

# Core Module (`src/core/`)

Claude MUST consult this when working with modal IDs, route/section anchors, UI prop types, icons, pricing data, or form validation.

## Folder Structure

```
src/core/
├── constants/
│   ├── modal-ids.ts      # MODAL_IDS object + ModalId type
│   ├── routes.ts         # SECTIONS, PAGES, EXTERNAL + sectionHref()
│   └── pricing.ts        # PLAN_IDS, PLAN_NAMES, PLAN_PRICES, buildCompareGroups(t)
├── types/
│   ├── ui.ts             # Shared UI-kit prop types (ButtonVariant, ButtonSize, etc.)
│   └── index.ts          # Domain types (CellValue, CompareRow, CompareGroup) + re-exports ui.ts
├── icons/
│   └── index.ts          # ICONS (18×18), FEAT_ICONS (16×16), UTIL_ICONS (check, chevron)
├── validation/
│   ├── index.ts          # VALIDATION_RULES, validateEmail(), validatePassword()
│   └── index.test.ts     # Unit tests for validators
└── index.ts              # Barrel re-export of everything
```

**Path alias**: `@core/*` → `./src/core/*` (defined in `tsconfig.json`)

## What Lives in `src/core/`

| Category | File | Exports | Used By |
|----------|------|---------|---------|
| Modal IDs | `constants/modal-ids.ts` | `MODAL_IDS`, `ModalId` | All modals, sections, Header |
| Routes | `constants/routes.ts` | `SECTIONS`, `PAGES`, `EXTERNAL`, `sectionHref()` | Header, Footer, all sections, pages |
| Pricing | `constants/pricing.ts` | `PLAN_IDS`, `PLAN_NAMES`, `PLAN_PRICES`, `buildCompareGroups(t)` | Pricing.astro, CheckoutModal.astro |
| UI Types | `types/ui.ts` | `ButtonVariant`, `ButtonSize`, `CardPadding`, `SectionBackground`, `TagVariant`, `TooltipPosition`, `ComponentSize`, `InputType` | All ui-kit components |
| Domain Types | `types/index.ts` | `CellValue`, `CompareRow`, `CompareGroup` | Pricing.astro |
| Icons | `icons/index.ts` | `ICONS`, `FEAT_ICONS`, `UTIL_ICONS` | Benefits, Workflows, Solutions, Pricing |
| Validation | `validation/index.ts` | `VALIDATION_RULES`, `validateEmail()`, `validatePassword()` | CheckoutModal.astro |

## Import Patterns

### In Astro Frontmatter (Server-Side)

```astro
---
import { MODAL_IDS } from "@core/constants/modal-ids";
import { SECTIONS, PAGES, EXTERNAL } from "@core/constants/routes";
import { ICONS, FEAT_ICONS } from "@core/icons";
import { buildCompareGroups } from "@core/constants/pricing";
import type { ButtonVariant } from "@core/types/ui";

const groups = buildCompareGroups(t); // Pass the i18n t() function
---

<Section id={SECTIONS.PRICING}>
  <Button data-open-modal={MODAL_IDS.DEMO_VIDEO}>Demo</Button>
  <a href={`${base}#${SECTIONS.CONTACT}`}>Contact</a>
</Section>
```

### In `<script>` Tags (Client-Side)

Astro `<script>` tags (without `is:inline`) are processed by Vite, so TS imports work:

```astro
<script>
  import { MODAL_IDS } from "@core/constants/modal-ids";
  import { PLAN_NAMES, PLAN_PRICES } from "@core/constants/pricing";
  import { VALIDATION_RULES } from "@core/validation";
  import { EXTERNAL } from "@core/constants/routes";

  // Use constants directly in client-side code
  (window as any).openModal?.(MODAL_IDS.CHECKOUT);
</script>
```

**Important**: `is:inline` scripts cannot use imports — they are emitted verbatim. Only standard `<script>` tags support `@core` imports.

### Barrel Import (When You Need Multiple Things)

```typescript
import { MODAL_IDS, SECTIONS, icons, validateEmail } from "@core";
```

Prefer specific imports (`@core/constants/modal-ids`) over barrel imports for clarity.

## Rules

### 1. Never Hardcode Modal IDs

```astro
<!-- BAD -->
<Modal id="modal-search">
<button data-open-modal="modal-demo-video">

<!-- GOOD -->
<Modal id={MODAL_IDS.SEARCH}>
<button data-open-modal={MODAL_IDS.DEMO_VIDEO}>
```

### 2. Never Hardcode Section Anchors or Page Paths

```astro
<!-- BAD -->
<a href={`${base}#pricing`}>
<Section id="contact">
<a href={getLocalizedPath("/privacy/", lang)}>

<!-- GOOD -->
<a href={`${base}#${SECTIONS.PRICING}`}>
<Section id={SECTIONS.CONTACT}>
<a href={getLocalizedPath(PAGES.PRIVACY, lang)}>
```

### 3. Never Hardcode `/dashboard` Links

```astro
<!-- BAD -->
<a href="/dashboard">

<!-- GOOD -->
<a href={EXTERNAL.DASHBOARD}>
```

### 4. UI-Kit Props Must Use Shared Types

```astro
---
<!-- BAD -->
interface Props {
  variant?: "primary" | "secondary" | "ghost" | "link";
}

<!-- GOOD -->
import type { ButtonVariant } from "@core/types/ui";
interface Props {
  variant?: ButtonVariant;
}
---
```

### 5. Never Inline SVG Icon Definitions in Sections

```astro
---
<!-- BAD -->
const icons = {
  search: `<svg ...>...</svg>`,
};

<!-- GOOD -->
import { icons } from "@core/icons";
---
```

### 6. Validation Uses Shared Constants

```typescript
// BAD
if (password.length < 6) { ... }
if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) { ... }

// GOOD
import { VALIDATION_RULES } from "@core/validation";
if (password.length < VALIDATION_RULES.PASSWORD_MIN_LENGTH) { ... }
if (!VALIDATION_RULES.EMAIL_REGEX.test(email)) { ... }
```

## How to Extend

### Adding a New Modal

1. Add the ID to `MODAL_IDS` in `src/core/constants/modal-ids.ts`:
   ```typescript
   export const MODAL_IDS = {
     // ...existing
     NEW_MODAL: "modal-new-thing",
   } as const;
   ```
2. Use `MODAL_IDS.NEW_MODAL` in the modal component's `<Modal id={...}>` and all triggers.

### Adding a New Section

1. Add the ID to `SECTIONS` in `src/core/constants/routes.ts`:
   ```typescript
   export const SECTIONS = {
     // ...existing
     NEW_SECTION: "new-section",
   } as const;
   ```
2. Use `SECTIONS.NEW_SECTION` in the `<Section id={...}>` and all anchor links.

### Adding a New Icon

1. Add the SVG string to the appropriate group in `src/core/icons/index.ts`:
   - `ICONS` — 18×18 stroke-based icons for section sidebar/cards
   - `FEAT_ICONS` — 16×16 feature icons for profile cards
   - `UTIL_ICONS` — UI utility icons (checkmarks, chevrons)
2. Import and use: `import { icons } from "@core/icons";`

### Adding a New UI-Kit Prop Type

1. Add the type to `src/core/types/ui.ts`:
   ```typescript
   export type NewVariant = "a" | "b" | "c";
   ```
2. Re-export from `src/core/types/index.ts` and `src/core/index.ts`.
3. Import in the component: `import type { NewVariant } from "@core/types/ui";`

### Adding a New Plan

1. Add to `PLAN_IDS`, `PLAN_NAMES`, and `PLAN_PRICES` in `src/core/constants/pricing.ts`.
2. Add the plan column to `buildCompareGroups()` rows (requires updating `CompareRow` type too).

### Adding Validation Rules

1. Add new constants to `VALIDATION_RULES` in `src/core/validation/index.ts`.
2. Add new validator functions as needed.
3. Add tests in `src/core/validation/index.test.ts`.

## What Does NOT Belong in `src/core/`

- **Component code** — Components stay in `src/components/`
- **i18n strings** — Translation keys stay in `src/i18n/`
- **CSS/styles** — Design tokens stay in `src/styles/`
- **Page-specific data** — Data only used by one component stays in that component's frontmatter
- **Runtime-only helpers** — DOM manipulation utilities belong in component `<script>` blocks
