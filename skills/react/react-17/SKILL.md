---
name: react-17
description: >
  React 17 patterns without React Compiler.
  Trigger: When writing React 17 components/hooks in .tsx/.jsx (manual memoization, forwardRef, class components, hook patterns). Use this skill whenever the user mentions React 17, legacy React, or is working in a project without the React Compiler — even if they don't explicitly ask for "React 17 patterns".
metadata:
  auto_invoke: "Writing React 17 components or hooks"
allowed-tools: Read, Edit, Write, Glob, Grep, Bash, WebFetch, WebSearch, Task
user-invocable: false
---

# React skill

## Imports (REQUIRED)

```typescript
// ✅ Named imports — preferred with new JSX transform (React 17+)
import { useState, useEffect, useRef, useCallback, useMemo } from "react";

// ✅ Also acceptable — required if JSX transform is NOT configured
import React, { useState, useEffect } from "react";

// ❌ NEVER: Wildcard import
import * as React from "react";
```

> React 17 introduced the new JSX transform, so `import React` is no longer
> required for JSX — but confirm the project's tsconfig/babel config before omitting it.

---

## Manual Memoization (REQUIRED — no compiler)

React 17 has no React Compiler. Optimize renders explicitly.

```typescript
// ✅ Memoize expensive derived values
function ProductList({ products, filterTerm }: Props) {
  const filtered = useMemo(
    () => products.filter((p) => p.name.includes(filterTerm)),
    [products, filterTerm]
  );

  // ✅ Stable callback reference to prevent child re-renders
  const handleSelect = useCallback(
    (id: string) => {
      console.log("selected", id);
    },
    [] // no deps — stable forever
  );

  return <List items={filtered} onSelect={handleSelect} />;
}

// ✅ Memoize child components that receive stable props
const List = React.memo(function List({ items, onSelect }: ListProps) {
  return (
    <ul>
      {items.map((item) => (
        <li key={item.id} onClick={() => onSelect(item.id)}>
          {item.name}
        </li>
      ))}
    </ul>
  );
});
```

**Rules of thumb:**

- `useMemo` → expensive computations or referentially stable objects/arrays passed as props
- `useCallback` → functions passed as props to memoized children or used in `useEffect` deps
- `React.memo` → pure components with stable props; always pair with `useCallback`/`useMemo` on the parent

---

## forwardRef (REQUIRED for ref forwarding)

```typescript
// ✅ React 17: forwardRef is the only way to forward refs
import { forwardRef, useRef } from "react";

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  label: string;
}

const LabeledInput = forwardRef<HTMLInputElement, InputProps>(
  ({ label, ...props }, ref) => (
    <label>
      {label}
      <input ref={ref} {...props} />
    </label>
  )
);

LabeledInput.displayName = "LabeledInput";

// Usage
function Form() {
  const inputRef = useRef<HTMLInputElement>(null);
  return <LabeledInput ref={inputRef} label="Name" />;
}

// ❌ NEVER: passing ref as a regular prop (breaks silently in React 17)
function BadInput({ ref, ...props }) { ... }
```

---

## useEffect Patterns

```typescript
// ✅ Cleanup subscriptions and timers
useEffect(() => {
  const sub = eventBus.subscribe("update", handleUpdate);
  return () => sub.unsubscribe();
}, [handleUpdate]); // handleUpdate must be stable (useCallback)

// ✅ Async inside effect — avoid returning promises
useEffect(() => {
  let cancelled = false;

  async function load() {
    const data = await fetchData(id);
    if (!cancelled) setData(data);
  }

  load();
  return () => { cancelled = true; };
}, [id]);

// ❌ NEVER: async effect directly
useEffect(async () => { ... }, []); // returns a Promise, not a cleanup fn
```

---

## Context

```typescript
// ✅ Typed context with a default value guard
interface ThemeContextValue {
  theme: "light" | "dark";
  toggle: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) throw new Error("useTheme must be used within ThemeProvider");
  return ctx;
}

// ✅ Memoize context value to prevent unnecessary re-renders
export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<"light" | "dark">("light");
  const toggle = useCallback(() => setTheme((t) => (t === "light" ? "dark" : "light")), []);
  const value = useMemo(() => ({ theme, toggle }), [theme, toggle]);

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}
```

---

## Custom Hooks

```typescript
// ✅ Encapsulate stateful logic; prefix with "use"
function useDebouncedValue<T>(value: T, delayMs: number): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(timer);
  }, [value, delayMs]);

  return debounced;
}
```

---

## Component Patterns

### Functional Components (preferred)

```typescript
// ✅ Typed props interface; explicit return type optional but recommended
interface CardProps {
  title: string;
  children: React.ReactNode;
  onDismiss?: () => void;
}

export function Card({ title, children, onDismiss }: CardProps) {
  return (
    <div className="card">
      <h2>{title}</h2>
      {children}
      {onDismiss && <button onClick={onDismiss}>✕</button>}
    </div>
  );
}
```

### Class Components (legacy — avoid unless required)

```typescript
// ✅ Only use for error boundaries (no hook equivalent in React 17)
class ErrorBoundary extends React.Component<
  { fallback: React.ReactNode; children: React.ReactNode },
  { hasError: boolean }
> {
  state = { hasError: false };

  static getDerivedStateFromError(): { hasError: boolean } {
    return { hasError: true };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error(error, info);
  }

  render() {
    return this.state.hasError ? this.props.fallback : this.props.children;
  }
}
```

---

## Key Differences vs React 19

| Feature           | React 17                                        | React 19                   |
| ----------------- | ----------------------------------------------- | -------------------------- |
| Memoization       | Manual (`useMemo`, `useCallback`, `React.memo`) | Automatic (React Compiler) |
| Ref forwarding    | `forwardRef()` required                         | `ref` as plain prop        |
| Server Components | ❌ Not available                                | ✅ Default                 |
| `use()` hook      | ❌ Not available                                | ✅ Available               |
| `useActionState`  | ❌ Not available                                | ✅ Available               |
| `import React`    | Required without new JSX transform              | Never needed               |
