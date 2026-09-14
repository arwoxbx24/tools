"""Durable notify transport for claude-doctor / codex-doctor.

JSON queue (tools/.notify-state/notify_state.json) + fcntl.flock on
tools/.notify-state/notify_state.lock
+ atomic temp+os.replace writes. Monotonic event_id, ack registry, recovery
of unacknowledged events after restart. Python stdlib only.
"""

from __future__ import annotations

import contextlib
import fcntl
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

DEFAULT_STATE_FILE = Path(__file__).resolve().parent / ".notify-state" / "notify_state.json"
CORRUPT_SUFFIX = ".corrupt"


def _now_iso8601() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def _parse_iso8601(ts: str) -> datetime:
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S.%fZ").replace(
        tzinfo=timezone.utc
    )


def _empty_state() -> dict:
    return {
        "next_event_id": 1,
        "last_acked": 0,
        "events": [],
        "acks": {},
        "last_modified": _now_iso8601(),
    }


class NotifyTransport:
    """Durable, file-based event queue with ACK semantics."""

    def __init__(self, state_file: Path | str | None = None):
        """Initialize the transport.

        Args:
            state_file: path to notify_state.json
                (default: tools/.notify-state/notify_state.json)
        """
        self.state_file = Path(state_file) if state_file else DEFAULT_STATE_FILE
        self.lock_file = self.state_file.with_suffix(".lock")

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @contextlib.contextmanager
    def _locked(self):
        """Hold an exclusive flock on the lock file."""
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        with open(self.lock_file, "a+") as lf:
            fcntl.flock(lf.fileno(), fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lf.fileno(), fcntl.LOCK_UN)

    def _read(self) -> dict:
        """Read state from JSON; back up corrupt files and start fresh."""
        if not self.state_file.exists():
            return _empty_state()
        try:
            return json.loads(self.state_file.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError, OSError):
            corrupt = self.state_file.with_name(
                self.state_file.name + CORRUPT_SUFFIX
            )
            os.replace(self.state_file, corrupt)
            return _empty_state()

    def _write(self, state: dict) -> None:
        """Atomically write state (tmp+fsync+os.replace, pid-isolated tmp)."""
        state["last_modified"] = _now_iso8601()
        tmp = self.state_file.with_name(
            f"{self.state_file.name}.tmp.{os.getpid()}"
        )
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(state, f, ensure_ascii=False, indent=2)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, self.state_file)
        except BaseException:
            # Leave nothing stale behind; caller sees the exception.
            with contextlib.suppress(OSError):
                tmp.unlink()
            raise

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def write_event(self, from_agent: str = None, type: str = None,
                    data: dict | None = None, recipient: str | None = None,
                    **kwargs) -> int:
        """Write an event, return its monotonically increasing event_id.

        recipient=None means broadcast (visible to every reader).
        Raises ValueError on self-send (recipient == from_agent).
        """
        # Accept `from=` via kwargs since `from` is a Python keyword.
        if from_agent is None:
            from_agent = kwargs.pop("from")
        if recipient is not None and recipient == from_agent:
            raise ValueError(
                "self-send not allowed: recipient == from_agent "
                f"({recipient!r})"
            )
        with self._locked():
            state = self._read()
            event_id = state["next_event_id"]
            state["next_event_id"] = event_id + 1
            state["events"].append({
                "id": event_id,
                "from": from_agent,
                "type": type,
                "recipient": recipient,
                "timestamp": _now_iso8601(),
                "data": data or {},
            })
            self._write(state)
            return event_id

    def read_events(self, since_id: int = 0,
                    from_agent: str | None = None,
                    recipient: str | None = None) -> list:
        """Read events with id > since_id, optionally filtered by sender
        and/or recipient.

        recipient=None: no recipient filter. Otherwise matches broadcast
        events (recipient unset) plus events addressed to `recipient`.
        """
        with self._locked():
            state = self._read()
            events = [
                dict(e) for e in state["events"]
                if e["id"] > since_id
                and (from_agent is None or e["from"] == from_agent)
                and (recipient is None
                     or e.get("recipient") is None
                     or e.get("recipient") == recipient)
            ]
            return events

    def ack(self, event_id: int) -> bool:
        """Acknowledge an event: remove it from the queue.

        Returns False if the event does not exist (idempotent double-ack).
        """
        with self._locked():
            state = self._read()
            idx = next(
                (i for i, e in enumerate(state["events"])
                 if e["id"] == event_id),
                None,
            )
            if idx is None:
                return False
            state["acks"][str(event_id)] = _now_iso8601()
            del state["events"][idx]
            if event_id == state["last_acked"] + 1:
                state["last_acked"] = event_id
            self._write(state)
            return True

    def get_pending(self, recipient: str | None = None) -> list:
        """Return the ids of unacknowledged events.

        recipient=None: all pending. Otherwise only broadcast events plus
        events addressed to `recipient`.
        """
        with self._locked():
            state = self._read()
            acked = set(state["acks"])
            return [
                e["id"] for e in state["events"]
                if str(e["id"]) not in acked
                and (recipient is None
                     or e.get("recipient") is None
                     or e.get("recipient") == recipient)
            ]

    def cleanup(self, max_age_hours: int = 24) -> int:
        """Remove events older than max_age_hours; never removes pending.

        Only events already present in `acks` are eligible for removal.
        """
        with self._locked():
            state = self._read()
            cutoff = datetime.now(timezone.utc) - timedelta(
                hours=max_age_hours
            )
            acked = set(state["acks"])
            keep, drop = [], []
            for e in state["events"]:
                old = _parse_iso8601(e["timestamp"]) < cutoff
                if old and str(e["id"]) in acked:
                    drop.append(e)
                else:
                    keep.append(e)
            dropped_ids = {str(e["id"]) for e in drop}
            state["events"] = keep
            state["acks"] = {
                k: v for k, v in state["acks"].items()
                if k not in dropped_ids
            }
            if drop:
                self._write(state)
            return len(drop)

    def recover(self, recipient: str | None = None) -> list:
        """Recovery on restart: return all unacknowledged events."""
        with self._locked():
            state = self._read()
            if recipient is None:
                return [dict(e) for e in state["events"]]
            # Filter for recipient (same logic as get_pending)
            return [dict(e) for e in state["events"]
                    if e.get("recipient") is None or e.get("recipient") == recipient]

    def get_state(self) -> dict:
        """Debug helper: full state snapshot (deep-ish copy)."""
        with self._locked():
            state = self._read()
            return json.loads(json.dumps(state))

    def reset(self) -> None:
        """Clear all state (TESTS/DEBUG ONLY)."""
        with self._locked():
            self._write(_empty_state())
