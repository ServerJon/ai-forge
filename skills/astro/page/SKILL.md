---
name: page
description: Scaffold a new Astro page with Layout, SEO meta, Section structure, and i18n support
user-invocable: true
---

# Page

Scaffold a new Astro page following project conventions.

## Usage

```
/page pricing
/page about --no-i18n
```

- **name**: kebab-case page name — creates `src/pages/{name}.astro`
- **--no-i18n**: Skip i18n setup in the page

## Generated File

### `src/pages/{name}.astro`

```astro
---
import Layout from "../layouts/Layout.astro";
import Section from "../components/ui-kit/Section.astro";
import SectionHeader from "../components/ui-kit/SectionHeader.astro";
import { getLangFromUrl, useTranslations } from "../i18n/utils";

const lang = getLangFromUrl(Astro.url);
const t = useTranslations(lang);
---

<Layout
  title={t("{name}.meta-title")}
  description={t("{name}.meta-description")}
>
  <Section bg="primary">
    <SectionHeader
      title={t("{name}.hero-title")}
      description={t("{name}.hero-description")}
    />

    <!-- Page content here -->
  </Section>
</Layout>
```

## Page Structure Rules

### Layout Wrapper

Every page MUST be wrapped in `<Layout>` with SEO props:

```astro
<Layout
  title="Page Title — Wesog"
  description="Concise description for search engines (under 160 chars)"
>
  <!-- page content -->
</Layout>
```

### Section Composition

Pages are composed of `<Section>` blocks that alternate backgrounds:

```astro
<Section bg="primary">     <!-- var(--fp-bg) background -->
  <SectionHeader title="..." />
  <!-- content -->
</Section>

<Section bg="secondary">   <!-- var(--fp-surface) background -->
  <SectionHeader title="..." />
  <!-- content -->
</Section>

<Section bg="primary" borderTop>  <!-- with top border -->
  <!-- content -->
</Section>
```

### SEO Checklist

Every page must have:

- [ ] `<Layout title="..." description="...">` with unique title and description
- [ ] Semantic heading hierarchy (`<h1>` once, then `<h2>`, `<h3>`)
- [ ] Meaningful content in the first `<Section>` (hero/intro)
- [ ] All images with `alt` attributes
- [ ] All interactive elements keyboard-accessible

### i18n Integration

If i18n is enabled (default):

1. Import `getLangFromUrl` and `useTranslations` in frontmatter
2. Use `t()` for all user-visible strings
3. Add the page's translation keys to `src/i18n/ui.ts`:

```typescript
// Minimum keys for a new page:
"{name}.meta-title": "...",
"{name}.meta-description": "...",
"{name}.hero-title": "...",
"{name}.hero-description": "...",
```

### File Naming

- **kebab-case** for page files: `pricing.astro`, `about-us.astro`
- Becomes route: `/pricing/`, `/about-us/` (with `trailingSlash: "always"`)
- For dynamic routes: `[slug].astro`, `[...path].astro`

## Template Variants

### Simple Content Page (about, legal, privacy)

```astro
---
import Layout from "../layouts/Layout.astro";
import Section from "../components/ui-kit/Section.astro";
---

<Layout title="About — Wesog" description="Learn about Wesog">
  <Section bg="primary">
    <div class="content">
      <h1>About Wesog</h1>
      <p>Content here...</p>
    </div>
  </Section>
</Layout>

<style>
  .content {
    max-width: var(--fp-container-max);
    margin-inline: auto;
    padding-inline: var(--fp-container-padding);
  }
  h1 {
    font-size: var(--fp-text-3xl);
    font-weight: var(--fp-font-semibold);
    color: var(--fp-text);
  }
  p {
    font-size: var(--fp-text-md);
    color: var(--fp-muted);
    line-height: var(--fp-leading-relaxed);
  }
</style>
```

### Multi-Section Landing Page (features, pricing)

```astro
---
import Layout from "../layouts/Layout.astro";
import Section from "../components/ui-kit/Section.astro";
import SectionHeader from "../components/ui-kit/SectionHeader.astro";
---

<Layout title="Features — Wesog" description="Explore Wesog features">
  <Section bg="primary">
    <SectionHeader
      title="Features"
      description="Everything you need to manage your team"
    />
    <!-- Feature grid -->
  </Section>

  <Section bg="secondary">
    <SectionHeader title="How it works" />
    <!-- Steps/timeline -->
  </Section>

  <Section bg="primary" borderTop>
    <SectionHeader title="Ready to start?" />
    <!-- CTA block -->
  </Section>
</Layout>
```
