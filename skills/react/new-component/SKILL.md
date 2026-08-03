---
name: new-component
description: >
  Scaffold all artifacts for a new React component in the trunk module:
  component file, test file, index.js barrel, and optional styled.js.
  Updates the parent index.js to export the new component.
  Invoke when creating a new component or page.
allowed-tools: Read, Edit, Write, Glob, Grep, Bash
user-invocable: true
---

# new-component

Scaffold all required files for a new React component in the **trunk** module, following
project conventions. This skill is action-oriented — it creates files.

---

## Step 1 — Gather inputs

Ask the user for (or infer from context):

1. **Component name** — PascalCase (e.g. `SiteStatusBadge`)
2. **Target directory** — `src/components/` (default) or `src/pages/`
3. **Props** — list of `(name, type, required, description)` tuples
4. **Purpose** — one-line description for JSDoc

---

## Step 2 — Create the directory structure

```
<target>/<ComponentName>/
├── ComponentName.jsx        ← main component (Step 3)
├── ComponentName.test.jsx   ← co-located test (Step 4)
└── index.js                 ← barrel export (Step 5)
```

---

## Step 3 — Write `ComponentName.jsx`

Use this template, filling in the component-specific values:

```javascript
import { useCustomTranslation } from '#trunk/hooks';

/**
 * <purpose>.
 * @param {Object} props - Component props.
 * @param {<type>} props.<name> - <description>.
 * @returns {React.JSX.Element} <ComponentName>.
 */
const <ComponentName> = ({ <props> }) => {
    const { t } = useCustomTranslation();

    return (
        <div data-testid="<kebab-case-component-name>">
            {/* TODO: implement */}
        </div>
    );
};

export default <ComponentName>;
```

**Rules:**
- JSDoc `@param` for every prop
- `data-testid` on the root element (kebab-case of component name)
- No inline styles
- Import aliases only (`#trunk/*`)
- React Hook Form for any form logic

---

## Step 4 — Write `ComponentName.test.jsx`

Use the `gen-test` skill to generate the test, or follow this minimal template:

```javascript
import { render, screen } from '@testing-library/react';

import <ComponentName> from './<ComponentName>';

describe('<ComponentName>', () => {
    beforeEach(() => {
        jest.clearAllMocks();
    });

    it('should render correctly', () => {
        render(<<ComponentName> />);

        expect(screen.getByTestId('<kebab-case-component-name>')).toBeInTheDocument();
    });
});
```

---

## Step 5 — Write `index.js`

```javascript
export { default } from './<ComponentName>';
```

---

## Step 6 — Update the parent `index.js`

Find the nearest parent `index.js` and add the new export:

```javascript
// Before (example)
export { OtherComponent } from './OtherComponent';

// After
export { OtherComponent } from './OtherComponent';
export { default as <ComponentName> } from './<ComponentName>';
```

Keep exports **alphabetically sorted**.

---

## Step 7 — Verify

After creating files, confirm:
- [ ] `ComponentName.jsx` exists with JSDoc + `data-testid`
- [ ] `ComponentName.test.jsx` exists with at least one `it()` block
- [ ] `index.js` exports the component
- [ ] Parent `index.js` includes the new export
- [ ] No relative path imports (only `#trunk/*` aliases)
- [ ] No inline styles

---

## Reference implementations

- `src/components/WarningMessages/components/PhoneNumberWarningMessage/` — Alert with permission check
- `src/components/WarningMessages/components/NumberRemovedWarningMessage/` — Closable alert with placeholders
- `src/components/InformationMessages/` — Standard information message component
