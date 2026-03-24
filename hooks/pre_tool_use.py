#!/usr/bin/env python3
"""
preToolUse hook — fired before the agent invokes any tool.

Logs a lightweight pre-execution event so denied tools (which still
produce a postToolUse event with resultType='denied') can be tracked.
No output is produced; omitting output allows the tool to proceed.

Input JSON (stdin):
  { "timestamp": int, "cwd": str, "toolName": str, "toolArgs": str }
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
    tool_name: str = data.get("toolName", "")
    tool_args: str = data.get("toolArgs", "")

    with db.connect(cwd) as conn:
        session_id = db.find_session_id(conn, cwd, timestamp)
        conn.execute(
            """
            INSERT INTO pre_tool_events
                (session_id, timestamp, cwd, tool_name, tool_args)
            VALUES (?, ?, ?, ?, ?)
            """,
            (session_id, timestamp, cwd, tool_name, tool_args),
        )

    # No output → tool is allowed by default


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        db.log_hook_error(os.getcwd(), "pre_tool_use", exc)
        print(f"[hooks/pre_tool_use] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
