---
name: new-entity
description: Scaffold a complete domain entity across all hexagonal architecture layers (domain, application, infrastructure). Use this skill whenever the user asks to add a new entity, model, resource, or domain object to a project that follows hexagonal (ports & adapters) or clean architecture — even if they just say "add a User entity" or "create the Order model". Triggers on: "new entity", "scaffold entity", "add model", "create domain object", "new resource", "add [EntityName] to the project".
user-invocable: false
---

# New Entity Scaffolding Skill

Scaffold a complete domain entity across all hexagonal architecture layers. This skill is architecture-first and project-agnostic — it guides you through discovery of existing patterns before generating anything.

## Arguments

**Required:**

- **entity name** — singular PascalCase (e.g., `Order`, `Customer`, `Invoice`)

**Optional:**

- **fields** — comma-separated field definitions (e.g., `name:str, created_at:datetime, amount:float`)
- **relations** — related entities (e.g., `belongs_to:User, has_many:LineItem`)

If fields are not provided, ask the user to describe the entity and its purpose before proceeding.

---

## Pre-Flight Checks (Always Run First)

Before generating any files, read the existing codebase to extract the exact patterns in use. Never assume — always discover.

### 1. Discover project structure

```
ls {project_root}/src/{package}/
```

Identify the layers present (e.g., `domain/`, `application/`, `infrastructure/`, `adapters/`). Note the naming convention used.

### 2. Identify an existing reference entity

Pick one well-established entity already in the codebase (ideally not the simplest or most complex one). Use it as the pattern source for everything below.

### 3. Read base classes

- **Domain base entity**: e.g., `domain/entities/base.py`
- **Infrastructure base model**: e.g., `infrastructure/persistence/models/base.py`
- **Any shared interfaces or mixins** visible in the reference entity

### 4. Read the reference entity across all layers

For the chosen reference entity, read:

- Domain entity class
- Domain exceptions
- Repository interface
- Application DTO(s)
- Application service
- Infrastructure ORM model
- Repository implementation
- API schema(s)
- Route handler(s)

### 5. Identify wiring files

- Dependency injection / service factory file
- Route registration file
- Exception handler registration file
- Alembic/migration env file (if applicable)
- Model registry / `__init__.py` (if applicable)

Document what you found before generating anything. Show a short summary to the user:
> "I found the following pattern based on `{ReferenceEntity}`. Proceeding with this template..."

---

## Files to Generate

Generate files in layer order: domain → application → infrastructure → wiring.

Use the reference entity's exact import paths, naming conventions, and code style as the template. Adapt the layer structure if the project uses different names (e.g., `adapters/` instead of `infrastructure/`).

---

### Layer 1: Domain

> No upward imports allowed. Domain is the innermost layer.

#### 1.1 Domain Entity — `domain/entities/{snake_name}.py`

- Inherit from the discovered `BaseEntity`
- Private backing fields (`self._{field}`), public read-only `@property` accessors
- Static validators (`_validate_{field}`) that raise domain exceptions
- Business methods that call `self._mark_updated()` (or equivalent) after mutations
- Constructor supports optional `entity_id`, `created_at`, `updated_at` for DB reconstruction

#### 1.2 Domain Exceptions — `domain/exceptions/{snake_name}_exceptions.py`

- Base: `{Entity}Exception(Exception)`
- Specifics: `{Entity}NotFoundException`, `Invalid{Entity}DataException`, `Duplicate{Entity}Exception`
- Each with a descriptive default message in `__init__`

#### 1.3 Repository Interface — `domain/repositories/{snake_name}_repository.py`

- ABC with `@abstractmethod` async methods
- Standard: `save()`, `find_by_id(id)`, `find_all(skip, limit, **filters)`, `delete(id) -> bool`, `count(**filters) -> int`
- Add entity-specific finders for unique or frequently-queried fields

---

### Layer 2: Application

> Imports only from the domain layer.

#### 2.1 DTOs — `application/dtos/{snake_name}_dtos.py`

Match the DTO style used in the project (dataclasses, Pydantic, TypedDict, etc.). Typically:

- `Create{Entity}DTO` — all required fields
- `Update{Entity}DTO` — all fields optional, for partial updates
- `{Entity}ResponseDTO` — includes `id`, `created_at`, `updated_at`; FK fields appear as both raw ID and optional nested DTO

#### 2.2 Application Service — `application/services/{snake_name}_service.py`

- Inject all repository interfaces via `__init__`
- CRUD methods: `create_{entity}`, `get_{entity}`, `list_{entities}`, `update_{entity}`, `delete_{entity}`
- Private `_to_response_dto(entity)` helper for mapping domain → DTO
- Raise domain exceptions; do not catch them here (handled centrally)

---

### Layer 3: Infrastructure

> Imports from domain + application. Adapters to external systems.

#### 3.1 ORM Model — `infrastructure/persistence/models/{snake_name}_model.py`

Match the ORM in use (SQLAlchemy, SQLModel, Tortoise, etc.):

- Inherit from discovered `BaseModel`
- `__tablename__` = plural snake_case (e.g., `orders`)
- Columns use the project's existing type + annotation style
- FK columns follow existing cascade/ondelete patterns
- Enum columns follow existing enum strategy (DB-level or string)
- Relationships declared with `TYPE_CHECKING` guards to avoid circular imports
- All columns include a `comment=` or docstring

#### 3.2 Repository Implementation — `infrastructure/persistence/repositories/{snake_name}_repository_impl.py`

- Implements the domain repository interface
- Constructor takes only the session/connection object
- Three private mappers:
  - `_to_domain(model) -> Entity`
  - `_to_model(entity) -> Model`
  - `_update_model_from_entity(model, entity)` (mutates existing model in-place)
- `save()` detects insert vs. update, ends with flush + refresh

#### 3.3 API Schemas — `infrastructure/api/schemas/{snake_name}_schemas.py`

Match the validation library in use (Pydantic, marshmallow, etc.):

- `{Entity}Create` — input validation with constraints and examples
- `{Entity}Update` — all fields optional
- `{Entity}Response` — `from_attributes = True`, nested response schemas for relations

#### 3.4 Route Handler — `infrastructure/api/routes/{snake_name}s.py`

- Router prefix: `/api/v1/{plural_snake_name}`, tags: `["{Entity}s"]`
- All routes inject `db` session via dependency, then call a service factory
- Auth guards: write routes require elevated auth, read routes require basic auth (follow existing pattern)
- No try/except — exceptions are caught centrally
- DELETE returns 204; 404 if the entity was not found

---

## Post-Generation Wiring

After files are created, update the following (adapt paths to the actual project):

### W1 — Register ORM model for migrations

- Add import to `alembic/env.py` (or equivalent migration config)
- Add to `infrastructure/persistence/models/__init__.py` and `__all__`

### W2 — Add dependency injection factory

- In the DI / dependencies file, add `get_{snake_name}_service(db) -> {Entity}Service`
- Import the new repository impl and service

### W3 — Register routes

- In the main router file, import and include the new router

### W4 — Register exception handlers

- In the exception handler file, add:
  - `{Entity}NotFoundException` → HTTP 404
  - `Invalid{Entity}DataException` → HTTP 400
  - `Duplicate{Entity}Exception` → HTTP 409

---

## Post-Wiring Verification

1. **Generate migration** (if applicable):

   ```bash
   alembic revision --autogenerate -m "add {snake_name} table"
   ```

   Review the generated file — confirm it only adds the expected table/columns.

2. **Apply migration**:

   ```bash
   alembic upgrade head
   ```

3. **Run test suite**:

   ```bash
   pytest   # or the project's test runner
   ```

4. **Present a summary** of all created and modified files with a brief description of each.

---

## Output Summary Template

After generation, present:

```
✅ Created:
  domain/entities/{snake_name}.py
  domain/exceptions/{snake_name}_exceptions.py
  domain/repositories/{snake_name}_repository.py
  application/dtos/{snake_name}_dtos.py
  application/services/{snake_name}_service.py
  infrastructure/persistence/models/{snake_name}_model.py
  infrastructure/persistence/repositories/{snake_name}_repository_impl.py
  infrastructure/api/schemas/{snake_name}_schemas.py
  infrastructure/api/routes/{snake_name}s.py

✏️ Modified:
  alembic/env.py
  infrastructure/persistence/models/__init__.py
  infrastructure/api/dependencies.py
  infrastructure/api/router.py
  infrastructure/api/exception_handlers.py

🗄️ Migration: migrations/versions/xxxx_add_{snake_name}_table.py
```
