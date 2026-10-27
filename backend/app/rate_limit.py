"""Small fixed-window limiter with Redis-backed cross-instance counters.

Redis is the production path. The in-process fallback exists for local development
and tests only; it is not a distributed limiter and must not be relied on at scale.
"""
from __future__ import annotations

import time
from collections import defaultdict
from dataclasses import dataclass
from typing import Awaitable, Callable

from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware


@dataclass(frozen=True)
class Limit:
    requests: int
    window_seconds: int


POLICIES: tuple[tuple[str, Limit], ...] = (
    ("/auth/firebase/exchange", Limit(10, 60)),
    ("/encrypted-messages", Limit(60, 60)),
    ("/messages", Limit(60, 60)),
    ("/users/search", Limit(30, 60)),
    ("/push-devices", Limit(20, 60)),
)
DEFAULT_LIMIT = Limit(120, 60)


def policy_for(path: str) -> Limit:
    for marker, policy in POLICIES:
        if marker in path:
            return policy
    return DEFAULT_LIMIT


class RateLimitMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, redis_getter: Callable[[], object | None], enabled: bool = True):
        super().__init__(app)
        self.redis_getter = redis_getter
        self.enabled = enabled
        self._local: dict[str, tuple[int, int]] = {}
        self._last_cleanup = 0.0

    async def _count(self, key: str, policy: Limit, now: int) -> tuple[int, int]:
        redis = self.redis_getter()
        bucket = now // policy.window_seconds
        ttl = policy.window_seconds - (now % policy.window_seconds)
        if redis is not None:
            redis_key = f"veyra:ratelimit:{key}:{bucket}"
            count = int(await redis.incr(redis_key))
            if count == 1:
                await redis.expire(redis_key, ttl + 1)
            return count, ttl

        # Local fallback is intentionally per-process; Redis is required for a
        # multi-instance deployment. Opportunistically remove expired buckets.
        local_key = f"{key}:{bucket}"
        old_count, old_expiry = self._local.get(local_key, (0, now + ttl))
        count = old_count + 1
        self._local[local_key] = (count, old_expiry)
        if now - self._last_cleanup > 60:
            self._local = {k: v for k, v in self._local.items() if v[1] >= now}
            self._last_cleanup = now
        return count, ttl

    async def dispatch(self, request: Request, call_next):
        if not self.enabled or request.url.path in {"/health", "/health/live", "/health/ready"}:
            return await call_next(request)
        if request.method == "OPTIONS":
            return await call_next(request)

        policy = policy_for(request.url.path)
        # Do not trust X-Forwarded-For here: it is client-controlled unless a
        # trusted-proxy deployment explicitly normalizes it upstream.
        host = request.client.host if request.client else "unknown"
        route_group = next((marker for marker, _ in POLICIES if marker in request.url.path), "default")
        key = f"{host}:{route_group}"
        now = int(time.time())
        try:
            count, retry_after = await self._count(key, policy, now)
        except Exception:
            # Fail closed for sensitive routes if Redis was configured but failed.
            # The app's Redis connection health is independently exposed by ready.
            if self.redis_getter() is not None:
                return JSONResponse(status_code=503, content={"detail": "Rate limiting temporarily unavailable"})
            count, retry_after = 0, policy.window_seconds

        if count > policy.requests:
            return JSONResponse(
                status_code=429,
                content={"detail": "Too many requests. Please try again shortly."},
                headers={"Retry-After": str(retry_after), "X-RateLimit-Limit": str(policy.requests)},
            )
        response = await call_next(request)
        response.headers["X-RateLimit-Limit"] = str(policy.requests)
        response.headers["X-RateLimit-Remaining"] = str(max(0, policy.requests - count))
        return response
