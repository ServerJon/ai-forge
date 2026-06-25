---
name: hexagonal-testing
description: >
  Testing conventions, patterns, and test generation for any Python API built with hexagonal
  architecture. Use this skill whenever the user asks to write, generate, review, or audit tests
  in a hexagonal-architecture project — including unit tests for domain entities/value objects,
  application service tests with mocked repositories, or integration/endpoint tests. Also triggers
  when the user references test structure, coverage goals, AAA pattern, fixture organization,
  conftest.py, cov_annotate, missing lines, or asks about testing a specific entity, service,
  or endpoint. Also triggers when the user asks to measure, improve, or audit test coverage.
user-invocable: false
---

# Hexagonal Testing Skill

Generic testing conventions and test generation for Python APIs structured with hexagonal
(ports & adapters) architecture.

> **Project-specific details** (app package name, DB engine, test runner config) are read from
> `tests/conftest.py` and the source tree at invocation time. Do not hardcode project names.

---

## 1. Pre-Flight Checklist

Before writing or generating any test:

1. **Locate the test root** — scan for `tests/` or `test/` at the project root.
2. **Read `conftest.py`** — identify existing fixtures, DB setup, and async configuration.
3. **Read existing tests** in the relevant sub-directory to match style and conventions.
4. **Read the source file(s)** for the target to understand methods, rules, and edge cases.
5. **Identify the layer** (domain / application / infrastructure) to apply the right strategy.
6. **Confirm coverage tooling** — ensure `pytest-cov` is available; use `cov_annotate/` output (§6).

---

## 2. Directory Layout

```
tests/
├── conftest.py                     # Shared fixtures (session, client, mock repos)
├── unit/
│   ├── domain/                     # Entity + value object tests — NO I/O
│   └── application/                # Service tests — mocked repositories
└── integration/
    └── test_{entity}_endpoints.py  # Full request cycles with real DB
```

Adapt the structure to what already exists in the project.

---

## 3. Layer Strategy

### 3.1 Domain Layer (`tests/unit/domain/`)

| Goal          | Rule                                                              |
| ------------- | ----------------------------------------------------------------- |
| Zero I/O      | No DB, no network, no filesystem                                  |
| Full coverage | Target **100%** of domain methods                                 |
| Test scope    | Business methods, validation rules, state transitions, invariants |

```python
def test_grant_admin_sets_flag():
    # Arrange
    entity = MyEntity(name="Alice", role=Role.VIEWER)
    # Act
    entity.grant_admin()
    # Assert
    assert entity.is_admin is True
```

### 3.2 Application Layer (`tests/unit/application/`)

| Goal                | Rule                                               |
| ------------------- | -------------------------------------------------- |
| Isolated services   | Mock every port with `MagicMock(spec=<Port>)`      |
| Coverage target     | **90%+**                                           |
| Verify interactions | Assert repository methods called with correct args |

```python
def test_create_entity_calls_repository_save(mock_repo):
    # Arrange
    service = MyService(repository=mock_repo)
    # Act
    service.create(name="Alice")
    # Assert
    mock_repo.save.assert_called_once()
```

### 3.3 Infrastructure Layer (`tests/integration/`)

| Goal                | Rule                                                   |
| ------------------- | ------------------------------------------------------ |
| Real DB / transport | Use in-memory DB (SQLite) or test container            |
| Coverage target     | **80%+**                                               |
| Full cycles         | Create → Read → Update → Delete, including error paths |

See `references/integration-patterns.md` for async client setup and fixture patterns.

---

## 4. Universal Patterns

### AAA (Arrange-Act-Assert)

Every test follows this structure with blank-line separation and comments:

```python
def test_{action}_{expected_result}[_{condition}]():
    # Arrange
    ...
    # Act
    ...
    # Assert
    ...
```

### Naming Convention

```
test_{action}_{expected_result}[_{condition}]

# Good
test_create_raises_conflict_when_email_exists
test_grant_admin_sets_is_admin_flag
test_update_returns_404_when_entity_not_found

# Bad
test_create
test_role_change
```

### One Behavior Per Test

- Each test verifies **one behavior**.
- Multiple assertions on the _same result_ are acceptable.
- Multiple _actions_ in one test are not.

### Async Tests

- Mark every async test with `@pytest.mark.asyncio`.
- Use `pytest-asyncio` in `auto` mode if the project is fully async.

---

## 5. Fixture Guidelines

| Fixture type             | Scope                   | Location                           |
| ------------------------ | ----------------------- | ---------------------------------- |
| DB session / test client | `function` or `session` | `conftest.py`                      |
| Mock repository          | `function`              | `conftest.py` or test file         |
| Sample domain entity     | `function`              | `conftest.py` (if reused) or local |

- **Reuse** existing fixtures from `conftest.py` — don't duplicate.
- **Add** new fixtures to `conftest.py` only when they'll be used across multiple files.
- Mock repos: `MagicMock(spec=<EntityRepositoryInterface>)` — always use `spec=` to catch API drift.

---

## 6. Coverage Rules

> Coverage workflow adapted from [github/awesome-copilot](https://github.com/github/awesome-copilot)
> (MIT).

### 6.1 Layer Targets

Minimum **line coverage** per layer. When a layer target exceeds the global floor, use the layer
target.

| Layer            | Package path (typical)          | Line coverage target |
| ---------------- | ------------------------------- | -------------------- |
| Domain           | `src/<package>/domain/`         | **100%**             |
| Application      | `src/<package>/application/`    | **90%+**             |
| Infrastructure   | `src/<package>/infrastructure/` | **80%+**             |
| **Global floor** | entire `src/<package>`          | **90%+**             |

### 6.2 Generate a Coverage Report

Use the **annotate** reporter so uncovered lines are easy to find. Adapt the runner/package
manager to the project (poetry, pip, uv, etc.):

```bash
# When pyproject.toml / setup.cfg already defines the cov source
poetry run pytest --cov --cov-report=annotate:cov_annotate

# Full package — global floor check
poetry run pytest --cov=src/<package> --cov-report=annotate:cov_annotate

# Single layer or module
poetry run pytest --cov=src/<package>/domain --cov-report=annotate:cov_annotate
poetry run pytest --cov=src/<package>/application --cov-report=annotate:cov_annotate

# Scoped to one test file while iterating
poetry run pytest tests/unit/domain/test_foo.py \
  --cov=src/<package>/domain/foo.py \
  --cov-report=annotate:cov_annotate
```

### 6.3 Read the Annotated Report

1. Open the `cov_annotate/` directory — one annotated file per source file.
2. **Skip** files already at the layer target — 100% line coverage means every line is
   exercised; no need to open that file.
3. For files below target, open the matching file in `cov_annotate/`.
4. Lines prefixed with **`!`** are **not covered** by any test — add tests for those lines.
5. Map each uncovered line back to the correct layer strategy (§3) and test directory (§2).

### 6.4 Coverage Improvement Loop

Run this loop after generating tests or when asked to raise coverage:

1. Run pytest with `--cov` and `--cov-report=annotate:cov_annotate` for the target module.
2. Review `cov_annotate/` for files below the layer target.
3. For each `!` line, add a focused test that exercises that branch/path.
4. Re-run coverage until every file in scope meets its layer target.
5. Do **not** delete or weaken existing tests to hit a number — cover real behavior.

---

## 7. Common Commands

Adapt the runner/package manager to the project (poetry, pip, uv, etc.):

```bash
# All tests
poetry run pytest

# By layer
poetry run pytest tests/unit/
poetry run pytest tests/integration/

# Coverage with annotated report (preferred)
poetry run pytest --cov=src/<package> --cov-report=annotate:cov_annotate

# Terminal summary only (quick check)
poetry run pytest --cov=src/<package> --cov-report=term-missing

# Stop on first failure / verbose
poetry run pytest -x
poetry run pytest -v
```

---

## 8. Test Generation

When asked to generate tests for a target, follow this process:

1. Read the source file(s) for the target.
2. Identify every public method and business rule.
3. List the test cases before writing code (confirm with user if uncertain).
4. Apply the matching layer strategy from §3.
5. Use existing fixtures from `conftest.py`.
6. Output tests to the correct directory path.
7. Run the coverage improvement loop (§6.4) and close any `!` gaps before finishing.

### Generation targets

| Request phrasing        | Target type         | Output location                              |
| ----------------------- | ------------------- | -------------------------------------------- |
| "test the `Foo` entity" | Domain entity       | `tests/unit/domain/test_foo.py`              |
| "test `FooService`"     | Application service | `tests/unit/application/test_foo_service.py` |
| "test `/api/v1/foos`"   | API endpoint        | `tests/integration/test_foo_endpoints.py`    |
| "test both"             | Entity + endpoint   | Both files                                   |

For detailed integration test templates, see `references/integration-patterns.md`.

---

## 9. Review Checklist

Before finalising any generated test file:

- [ ] Tests are in the correct directory for their layer
- [ ] Naming follows `test_{action}_{result}[_{condition}]`
- [ ] Each test has a single behavioral focus
- [ ] AAA structure with comments is present
- [ ] Async tests carry `@pytest.mark.asyncio`
- [ ] No new fixtures duplicated from `conftest.py`
- [ ] Mock repos use `spec=` parameter
- [ ] Coverage report generated with `--cov-report=annotate:cov_annotate`
- [ ] Every file in scope meets its layer target (§6.1); no remaining `!` lines for in-scope code
