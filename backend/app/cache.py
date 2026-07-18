import json
import logging
import os
import time
from typing import Any

logger = logging.getLogger(__name__)


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

            self._client = Client((host, port), serde=serde)
            self._client.stats()
            logger.info("✅ Memcached connected (%s:%s)", host, port)
        except Exception:
            self._client = None

    def get(self, key: str) -> Any | None:
        if self._client is None:
            return None
        try:
            value = self._client.get(key)
        except Exception:
            return None
        if value is None:
            return None
        return value

    def set(self, key: str, value: Any, ttl: int = 60) -> None:
        if self._client is None:
            return
        try:
            self._client.set(key, value, expire=ttl or self.default_ttl)
        except Exception:
            return

    def delete(self, key: str) -> None:
        if self._client is None:
            return
        try:
            self._client.delete(key)
        except Exception:
            return

    def delete_prefix(self, prefix: str) -> None:
        if self._client is None:
            return
        try:
            self._client.delete_many([prefix])
        except Exception:
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
            self._client.setex(key, ttl or self.default_ttl, json.dumps(value))
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


class Serde:
    def serialize(self, value: Any) -> bytes:
        return json.dumps(value).encode("utf-8")

    def deserialize(self, value: bytes) -> Any:
        if value is None:
            return None
        return json.loads(value.decode("utf-8"))


serde = Serde()


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
