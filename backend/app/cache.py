import json
import logging
import os
import time
from datetime import date, datetime
from typing import Any

logger = logging.getLogger(__name__)


def _json_default(obj: Any) -> Any:
    """Fallback encoder for types json.dumps can't handle natively.

    Task rows carry datetime created_at/updated_at columns. ISO-8601 strings
    round-trip cleanly: on a cache hit json.loads yields the string back and
    Pydantic's TaskRead parses it into a datetime again.
    """
    if isinstance(obj, (datetime, date)):
        return obj.isoformat()
    raise TypeError(f"Object of type {obj.__class__.__name__} is not JSON serializable")


class InMemoryCache:
    def __init__(self) -> None:
        self._store: dict[str, dict[str, Any]] = {}

    def get(self, key: str) -> Any | None:
        item = self._store.get(key)
        if item is None:
            return None
        if time.time() >= item["expires_at"]:
            self._store.pop(key, None)
            return None
        return item["value"]

    def set(self, key: str, value: Any, ttl: int = 60) -> None:
        self._store[key] = {
            "value": value,
            "expires_at": time.time() + ttl,
        }

    def delete(self, key: str) -> None:
        self._store.pop(key, None)

    def delete_prefix(self, prefix: str) -> None:
        for key in list(self._store.keys()):
            if key.startswith(prefix):
                self._store.pop(key, None)


class MemcachedCache:
    def __init__(self, host: str, port: int, default_ttl: int) -> None:
        self.host = host
        self.port = port
        self.default_ttl = default_ttl
        self._client = None
        try:
            from pymemcache.client.base import Client

            # No custom serde: set()/get() below do json.dumps/json.loads
            # themselves. Passing a serde with the wrong signature made every
            # store raise inside pymemcache and get swallowed silently.
            self._client = Client((host, port))
            self._client.stats()
            logger.info("✅ Memcached connected (%s:%s)", host, port)
        except Exception as e:
            logger.exception("❌ Memcached connection failed: %s", e)
            self._client = None

    def get(self, key: str) -> Any | None:
        if self._client is None:
            return None
        try:
            value = self._client.get(key)
        except Exception as e:
            logger.exception("Memcached GET error for %s: %s", key, e)
            return None
        if value is None:
            return None
        if isinstance(value, bytes):
            try:
                return json.loads(value.decode("utf-8"))
            except Exception:
                return value.decode("utf-8")
        return value

    def set(self, key: str, value: Any, ttl: int = 60) -> None:
        if self._client is None:
            return
        try:
            payload = json.dumps(value, default=_json_default)
            self._client.set(key, payload, expire=ttl or self.default_ttl)
            logger.debug("Memcached SET %s", key)
        except Exception as e:
            logger.exception("Memcached SET error for %s: %s", key, e)
            return

    def delete(self, key: str) -> None:
        if self._client is None:
            return
        try:
            self._client.delete(key)
        except Exception as e:
            logger.exception("Memcached DELETE error for %s: %s", key, e)
            return

    def delete_prefix(self, prefix: str) -> None:
        if self._client is None:
            return
        try:
            self._client.delete_many([prefix])
        except Exception as e:
            logger.exception("Memcached delete_prefix error for %s: %s", prefix, e)
            return

class RedisCache:
    def __init__(self, host: str, port: int, default_ttl: int) -> None:
        self.default_ttl = default_ttl
        self._client = None

        try:
            import redis

            self._client = redis.Redis(
                host=host,
                port=port,
                decode_responses=True,
                socket_connect_timeout=5,
                socket_timeout=5,
            )

            self._client.ping()

            logger.info("✅ Redis connected (%s:%s)", host, port)

        except Exception as e:
            logger.exception("❌ Redis connection failed: %s", e)
            self._client = None

    def get(self, key: str):
        if self._client is None:
            return None

        try:
            value = self._client.get(key)

            if value is None:
                logger.debug("Redis MISS %s", key)
                return None

            logger.debug("Redis HIT %s", key)
            return json.loads(value)

        except Exception as e:
            logger.exception("Redis GET error: %s", e)
            return None

    def set(self, key: str, value: Any, ttl: int = 60):
        if self._client is None:
            return

        try:
            self._client.setex(key, ttl or self.default_ttl, json.dumps(value, default=_json_default))
            logger.debug("Redis SET %s", key)

        except Exception as e:
            logger.exception("Redis SET error: %s", e)

    def delete(self, key: str):
        if self._client is None:
            return

        try:
            self._client.delete(key)

        except Exception as e:
            logger.exception("Redis DELETE error: %s", e)

    def delete_prefix(self, prefix: str):
        if self._client is None:
            return

        try:
            cursor = 0

            while True:
                cursor, keys = self._client.scan(
                    cursor=cursor,
                    match=f"{prefix}*",
                    count=100,
                )

                if keys:
                    self._client.delete(*keys)

                if cursor == 0:
                    break

        except Exception as e:
            logger.exception("Redis delete_prefix error: %s", e)


class CacheService:
    def __init__(self) -> None:
        backend = os.getenv("CACHE_BACKEND", "memory").lower()

        logger.info("Cache backend: %s", backend)

        self.default_ttl = int(os.getenv("CACHE_TTL_SECONDS", "60"))

        if backend == "redis":
            cache = RedisCache(
                host=os.getenv("REDIS_HOST", "redis"),
                port=int(os.getenv("REDIS_PORT", "6379")),
                default_ttl=self.default_ttl,
            )

            self.backend = cache if cache._client else InMemoryCache()

            if cache._client is None:
                logger.warning("⚠ Falling back to InMemory cache")

        elif backend == "memcached":
            cache = MemcachedCache(
                host=os.getenv("CACHE_HOST", "memcached"),
                port=int(os.getenv("CACHE_PORT", "11211")),
                default_ttl=self.default_ttl,
            )

            self.backend = cache if cache._client else InMemoryCache()

            if cache._client is None:
                logger.warning("⚠ Falling back to InMemory cache")

        else:
            logger.info("Using InMemory cache")
            self.backend = InMemoryCache()

    def get(self, key: str) -> Any | None:
        return self.backend.get(key)

    def set(self, key: str, value: Any, ttl: int | None = None) -> None:
        self.backend.set(key, value, ttl=ttl or self.default_ttl)

    def delete(self, key: str) -> None:
        self.backend.delete(key)

    def delete_prefix(self, prefix: str) -> None:
        self.backend.delete_prefix(prefix)


cache_service = CacheService()
