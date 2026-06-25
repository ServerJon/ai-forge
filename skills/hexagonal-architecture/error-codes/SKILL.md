---
name: error-codes
description: >
  API error code registry and error handling conventions for hexagonal architecture projects.
  Use this skill whenever creating or modifying: API error responses, domain exceptions,
  port/adapter error contracts, frontend error handling, HTTP exception mappers, i18n error
  keys, or any layer that produces or consumes structured error envelopes. Trigger on phrases
  like "add error code", "handle this error", "map exception", "error response", "domain exception",
  "error translation", or when scaffolding a new domain entity that will need its own error codes.
user-invocable: false
---

# API Error Codes — Hexagonal Architecture Convention

This skill governs how errors are defined, propagated, and presented across all layers of a
hexagonal (ports & adapters) architecture. Follow these conventions strictly when adding or
modifying any error-related code.

---

## Architecture Layer Responsibilities

| Layer | Responsibility |
|---|---|
| **Domain** | Raise typed `DomainException` subclasses with a stable `code` |
| **Application** | Catch domain exceptions; translate to port output models |
| **Primary Adapter (HTTP)** | Map application errors → HTTP status + `ApiErrorResponse` envelope |
| **Secondary Adapter** | Wrap infrastructure errors → domain or application exceptions |
| **Frontend / Client** | Translate `error.code` via i18n; never display `error.message` raw |

---

## Error Response Envelope

All HTTP error responses use this consistent JSON shape:

```json
{
  "error": {
    "code": "ENTITY_REASON",
    "message": "Human-readable English fallback (never shown directly to users)",
    "details": { "context_key": "value" },
    "timestamp": "2024-01-15T10:30:00Z",
    "path": "/api/v1/resource"
  }
}
```

| Field | Type | Notes |
|---|---|---|
| `code` | `string` | Machine-readable; used as i18n key (`errors.ENTITY_REASON`) |
| `message` | `string` | English fallback; logged, never surfaced to end users |
| `details` | `object \| null` | Interpolation values for i18n; nullable |
| `timestamp` | `ISO 8601` | Set automatically by the exception mapper |
| `path` | `string` | Request path; set automatically by the exception mapper |

---

## Error Code Naming Convention

```
{ENTITY}_{REASON}   — UPPER_SNAKE_CASE
```

**Rules:**

- `ENTITY` = the domain noun (e.g., `USER`, `ORDER`, `PRODUCT`, `PAYMENT`)
- `REASON` = what went wrong (e.g., `NOT_FOUND`, `DUPLICATE_EMAIL`, `INVALID_DATA`)
- System/cross-cutting codes use descriptive prefixes: `AUTH_`, `VALIDATION_`, `EMAIL_`

**Examples:**

```
USER_NOT_FOUND
ORDER_DUPLICATE_REFERENCE
PRODUCT_INVALID_CATEGORY
AUTH_EXPIRED_TOKEN
VALIDATION_ERROR
INTERNAL_SERVER_ERROR
```

---

## Domain Exception Hierarchy

Define a base exception in the domain layer. All domain-specific errors extend it.

```python
# domain/exceptions.py

class DomainException(Exception):
    """Base for all domain exceptions. Carries a stable error code."""

    def __init__(self, code: str, message: str, details: dict | None = None):
        self.code = code
        self.message = message
        self.details = details
        super().__init__(message)


class EntityNotFoundException(DomainException):
    """Raised when a requested entity does not exist."""


class DuplicateEntityException(DomainException):
    """Raised when a uniqueness constraint is violated."""


class InvalidOperationException(DomainException):
    """Raised when a business rule disallows the requested operation."""
```

Concrete domain exceptions are thin wrappers that fix the `code` and `details` shape:

```python
# domain/user/exceptions.py

from domain.exceptions import EntityNotFoundException, DuplicateEntityException

class UserNotFoundException(EntityNotFoundException):
    def __init__(self, user_id: str):
        super().__init__(
            code="USER_NOT_FOUND",
            message=f"User '{user_id}' not found.",
            details={"user_id": user_id},
        )

class UserDuplicateEmailException(DuplicateEntityException):
    def __init__(self, email: str):
        super().__init__(
            code="USER_DUPLICATE_EMAIL",
            message=f"Email '{email}' is already registered.",
            details={"email": email},
        )
```

---

## HTTP Exception Mapper (Primary Adapter)

A single mapper translates domain exceptions → HTTP responses. Add new mappings here only.

```python
# adapters/primary/http/exception_mapper.py

from domain.exceptions import (
    EntityNotFoundException,
    DuplicateEntityException,
    InvalidOperationException,
)

DOMAIN_TO_HTTP: dict[type, int] = {
    EntityNotFoundException: 404,
    DuplicateEntityException: 409,
    InvalidOperationException: 400,
}

def domain_exception_to_status(exc: DomainException) -> int:
    for exc_type, status in DOMAIN_TO_HTTP.items():
        if isinstance(exc, exc_type):
            return status
    return 500
```

---

## Error Code Registry

Add all project error codes here. Group by domain entity.

### Authentication

| Code | HTTP | When | Details |
|---|---|---|---|
| `AUTH_INVALID_CREDENTIALS` | 401 | Wrong credentials | `null` |
| `AUTH_EMAIL_NOT_VERIFIED` | 403 | Unverified email | `{ email }` |
| `AUTH_INVALID_TOKEN` | 401 | Malformed token | `null` |
| `AUTH_EXPIRED_TOKEN` | 401 | Expired token | `null` |
| `AUTH_UNAUTHORIZED` | 401 | No token provided | `null` |
| `AUTH_INSUFFICIENT_PERMISSIONS` | 403 | Missing permission | `{ required_permission? }` |

### Validation

| Code | HTTP | When | Details |
|---|---|---|---|
| `VALIDATION_ERROR` | 422 | Schema/input validation fails | `{ errors: [{ field, code, message, type? }] }` |
| `FIELD_REQUIRED` | — | Used inside `errors[]` details | — |
| `INVALID_EMAIL_FORMAT` | — | Used inside `errors[]` details | — |
| `INVALID_UUID_FORMAT` | — | Used inside `errors[]` details | — |

### Email / Messaging

| Code | HTTP | When | Details |
|---|---|---|---|
| `EMAIL_SEND_FAILED` | 503 | Provider API error | `{ recipient? }` |
| `EMAIL_INVALID_DATA` | 400 | Malformed payload | `{ field? }` |

### System

| Code | HTTP | When | Details |
|---|---|---|---|
| `INTERNAL_SERVER_ERROR` | 500 | Unhandled exception | `{ exception_type?, exception_message? }` (dev only) |
| `DATABASE_ERROR` | 500 | DB operation fails | `null` |
| `SERVICE_UNAVAILABLE` | 503 | Service down / overloaded | `null` |

> **Add domain-specific tables below this line, one table per entity.**
> Example: `### User`, `### Order`, `### Product`

---

## Frontend / Client Error Handling Rules

1. **Always translate via code** — use `t(\`errors.${error.code}\`, error.details)`
2. **Never display `error.message` directly** — it's an English fallback for logs only
3. **Always provide a fallback** — `t(\`errors.${error.code}\`, { defaultValue: error.message, ...error.details })`
4. **Handle `VALIDATION_ERROR` specially** — iterate `error.details.errors[]` and set per-field errors
5. **TypeScript types:**

```ts
interface ApiError {
  code: string;
  message: string;
  details?: Record<string, unknown> | null;
  timestamp: string;
  path: string;
}

interface ApiErrorResponse {
  error: ApiError;
}

interface ValidationFieldError {
  field: string;
  code: string;
  message: string;
  type?: string;
}
```

---

## i18n Key Convention

Every error code must have a corresponding key in **all supported locale files**:

```json
// locales/en.json
{
  "errors": {
    "USER_NOT_FOUND": "User not found.",
    "USER_DUPLICATE_EMAIL": "The email '{{email}}' is already registered.",
    "AUTH_EXPIRED_TOKEN": "Your session has expired. Please sign in again.",
    "VALIDATION_ERROR": "Please correct the errors below.",
    "INTERNAL_SERVER_ERROR": "An unexpected error occurred. Please try again."
  }
}
```

Use `{{key}}` (or your i18n library's syntax) matching the `details` field keys.

---

## Adding a New Error Code — Checklist

1. [ ] Name follows `{ENTITY}_{REASON}` in UPPER_SNAKE_CASE
2. [ ] Correct HTTP status chosen (400 / 401 / 403 / 404 / 409 / 422 / 500 / 503)
3. [ ] `details` shape defined (or `null`)
4. [ ] Concrete `DomainException` subclass created in the domain layer
5. [ ] HTTP status mapped in `exception_mapper.py` (if new base type)
6. [ ] Entry added to the **Error Code Registry** table in this file
7. [ ] i18n keys added to **all** locale files
8. [ ] Frontend type definitions updated if `details` shape is non-trivial

---

## Secondary Adapter Error Wrapping

Infrastructure errors (DB, HTTP clients, file I/O) must never leak into the domain. Wrap them:

```python
# adapters/secondary/persistence/user_repository.py

from domain.exceptions import DomainException

class SqlUserRepository(UserRepository):
    def find_by_id(self, user_id: str) -> User:
        try:
            return self._session.get(UserModel, user_id)
        except SQLAlchemyError as exc:
            raise DomainException(
                code="DATABASE_ERROR",
                message="A database error occurred.",
            ) from exc
```

**Rule:** Secondary adapters catch infrastructure exceptions and re-raise as `DomainException`
(or a subclass). They never raise HTTP-level or framework-specific errors.
