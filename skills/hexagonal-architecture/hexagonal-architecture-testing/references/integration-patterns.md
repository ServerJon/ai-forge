# Integration Test Patterns

Reference for writing `tests/integration/` tests in hexagonal-architecture Python APIs.

---

## Async HTTP Client Setup

Use `httpx.AsyncClient` mounted against the FastAPI app (or adapt for your framework):

```python
# conftest.py
import pytest_asyncio
import httpx
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

from src.<package>.main import app
from src.<package>.infrastructure.database import Base, get_db

TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"

@pytest_asyncio.fixture(scope="function")
async def db_session():
    engine = create_async_engine(TEST_DATABASE_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with async_session() as session:
        yield session

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()

@pytest_asyncio.fixture(scope="function")
async def client(db_session: AsyncSession):
    async def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as ac:
        yield ac

    app.dependency_overrides.clear()
```

---

## CRUD Cycle Template

```python
import pytest

@pytest.mark.asyncio
async def test_create_{entity}_returns_201(client):
    # Arrange
    payload = {"name": "Example", ...}
    # Act
    response = await client.post("/api/v1/{entities}", json=payload)
    # Assert
    assert response.status_code == 201
    data = response.json()
    assert data["name"] == "Example"


@pytest.mark.asyncio
async def test_get_{entity}_returns_200(client):
    # Arrange — create via API so state is consistent
    create_resp = await client.post("/api/v1/{entities}", json={"name": "Example"})
    entity_id = create_resp.json()["id"]
    # Act
    response = await client.get(f"/api/v1/{entities}/{entity_id}")
    # Assert
    assert response.status_code == 200


@pytest.mark.asyncio
async def test_update_{entity}_returns_200(client):
    # Arrange
    create_resp = await client.post("/api/v1/{entities}", json={"name": "Old"})
    entity_id = create_resp.json()["id"]
    # Act
    response = await client.put(f"/api/v1/{entities}/{entity_id}", json={"name": "New"})
    # Assert
    assert response.status_code == 200
    assert response.json()["name"] == "New"


@pytest.mark.asyncio
async def test_delete_{entity}_returns_204(client):
    # Arrange
    create_resp = await client.post("/api/v1/{entities}", json={"name": "ToDelete"})
    entity_id = create_resp.json()["id"]
    # Act
    response = await client.delete(f"/api/v1/{entities}/{entity_id}")
    # Assert
    assert response.status_code == 204
```

---

## Error Path Coverage

Always test these HTTP error codes for every endpoint group:

| Status | Trigger | Example test name |
|--------|---------|-------------------|
| 404 | Resource not found | `test_get_{entity}_returns_404_when_not_found` |
| 409 | Duplicate / conflict | `test_create_{entity}_returns_409_on_duplicate_email` |
| 422 | Validation failure | `test_create_{entity}_returns_422_when_name_missing` |
| 400 | Business rule violation | `test_update_{entity}_returns_400_when_rule_violated` |

```python
@pytest.mark.asyncio
async def test_get_{entity}_returns_404_when_not_found(client):
    response = await client.get("/api/v1/{entities}/nonexistent-id")
    assert response.status_code == 404


@pytest.mark.asyncio
async def test_create_{entity}_returns_409_on_duplicate(client):
    payload = {"name": "Alice", "email": "alice@example.com"}
    await client.post("/api/v1/{entities}", json=payload)
    response = await client.post("/api/v1/{entities}", json=payload)
    assert response.status_code == 409
```

---

## Pagination / Filtering

```python
@pytest.mark.asyncio
async def test_list_{entities}_supports_pagination(client):
    # Arrange — seed 3 records
    for i in range(3):
        await client.post("/api/v1/{entities}", json={"name": f"Entity {i}"})
    # Act
    response = await client.get("/api/v1/{entities}?limit=2&offset=0")
    # Assert
    assert response.status_code == 200
    assert len(response.json()["items"]) == 2
```

---

## Rules

- Set up test data via **API calls or fixtures**, never direct DB inserts — this keeps tests
  independent of the ORM layer.
- Prefer `scope="function"` for DB sessions to guarantee isolation between tests.
- If the project uses `scope="session"` for performance, wrap mutations in transactions that
  roll back after each test.
