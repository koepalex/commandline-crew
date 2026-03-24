#!/usr/bin/env python3
"""
errorOccurred hook — fired when an error occurs during agent execution.

Input JSON (stdin):
  {
    "timestamp": int, "cwd": str,
    "error": { "message": str, "name": str, "stack": str }
  }
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

    error: dict = data.get("error") or {}
    error_name: str = error.get("name", "")
    error_message: str = error.get("message", "")
    error_stack: str = error.get("stack", "")

    with db.connect(cwd) as conn:
        session_id = db.find_session_id(conn, cwd, timestamp)
        conn.execute(
            """
            INSERT INTO errors
                (session_id, timestamp, cwd, error_name, error_message, error_stack)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (session_id, timestamp, cwd, error_name, error_message, error_stack),
        )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        db.log_hook_error(os.getcwd(), "error_occurred", exc)
        print(f"[hooks/error_occurred] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
