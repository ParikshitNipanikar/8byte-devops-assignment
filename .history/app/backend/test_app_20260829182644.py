
import pytest
from app import app

@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client

def test_health_endpoint(client):
    """Unit test: checks the health endpoint in isolation."""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "ok"

def test_visits_endpoint_integration(client):
    """Integration test: verifies the full backend -> Postgres write/read path."""
    response = client.post("/api/visits")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "ok"
    assert isinstance(data["count"], int)
    assert data["count"] > 0
EOF