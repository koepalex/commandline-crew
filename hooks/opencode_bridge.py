#!/usr/bin/env python3
"""Translate normalized OpenCode plugin events into the existing hooks database."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent))
import db

_MAX_RESULT_LEN = 4000
_RESULT_TYPE_ALIASES = {
    "completed": "success",
    "error": "failure",
    "success": "success",
    "failure": "failure",
    "denied": "denied",
}


def _integer(value: Any, default: int = 0) -> int:
    return value if isinstance(value, int) and not isinstance(value, bool) else default


def _text(value: Any, default: str = "") -> str:
    return value if isinstance(value, str) else default


def _json_text(value: Any) -> str:
    if isinstance(value, str):
        return value
    if value is None:
        return ""
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def _result_type(value: Any) -> str:
    raw = _text(value).lower()
    return _RESULT_TYPE_ALIASES.get(raw, raw)


def process_event(data: dict[str, Any]) -> None:
    """Persist one normalized event. Unknown events and absent fields are harmless."""
    kind = _text(data.get("kind"))
    cwd = _text(data.get("cwd"), os.getcwd()) or os.getcwd()
    timestamp = _integer(data.get("timestamp"))
    session_id = _text(data.get("session_id")) or None

    with db.connect(cwd) as conn:
        if kind == "session_start":
            if not session_id:
                session_id = db.make_session_id(cwd, timestamp)
            conn.execute(
                """
                INSERT OR REPLACE INTO sessions
                    (id, start_timestamp, cwd, source, initial_prompt, repository)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    session_id,
                    timestamp,
                    cwd,
                    _text(data.get("source"), "opencode"),
                    _text(data.get("initial_prompt")) or None,
                    Path(cwd).name,
                ),
            )
            return

        if kind == "session_end":
            if session_id:
                conn.execute(
                    """
                    UPDATE sessions SET end_timestamp = ?, end_reason = ? WHERE id = ?
                    """,
                    (timestamp, _text(data.get("reason"), "unknown"), session_id),
                )
            return

        if kind == "prompt":
            prompt = _text(data.get("prompt"))
            conn.execute(
                """
                INSERT INTO prompts
                    (session_id, timestamp, cwd, prompt, estimated_tokens, contains_error_report)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    session_id,
                    timestamp,
                    cwd,
                    prompt,
                    db.estimate_tokens(prompt),
                    db.contains_error_report(prompt),
                ),
            )
            return

        tool_name = _text(data.get("tool_name"))
        tool_args = _json_text(data.get("tool_args"))
        if kind == "pre_tool":
            conn.execute(
                """
                INSERT INTO pre_tool_events
                    (session_id, timestamp, cwd, tool_name, tool_args)
                VALUES (?, ?, ?, ?, ?)
                """,
                (session_id, timestamp, cwd, tool_name, tool_args),
            )
            return

        if kind == "post_tool":
            result_text = _text(data.get("result_text"))[:_MAX_RESULT_LEN]
            conn.execute(
                """
                INSERT INTO tool_uses
                    (session_id, timestamp, cwd, tool_name, tool_args,
                     file_path, result_type, result_text,
                     estimated_input_tokens, estimated_output_tokens)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    session_id,
                    timestamp,
                    cwd,
                    tool_name,
                    tool_args,
                    db.extract_file_path(tool_name, tool_args),
                    _result_type(data.get("result_type")),
                    result_text,
                    db.estimate_tokens(tool_args),
                    db.estimate_tokens(result_text),
                ),
            )
            return

        if kind == "error":
            conn.execute(
                """
                INSERT INTO errors
                    (session_id, timestamp, cwd, error_name, error_message, error_stack)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    session_id,
                    timestamp,
                    cwd,
                    _text(data.get("error_name")),
                    _text(data.get("error_message")),
                    _text(data.get("error_stack")),
                ),
            )


def main() -> None:
    raw = sys.stdin.read()
    data = json.loads(raw) if raw.strip() else {}
    if isinstance(data, dict):
        process_event(data)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        db.log_hook_error(os.getcwd(), "opencode_bridge", exc)
        print(f"[hooks/opencode_bridge] ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
