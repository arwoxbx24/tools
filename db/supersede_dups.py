#!/usr/bin/env python3
"""
tools/db/supersede_dups.py — data-heal: mark duplicate calls rows as superseded.

Finds nids with >1 row where superseded_by IS NULL, picks winner per
_DEDUP_PRIORITY (mirrors build_dashboard.py), sets superseded_by on losers.

Usage:
    python tools/db/supersede_dups.py            # dry-run (safe, default)
    python tools/db/supersede_dups.py --apply    # commit changes
"""

import argparse
import sqlite3
import sys
from datetime import datetime
from pathlib import Path

_DEDUP_PRIORITY = {st: i for i, st in enumerate([
    "итог_записан", "проведена",
    "не_явился", "отменена", "не_состоялась",
    "подтверждено", "ждём_подтверждения", "расхождение_даты",
    "слот_выбран", "слот_снят", "предварительно", "просит_перенос",
])}
_TERMINAL = frozenset({"итог_записан", "проведена", "не_явился", "отменена", "не_состоялась"})
_ACTIVE   = frozenset({"ждём_подтверждения", "подтверждено", "слот_выбран",
                        "расхождение_даты", "предварительно", "перенос_предложен"})


def _pick_winner(rows: list, now_ts: float) -> dict:
    """Return winning row from a dup group (mirrors dashboard _DEDUP_PRIORITY logic)."""
    best = rows[0]
    for r in rows[1:]:
        cur_ts = best.get("ts_from") or 0
        new_ts = r.get("ts_from") or 0
        cur_ms = best.get("meeting_state") or ""
        new_ms = r.get("meeting_state") or ""
        # Future active beats past terminal (rescheduled meeting, K-919)
        if (new_ts > now_ts and new_ms in _ACTIVE
                and cur_ts < now_ts and cur_ms in _TERMINAL):
            best = r
            continue
        ep = _DEDUP_PRIORITY.get(cur_ms, 99)
        np_ = _DEDUP_PRIORITY.get(new_ms, 99)
        if np_ < ep or (np_ == ep and new_ts > cur_ts):
            best = r
    return best


def supersede_dups(conn: sqlite3.Connection, apply: bool = False) -> int:
    """
    Mark loser rows with superseded_by = winner event_id.

    Idempotent: only touches rows where superseded_by IS NULL.
    Dry-run uses a transaction that is rolled back — no writes escape.
    Returns count of rows updated (or would-be updated in dry-run).
    """
    conn.row_factory = sqlite3.Row
    conn.execute("BEGIN IMMEDIATE")
    try:
        dup_nids = [
            row[0] for row in conn.execute(
                "SELECT nid FROM calls "
                "WHERE nid IS NOT NULL AND superseded_by IS NULL "
                "GROUP BY nid HAVING COUNT(*) > 1"
            )
        ]

        now_ts = datetime.now().timestamp()
        total = 0

        for nid in dup_nids:
            rows = [dict(r) for r in conn.execute(
                "SELECT event_id, nid, meeting_state, ts_from FROM calls "
                "WHERE nid=? AND superseded_by IS NULL",
                (nid,)
            )]
            if len(rows) < 2:
                continue

            winner = _pick_winner(rows, now_ts)
            winner_eid = winner["event_id"]
            losers = [r for r in rows if r["event_id"] != winner_eid]

            for loser in losers:
                loser_eid = loser["event_id"]
                ms = loser.get("meeting_state") or ""
                conn.execute(
                    "UPDATE calls SET superseded_by=? "
                    "WHERE event_id=? AND superseded_by IS NULL",
                    (winner_eid, loser_eid),
                )
                if apply:
                    print(f"APPLIED:   superseded_by={winner_eid} "
                          f"on event_id={loser_eid} (nid={nid}, ms={ms})")
                else:
                    print(f"DRY-RUN:   would set superseded_by={winner_eid} "
                          f"on event_id={loser_eid} (nid={nid}, ms={ms})")
                total += 1

        if apply:
            conn.commit()
        else:
            conn.rollback()
    except Exception:
        conn.rollback()
        raise

    return total


def main() -> None:
    ap = argparse.ArgumentParser(description="Mark duplicate calls rows as superseded.")
    ap.add_argument("--apply", action="store_true",
                    help="Commit changes (default: dry-run)")
    ap.add_argument("--db", default=None,
                    help="Path to SQLite DB (default: data/db.sqlite3 from repo root)")
    args = ap.parse_args()

    if args.db:
        db_path = Path(args.db)
    else:
        # Two levels up from tools/db/ → repo root
        db_path = Path(__file__).parent.parent.parent / "data" / "db.sqlite3"

    if not db_path.exists():
        print(f"ERROR: DB not found at {db_path}", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(str(db_path))
    try:
        mode = "APPLY" if args.apply else "DRY-RUN"
        print(f"supersede_dups — mode={mode} db={db_path}")
        n = supersede_dups(conn, apply=args.apply)
        label = "updated" if args.apply else "would update"
        print(f"Done: {n} row(s) {label}.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
