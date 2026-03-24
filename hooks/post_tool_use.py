#!/usr/bin/env python3
"""
postToolUse hook — fired after a tool completes (success, failure, or denied).

Logs the full tool execution record including:
  - extracted file path (if applicable)
  - result type and truncated result text
  - estimated input/output token counts

Input JSON (stdin):
  {
    "timestamp": int, "cwd": str,
    "toolName": str, "toolArgs": str,
    "toolResult": { "resultType": str, "textResultForLlm": str }
  }
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import db

_MAX_RESULT_LEN = 4000  # truncate long outputs to keep DB size reasonable


_raw_stdin: str = ""


def main() -> None:
    global _raw_stdin
    raw = sys.stdin.read()
    _raw_stdin = raw
    data: dict = json.loads(raw) if raw.strip() else {}

    cwd: str = data.get("cwd") or os.getcwd()
    timestamp: int = data.get("timestamp", 0)
    tool_name: str = data.get("toolName", "")
    tool_args_raw = data.get("toolArgs", "")
    # The CLI may send toolArgs as an object or as a JSON-encoded string
    tool_args: str = json.dumps(tool_args_raw) if isinstance(tool_args_raw, dict) else (tool_args_raw or "")

    result: dict = data.get("toolResult") or {}
    result_type: str = result.get("resultType", "")
    result_text: str = (result.get("textResultForLlm") or "")[:_MAX_RESULT_LEN]

    file_path = db.extract_file_path(tool_name, tool_args)
    input_tokens = db.estimate_tokens(tool_args)
    output_tokens = db.estimate_tokens(result_text)

    with db.connect(cwd) as conn:
        session_id = db.find_session_id(conn, cwd, timestamp)
        conn.execute(
            """
            INSERT INTO tool_uses
                (session_id, timestamp, cwd, tool_name, tool_args,
                 file_path, result_type, result_text,
                 estimated_input_tokens, estimated_output_tokens)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                session_id, timestamp, cwd, tool_name, tool_args,
                file_path, result_type, result_text,
                input_tokens, output_tokens,
            ),
        )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        db.log_hook_error(os.getcwd(), "post_tool_use", exc, _raw_stdin)
        print(f"[hooks/post_tool_use] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
