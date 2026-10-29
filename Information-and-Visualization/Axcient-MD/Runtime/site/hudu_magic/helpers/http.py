"""HTTP retry helpers (parity with HuduAPI PowerShell ``Invoke-HuduRequest``)."""

from __future__ import annotations

import random
from datetime import datetime, timezone

from ..constants import (
    HUDU_RATE_LIMIT_JITTER_MAX,
    HUDU_RATE_LIMIT_JITTER_MIN,
    HUDU_RATE_LIMIT_WINDOW_SECONDS,
)


def is_rate_limit_response(status_code: int, message: str) -> bool:
    if status_code == 429:
        return True
    lower = message.lower()
    return "retry later" in lower or "too many requests" in lower


def seconds_until_next_rate_limit_window(
    *,
    window_seconds: int = HUDU_RATE_LIMIT_WINDOW_SECONDS,
    now: datetime | None = None,
    jitter_min: int = HUDU_RATE_LIMIT_JITTER_MIN,
    jitter_max: int = HUDU_RATE_LIMIT_JITTER_MAX,
) -> float:
    """
    Sleep until the next Rack::Attack-style window (default 5 minutes), plus jitter.

    Mirrors PowerShell ``Invoke-HuduRequest`` rate-limit handling.
    """
    # Rack::Attack windows are epoch-aligned, so UTC is the correct reference clock.
    now = now or datetime.now(tz=timezone.utc)
    window_minutes = max(1, window_seconds // 60)
    seconds_into_window = (now.minute % window_minutes) * 60 + now.second
    seconds_until = max(0, window_seconds - seconds_into_window)
    jitter = random.randint(jitter_min, jitter_max)
    return float(max(0, seconds_until + jitter))


def error_message_from_response(response) -> str:
    try:
        payload = response.json()
        if isinstance(payload, dict):
            return str(
                payload.get("message") or payload.get("error") or response.text
            )
    except Exception:
        pass
    return str(response.text or "")


def retry_delay_seconds(
    status_code: int,
    message: str,
    *,
    retry_on_rate_limit: bool,
    retry_on_error: bool,
    rate_limit_window_seconds: int,
    error_retry_delay: float,
) -> float | None:
    """Return seconds to sleep before a retry, or ``None`` if the request should not retry."""
    if retry_on_rate_limit and is_rate_limit_response(status_code, message):
        return seconds_until_next_rate_limit_window(
            window_seconds=rate_limit_window_seconds
        )

    if status_code == 404:
        return None

    if retry_on_error:
        return float(error_retry_delay)

    return None
