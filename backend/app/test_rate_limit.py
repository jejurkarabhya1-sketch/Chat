from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.rate_limit import Limit, RateLimitMiddleware, policy_for


def test_sensitive_routes_have_stricter_policies():
    assert policy_for("/auth/firebase/exchange").requests == 10
    assert policy_for("/conversations/3/encrypted-messages").requests == 60
    assert policy_for("/users/search").requests == 30
    assert policy_for("/users/me").requests == 120


def test_local_rate_limit_returns_429_and_retry_after():
    app = FastAPI()
    app.add_middleware(RateLimitMiddleware, redis_getter=lambda: None, enabled=True)

    @app.get("/auth/firebase/exchange")
    def auth_exchange():
        return {"ok": True}

    client = TestClient(app)
    statuses = [client.get("/auth/firebase/exchange").status_code for _ in range(11)]
    assert statuses[:10] == [200] * 10
    assert statuses[10] == 429
    response = client.get("/auth/firebase/exchange")
    assert response.status_code == 429
    assert "Retry-After" in response.headers


def test_health_routes_are_exempt_from_rate_limit():
    app = FastAPI()
    app.add_middleware(RateLimitMiddleware, redis_getter=lambda: None, enabled=True)

    @app.get("/health/live")
    def health():
        return {"status": "alive"}

    client = TestClient(app)
    assert all(client.get("/health/live").status_code == 200 for _ in range(150))
