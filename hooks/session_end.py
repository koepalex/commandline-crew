#!/usr/bin/env python3
"""
sessionEnd hook — fired when an agent session completes or is terminated.

Updates the session record with end timestamp and reason, then removes
the .session_id correlation file.

Input JSON (stdin):
  { "timestamp": int, "cwd": str, "reason": str }
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import db


def main() -> None:
    raw = sys.stdin.read()
    data: dict = json.loads(raw) if raw.strip() else {}

    cwd: str = data.get("cwd") or os.getcwd()
    timestamp: int = data.get("timestamp", 0)
    reason: str = data.get("reason", "unknown")

    session_id = db.read_session_id(cwd)

    with db.connect(cwd) as conn:
        if session_id:
            conn.execute(
                """
                UPDATE sessions
                SET end_timestamp = ?, end_reason = ?
                WHERE id = ?
                """,
                (timestamp, reason, session_id),
            )

    db.clear_session_id(cwd)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"[hooks/session_end] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
