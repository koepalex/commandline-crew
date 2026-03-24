#!/usr/bin/env python3
"""
sessionStart hook — fired when a new agent session begins or resumes.

Writes a session record to the database and persists the session ID
to .copilot/hooks-data/.session_id for downstream hooks.

Input JSON (stdin):
  { "timestamp": int, "cwd": str, "source": str, "initialPrompt": str }
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

# Allow importing db from the same directory regardless of cwd
sys.path.insert(0, str(Path(__file__).parent))
import db


def main() -> None:
    raw = sys.stdin.read()
    data: dict = json.loads(raw) if raw.strip() else {}

    cwd: str = data.get("cwd") or os.getcwd()
    timestamp: int = data.get("timestamp", 0)
    source: str = data.get("source", "unknown")
    initial_prompt: str | None = data.get("initialPrompt")
    repository: str = Path(cwd).name

    session_id = db.make_session_id(cwd, timestamp)

    with db.connect(cwd) as conn:
        conn.execute(
            """
            INSERT OR REPLACE INTO sessions
                (id, start_timestamp, cwd, source, initial_prompt, repository)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (session_id, timestamp, cwd, source, initial_prompt, repository),
        )

    db.write_session_id(session_id, cwd)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(f"[hooks/session_start] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
