---
name: i18n-add
description: Add or update translation keys in the i18n dictionary for a component or page
user-invocable: true
---

# i18n Add

Add translation keys to the project's i18n system following Astro's i18n recipe.

## Usage

```
/i18n-add ComponentName
/i18n-add --page pricing
/i18n-add --init
```

- **ComponentName**: Add translation keys for a specific component
- **--page name**: Add translation keys for a specific page
- **--init**: Set up the i18n system from scratch (create files if they don't exist)

## i18n System Structure

```
src/
└── i18n/
    ├── ui.ts         ← Translation dictionary (all strings)
    └── utils.ts      ← Helper functions (getLangFromUrl, useTranslations)
```

## Init: Create i18n Files

If `src/i18n/` doesn't exist yet, create both files:

### `src/i18n/ui.ts`

```typescript
export const languages = {
  es: "Español",
  en: "English",
};

export const defaultLang = "es";

export const ui = {
  es: {
    // Navigation
    "nav.home": "Inicio",
    "nav.features": "Funcionalidades",
    "nav.pricing": "Precios",
    "nav.contact": "Contacto",

    // Common
    "common.cta": "Empezar gratis",
    "common.learn-more": "Saber más",
  },
  en: {
    // Navigation
    "nav.home": "Home",
    "nav.features": "Features",
    "nav.pricing": "Pricing",
    "nav.contact": "Contact",

    // Common
    "common.cta": "Start free",
    "common.learn-more": "Learn more",
  },
} as const;
```

### `src/i18n/utils.ts`

```typescript
import { ui, defaultLang } from "./ui";

export function getLangFromUrl(url: URL) {
  const [, lang] = url.pathname.split("/");
  if (lang in ui) return lang as keyof typeof ui;
  return defaultLang;
}

export function useTranslations(lang: keyof typeof ui) {
  return function t(key: keyof (typeof ui)[typeof defaultLang]) {
    return ui[lang][key] || ui[defaultLang][key];
  };
}
```

## Key Naming Convention

```
{scope}.{element}[-{modifier}]
```

| Scope | Usage | Example |
|-------|-------|---------|
| `nav` | Navigation items | `nav.home`, `nav.features` |
| `hero` | Hero section | `hero.title`, `hero.subtitle` |
| `features` | Features section | `features.title`, `features.card1-title` |
| `pricing` | Pricing section | `pricing.title`, `pricing.monthly` |
| `cta` | Call to action blocks | `cta.title`, `cta.button` |
| `footer` | Footer content | `footer.copyright`, `footer.links-title` |
| `common` | Shared across pages | `common.cta`, `common.learn-more` |
| `a11y` | Accessibility labels | `a11y.menu-toggle`, `a11y.close-modal` |

## Adding Keys for a Component

When adding translations for a component:

1. **Identify all user-visible text** in the component (labels, headings, descriptions, aria-labels, alt text)
2. **Create keys** following the naming convention
3. **Add to both languages** in `ui.ts`
4. **Update the component** to use `t()` instead of hardcoded strings

### Example: Adding keys for a PricingCard

```typescript
// Add to ui.ts
es: {
  // ... existing keys
  "pricing.card-title": "Plan Pro",
  "pricing.card-price-monthly": "29€/mes",
  "pricing.card-price-annual": "24€/mes",
  "pricing.card-cta": "Elegir plan",
  "pricing.card-feature1": "Usuarios ilimitados",
},
en: {
  // ... existing keys
  "pricing.card-title": "Pro Plan",
  "pricing.card-price-monthly": "€29/month",
  "pricing.card-price-annual": "€24/month",
  "pricing.card-cta": "Choose plan",
  "pricing.card-feature1": "Unlimited users",
},
```

### Using in Astro Component

```astro
---
import { getLangFromUrl, useTranslations } from "../i18n/utils";

const lang = getLangFromUrl(Astro.url);
const t = useTranslations(lang);
---

<h3>{t("pricing.card-title")}</h3>
<span>{t("pricing.card-price-monthly")}</span>
<a href="/signup/">{t("pricing.card-cta")}</a>
```

## Rules

1. **Never hardcode user-visible text** — always use `t()` helper
2. **Both languages required** — add keys to `es` and `en` simultaneously
3. **Spanish is default** — `es` keys are the fallback
4. **`aria-label` and `alt` text must be translated** too (use `a11y.*` scope)
5. **Keep keys sorted** by scope within each language block
6. **Use kebab-case** for multi-word keys: `hero.sub-title`, not `hero.subTitle`
