import json
import os
import time
from typing import Any, Optional

from .config import settings


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
            self._client.set(key, value, expire=ttl)
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
        if backend == "memcached":
            self.backend = MemcachedCache(
                host=os.getenv("CACHE_HOST", "memcached"),
                port=int(os.getenv("CACHE_PORT", "11211")),
                default_ttl=int(os.getenv("CACHE_TTL_SECONDS", "60")),
            )
        else:
            self.backend = InMemoryCache()

    def get(self, key: str) -> Any | None:
        return self.backend.get(key)

    def set(self, key: str, value: Any, ttl: int | None = None) -> None:
        self.backend.set(key, value, ttl=ttl or int(os.getenv("CACHE_TTL_SECONDS", "60")))

    def delete(self, key: str) -> None:
        self.backend.delete(key)

    def delete_prefix(self, prefix: str) -> None:
        self.backend.delete_prefix(prefix)


cache_service = CacheService()
