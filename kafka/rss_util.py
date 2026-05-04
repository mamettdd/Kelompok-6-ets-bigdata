"""Filter sumber RSS: blokir domain detik.com (Permintaan proyek)."""
from __future__ import annotations

import logging
from typing import List
from urllib.parse import urlparse

log = logging.getLogger(__name__)


def is_blocked_detik_url(url: str) -> bool:
    if not url or not isinstance(url, str):
        return False
    try:
        host = (urlparse(url.strip()).hostname or "").lower()
    except ValueError:
        return False
    return "detik.com" in host or host.endswith(".detik.com")


def filter_feed_urls(urls: List[str]) -> List[str]:
    out: List[str] = []
    for u in urls:
        if is_blocked_detik_url(u):
            log.warning("Mengabaikan feed RSS detik.com: %s", u)
            continue
        out.append(u)
    return out
