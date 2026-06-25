---
name: hexagonal-architecture
description: Hexagonal architecture rules, layer boundaries, and code patterns for Python APIs using FastAPI, SQLAlchemy, and Pydantic.
user-invocable: false
---

# Hexagonal Architecture Rules

You MUST follow these rules when writing or modifying any code in a project using hexagonal (ports & adapters) architecture.

## Layer Structure

Dependencies point **inward only**: Infrastructure → Application → Domain.

```txt
Infrastructure (Adapters)  →  Application (Use Cases)  →  Domain (Core)
FastAPI, SQLAlchemy, Pydantic    Services, DTOs              Entities, VOs, Ports
```

---

## Domain Layer — `src/{package}/domain/`

**Contains:** Entities, Value Objects, Repository Interfaces (Ports), Domain Exceptions.

**Import Rules:**

- NO imports from `application` or `infrastructure`
- NO framework dependencies (FastAPI, SQLAlchemy, Pydantic)
- Pure Python business logic only

**Patterns:**

- Entities inherit from `BaseEntity`; use private fields `self._{field}` with read-only `@property` accessors
- Field validators are `@staticmethod _validate_{field}(value)` — raise domain exceptions on failure
- Business methods call `self._mark_updated()` after any state change
- Repository interfaces are abstract base classes with `@abstractmethod async` methods (Ports)
- Domain exceptions are the **only** error vocabulary that crosses layer boundaries

**Example:**

```python
class Athlete(BaseEntity):
    def __init__(self, name: str, email: str):
        self._name = self._validate_name(name)
        self._email = self._validate_email(email)

    @property
    def name(self) -> str:
        return self._name

    @staticmethod
    def _validate_name(value: str) -> str:
        if not value or not value.strip():
            raise InvalidAthleteNameError("Name cannot be empty")
        return value.strip()

    def update_name(self, name: str) -> None:
        self._name = self._validate_name(name)
        self._mark_updated()
```

---

## Application Layer — `src/{package}/application/`

**Contains:** Services (orchestrators), DTOs (dataclasses).

**Import Rules:**

- CAN import from `domain`
- Depends on repository **interfaces** (Ports), never implementations
- NO framework-specific code (no HTTP, no database, no Pydantic)

**Patterns:**

- Services receive repository interfaces via `__init__` (constructor injection)
- DTOs are `@dataclass` (NOT Pydantic): `Create{Entity}DTO`, `Update{Entity}DTO`, `{Entity}ResponseDTO`
- Services: receive DTO → create/mutate domain entity → persist via repository interface → return ResponseDTO
- Cross-entity constraint validation (e.g., uniqueness checks) happens in the service, before domain operations
- Services raise domain exceptions — they do NOT catch them

**Example:**

```python
@dataclass
class CreateAthleteDTO:
    name: str
    email: str

@dataclass
class AthleteResponseDTO:
    id: str
    name: str
    email: str

class AthleteService:
    def __init__(self, repo: AthleteRepositoryInterface) -> None:
        self._repo = repo

    async def create(self, dto: CreateAthleteDTO) -> AthleteResponseDTO:
        if await self._repo.find_by_email(dto.email):
            raise AthleteEmailAlreadyExistsError(dto.email)
        athlete = Athlete(name=dto.name, email=dto.email)
        await self._repo.save(athlete)
        return AthleteResponseDTO(id=str(athlete.id), name=athlete.name, email=athlete.email)
```

---

## Infrastructure Layer — `src/{package}/infrastructure/`

**Contains:** FastAPI routes, Pydantic schemas, SQLAlchemy models, repository implementations.

**Import Rules:**

- CAN import from `domain` and `application`
- Framework-specific code lives exclusively here
- Implements domain interfaces (Adapters)

**Patterns:**

- Repository implementations: `Postgres{Entity}Repository({Entity}RepositoryInterface)`
- Constructor takes `AsyncSession` only
- Three mapping methods per repository: `_to_domain(model)`, `_to_model(entity)`, `_update_model_from_entity(model, entity)`
- Pydantic schemas: `{Entity}Create`, `{Entity}Update`, `{Entity}Response` with `model_config`
- Routes: `router = APIRouter(prefix="/api/v1/{plural}", tags=["{Entity}s"])`
- No `try/except` in routes — exceptions are handled centrally in `exception_handlers.py`
- DELETE endpoints return `204 No Content`

**Example:**

```python
class PostgresAthleteRepository(AthleteRepositoryInterface):
    def __init__(self, session: AsyncSession) -> None:
        self._session = session

    async def save(self, athlete: Athlete) -> None:
        model = self._to_model(athlete)
        self._session.add(model)
        await self._session.flush()

    def _to_domain(self, model: AthleteModel) -> Athlete:
        ...

    def _to_model(self, entity: Athlete) -> AthleteModel:
        ...
```

---

## Data Flow (Four Representations)

```
HTTP JSON → Pydantic Schema → DTO → Domain Entity → ORM Model → Database
            (validation)     (app   (business       (persistence
                             layer)  logic)          layer)
```

---

## Dependency Injection

Wired in `infrastructure/api/dependencies.py`:

```python
def get_{entity}_service(db: AsyncSession = Depends(get_db)) -> {Entity}Service:
    repo = Postgres{Entity}Repository(db)
    return {Entity}Service(repo)
```

In routes:

```python
service: {Entity}Service = Depends(get_{entity}_service)
```

---

## Anti-Patterns — These Must Never Occur

- Domain layer importing from `application` or `infrastructure`
- `from fastapi` / `from sqlalchemy` / `from pydantic` anywhere in the domain layer
- Services depending on repository **implementations** (only interfaces/ports)
- Business logic placed in services (it belongs in domain entities)
- Pydantic schemas passed directly to services (always convert to DTOs first)
- Catching domain exceptions in services (let them propagate to the infrastructure exception handler)
