"""
Shared SQLite database module for Copilot hooks observability.

Database location (in priority order):
  1. COPILOT_HOOKS_DB_PATH environment variable
  2. {cwd}/observability/hooks.db

Session ID is persisted to observability/.session_id so that
all hooks within a session can correlate their records.
"""
from __future__ import annotations

import json
import os
import re
import sqlite3
from contextlib import contextmanager
from pathlib import Path


# ---------------------------------------------------------------------------
# DB path resolution
# ---------------------------------------------------------------------------

def _data_dir(cwd: str | None = None) -> Path:
    if os.environ.get("COPILOT_HOOKS_DB_PATH"):
        return Path(os.environ["COPILOT_HOOKS_DB_PATH"]).parent
    root = Path(cwd) if cwd else Path.cwd()
    return root / "observability"


def db_path(cwd: str | None = None) -> Path:
    if os.environ.get("COPILOT_HOOKS_DB_PATH"):
        return Path(os.environ["COPILOT_HOOKS_DB_PATH"])
    root = Path(cwd) if cwd else Path.cwd()
    return root / "observability" / "hooks.db"


# ---------------------------------------------------------------------------
# Session ID file helpers
# ---------------------------------------------------------------------------

def _session_file(cwd: str | None = None) -> Path:
    return _data_dir(cwd) / ".session_id"


def write_session_id(session_id: str, cwd: str | None = None) -> None:
    f = _session_file(cwd)
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(session_id, encoding="utf-8")


def read_session_id(cwd: str | None = None) -> str | None:
    f = _session_file(cwd)
    if f.exists():
        return f.read_text(encoding="utf-8").strip() or None
    return None


def clear_session_id(cwd: str | None = None) -> None:
    f = _session_file(cwd)
    if f.exists():
        f.unlink()


# ---------------------------------------------------------------------------
# Connection + schema
# ---------------------------------------------------------------------------

@contextmanager
def connect(cwd: str | None = None):
    """Yield an open SQLite connection with WAL mode and the schema ensured."""
    path = db_path(cwd)
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.execute("PRAGMA journal_mode=WAL")
    conn.row_factory = sqlite3.Row
    _ensure_schema(conn)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS sessions (
            id                TEXT    PRIMARY KEY,
            start_timestamp   INTEGER NOT NULL,
            end_timestamp     INTEGER,
            cwd               TEXT,
            source            TEXT,
            initial_prompt    TEXT,
            end_reason        TEXT,
            repository        TEXT
        );

        CREATE TABLE IF NOT EXISTS prompts (
            id                    INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id            TEXT,
            timestamp             INTEGER NOT NULL,
            cwd                   TEXT,
            prompt                TEXT,
            estimated_tokens      INTEGER,
            contains_error_report INTEGER DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS pre_tool_events (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id  TEXT,
            timestamp   INTEGER NOT NULL,
            cwd         TEXT,
            tool_name   TEXT,
            tool_args   TEXT
        );

        CREATE TABLE IF NOT EXISTS tool_uses (
            id                       INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id               TEXT,
            timestamp                INTEGER NOT NULL,
            cwd                      TEXT,
            tool_name                TEXT,
            tool_args                TEXT,
            file_path                TEXT,
            result_type              TEXT,
            result_text              TEXT,
            estimated_input_tokens   INTEGER,
            estimated_output_tokens  INTEGER
        );

        CREATE TABLE IF NOT EXISTS errors (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id    TEXT,
            timestamp     INTEGER NOT NULL,
            cwd           TEXT,
            error_name    TEXT,
            error_message TEXT,
            error_stack   TEXT
        );
    """)


# ---------------------------------------------------------------------------
# Utility helpers
# ---------------------------------------------------------------------------

_ERROR_PATTERN = re.compile(
    r"error|bug|wrong|broken|not working|doesn't work|doesnt work|fix|fail",
    re.IGNORECASE,
)


def estimate_tokens(text: str | None) -> int:
    """Estimate token count using len/3 heuristic (conservative for code/logs)."""
    if not text:
        return 0
    return max(1, len(text) // 3)


def contains_error_report(text: str | None) -> int:
    """Return 1 if the text looks like a user complaint about an error."""
    if not text:
        return 0
    return 1 if _ERROR_PATTERN.search(text) else 0


def extract_file_path(tool_name: str, tool_args_raw: str | None) -> str | None:
    """
    Try to extract a file/path from the tool arguments JSON string.

    Scans all plausible field names across every known Copilot CLI tool:
      edit, view, create, read, write, read_file, write_file  → path / file_path / uri
      glob                                                     → pattern / path / glob
      grep                                                     → path / glob / pattern
      list_directory                                           → path / dir
      bash / powershell / cmd                                  → scan .command for file tokens
      task / explore / general-purpose agents                  → prompt field (skip — no single file)
    Falls back to scanning every string value in the args for a file-like token.
    """
    if not tool_args_raw:
        return None
    try:
        args = json.loads(tool_args_raw)
    except (json.JSONDecodeError, TypeError):
        return None

    if not isinstance(args, dict):
        return None

    name_lower = (tool_name or "").lower()

    # --- Tools that deal with a single file path ---
    if name_lower in (
        "edit", "view", "create", "read", "write",
        "read_file", "write_file", "view_file",
    ):
        for field in ("path", "file_path", "filepath", "uri", "filename"):
            if v := args.get(field):
                return str(v)

    # --- Glob / pattern-based tools ---
    if name_lower in ("glob", "list_directory", "ls"):
        for field in ("pattern", "glob", "path", "dir", "directory"):
            if v := args.get(field):
                return str(v)

    # --- Grep / search tools ---
    if name_lower in ("grep", "search", "ripgrep", "search_files"):
        for field in ("path", "glob", "pattern", "dir", "directory"):
            if v := args.get(field):
                return str(v)

    # --- Shell tools: scan the command string for file-like tokens ---
    if name_lower in ("bash", "powershell", "shell", "cmd", "run", "execute"):
        command = args.get("command") or args.get("script") or ""
        match = re.search(r'[\w./\\-]+\.\w{1,10}', command)
        return match.group(0) if match else None

    # --- Fallback: scan every string value for a file-like token ---
    _file_like = re.compile(r'^[\w./\\-]+\.\w{1,10}$')
    for key, val in args.items():
        if key.lower() in ("prompt", "query", "text", "content", "description"):
            continue  # skip large text fields
        if isinstance(val, str) and _file_like.match(val.strip()):
            return val.strip()

    return None


def find_session_id(conn, cwd: str, event_timestamp: int) -> str | None:
    """
    Resolve a session ID for an event at *event_timestamp*.

    Checks the persisted .session_id file first (fast path for in-session hooks).
    Falls back to querying the sessions table when the file is absent — this
    covers the case where userPromptSubmitted fires before sessionStart writes
    the file (~3 s timing gap observed in practice).
    """
    session_id = read_session_id(cwd)
    if session_id:
        return session_id
    row = conn.execute(
        "SELECT id FROM sessions WHERE start_timestamp <= ? ORDER BY start_timestamp DESC LIMIT 1",
        (event_timestamp,),
    ).fetchone()
    return row["id"] if row else None


def log_hook_error(cwd: str, hook_name: str, exc: BaseException, raw_input: str = "") -> None:
    """Append a hook crash record to observability/hook_errors.log."""
    import traceback
    from datetime import datetime, timezone

    log_path = _data_dir(cwd) / "hook_errors.log"
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write(
                f"\n[{datetime.now(tz=timezone.utc).isoformat()}] [{hook_name}] {type(exc).__name__}: {exc}\n"
            )
            traceback.print_exc(file=fh)
            if raw_input:
                fh.write(f"  raw_input[:500]: {raw_input[:500]!r}\n")
    except OSError:
        pass  # Never crash in the error handler


def make_session_id(cwd: str, timestamp: int) -> str:
    safe_cwd = re.sub(r'[^\w]', '_', (cwd or "unknown"))[-40:]
    return f"{safe_cwd}_{timestamp}"
