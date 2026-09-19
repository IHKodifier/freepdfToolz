import logging
import threading
import time
import uuid
from typing import Dict, Optional, Tuple

logger = logging.getLogger(__name__)


class StagedFileEntry:
    def __init__(self, filename: str, data: bytes, ttl_seconds: int = 1800):
        self.filename = filename
        self.data = data
        self.created_at = time.time()
        self.expires_at = self.created_at + ttl_seconds

    def is_expired(self) -> bool:
        return time.time() > self.expires_at


class FileStagingService:
    """
    Volatile in-memory and RAM disk cache for uploaded PDF files.
    Allows frontend preview/thumbnail endpoints to stage a file in memory
    so subsequent tool operations (delete, rotate, split, compress, crop, etc.)
    can execute with 0 re-upload bytes.
    """
    _lock = threading.Lock()
    _storage: Dict[str, StagedFileEntry] = {}

    @classmethod
    def store_staged_file(
        cls,
        filename: str,
        data: bytes,
        ttl_seconds: int = 1800,
    ) -> str:
        """
        Stores file bytes in volatile RAM cache with a default 30-minute TTL.
        Returns a unique session_file_id.
        """
        session_file_id = f"stg_{uuid.uuid4().hex}"
        entry = StagedFileEntry(filename=filename, data=data, ttl_seconds=ttl_seconds)

        with cls._lock:
            cls._cleanup_expired_locked()
            cls._storage[session_file_id] = entry

        logger.info(
            "Staged file '%s' (%d bytes) with session_file_id: %s (TTL: %ds)",
            filename,
            len(data),
            session_file_id,
            ttl_seconds,
        )
        return session_file_id

    @classmethod
    def get_staged_file(cls, session_file_id: str) -> Optional[Tuple[bytes, str]]:
        """
        Retrieves staged file (data, filename) if present and not expired.
        Refreshes access timestamp.
        """
        if not session_file_id:
            return None

        with cls._lock:
            cls._cleanup_expired_locked()
            entry = cls._storage.get(session_file_id)
            if entry is None:
                return None
            if entry.is_expired():
                cls._storage.pop(session_file_id, None)
                return None

            # Refresh expiration on access (rolling TTL)
            entry.expires_at = time.time() + 1800
            return entry.data, entry.filename

    @classmethod
    def delete_staged_file(cls, session_file_id: str) -> bool:
        """Removes a staged file from cache."""
        with cls._lock:
            return cls._storage.pop(session_file_id, None) is not None

    @classmethod
    def clear_all(cls) -> None:
        """Clears all staged files (used in test teardown)."""
        with cls._lock:
            cls._storage.clear()

    @classmethod
    def _cleanup_expired_locked(cls) -> int:
        now = time.time()
        expired_keys = [k for k, v in cls._storage.items() if now > v.expires_at]
        for k in expired_keys:
            del cls._storage[k]
        if expired_keys:
            logger.info("Evicted %d expired staged files from RAM cache", len(expired_keys))
        return len(expired_keys)
