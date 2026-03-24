#!/usr/bin/env python3
"""
userPromptSubmitted hook — fired when the user submits a prompt.

Logs the prompt with a token estimate and an error-complaint flag
(1 if the prompt contains words like error/bug/fix/wrong/broken/fail).

Input JSON (stdin):
  { "timestamp": int, "cwd": str, "prompt": str }
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
    prompt: str = data.get("prompt", "")

    tokens = db.estimate_tokens(prompt)
    error_flag = db.contains_error_report(prompt)

    with db.connect(cwd) as conn:
        session_id = db.find_session_id(conn, cwd, timestamp)
        conn.execute(
            """
            INSERT INTO prompts
                (session_id, timestamp, cwd, prompt, estimated_tokens, contains_error_report)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (session_id, timestamp, cwd, prompt, tokens, error_flag),
        )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        db.log_hook_error(os.getcwd(), "user_prompt", exc)
        print(f"[hooks/user_prompt] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
