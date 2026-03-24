#!/usr/bin/env python3
"""
Copilot Hooks Observability Reporter

Usage:
  python hooks/report.py sessions  [--limit N] [--db PATH]
  python hooks/report.py tools     [--session ID] [--limit N] [--db PATH]
  python hooks/report.py files     [--tool NAME] [--limit N] [--db PATH]
  python hooks/report.py errors    [--session ID] [--limit N] [--db PATH]
  python hooks/report.py tokens    [--session ID] [--db PATH]
  python hooks/report.py prompts   [--session ID] [--limit N] [--db PATH]
  python hooks/report.py latest    [--limit N] [--db PATH]
  python hooks/report.py all-time  [--limit N] [--db PATH]

Options:
  --limit N     Maximum rows to display (default: 20)
  --session ID  Filter to a specific session ID
  --tool NAME   Filter to a specific tool name
  --db PATH     Override the database path
"""
from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import db as dbmod


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------

def _ts(ms: int | None) -> str:
    if not ms:
        return "-"
    dt = datetime.fromtimestamp(ms / 1000, tz=timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M:%S UTC")


def _duration(start_ms: int | None, end_ms: int | None) -> str:
    if not start_ms or not end_ms:
        return "-"
    secs = (end_ms - start_ms) / 1000
    if secs < 60:
        return f"{secs:.0f}s"
    return f"{secs / 60:.1f}m"


def _trunc(text: str | None, width: int = 60) -> str:
    if not text:
        return ""
    text = text.replace("\n", " ").strip()
    return text[:width] + "…" if len(text) > width else text


def _col_widths(headers: list[str], rows: list[list]) -> list[int]:
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(str(cell)))
    return widths


def _print_table(headers: list[str], rows: list[list]) -> None:
    if not rows:
        print("  (no data)")
        return
    widths = _col_widths(headers, rows)
    fmt = "  " + "  ".join(f"{{:<{w}}}" for w in widths)
    sep = "  " + "  ".join("-" * w for w in widths)
    print(fmt.format(*headers))
    print(sep)
    for row in rows:
        print(fmt.format(*[str(c) for c in row]))


# ---------------------------------------------------------------------------
# Sub-commands
# ---------------------------------------------------------------------------

def cmd_sessions(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    print(f"\n{'='*60}")
    print("  SESSIONS")
    print(f"{'='*60}")
    rows = conn.execute(
        """
        SELECT id, repository, source, start_timestamp, end_timestamp, end_reason,
               substr(initial_prompt, 1, 50) AS prompt
        FROM sessions
        ORDER BY start_timestamp DESC
        LIMIT ?
        """,
        (args.limit,),
    ).fetchall()

    table = [
        [
            r["id"][-20:],
            r["repository"] or "?",
            r["source"] or "?",
            _ts(r["start_timestamp"]),
            _duration(r["start_timestamp"], r["end_timestamp"]),
            r["end_reason"] or "-",
            _trunc(r["prompt"], 40),
        ]
        for r in rows
    ]
    _print_table(
        ["Session (tail)", "Repo", "Source", "Started", "Duration", "Reason", "Initial Prompt"],
        table,
    )
    print(f"\n  Total shown: {len(rows)}\n")


def cmd_tools(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    print(f"\n{'='*60}")
    print("  TOOL USAGE STATISTICS")
    print(f"{'='*60}")

    where = "WHERE session_id = ?" if args.session else ""
    params = [args.session] if args.session else []

    rows = conn.execute(
        f"""
        SELECT tool_name,
               COUNT(*)                                        AS total,
               SUM(result_type = 'success')                   AS ok,
               SUM(result_type = 'failure')                   AS fail,
               SUM(result_type = 'denied')                    AS denied,
               SUM(estimated_input_tokens)                    AS in_tok,
               SUM(estimated_output_tokens)                   AS out_tok
        FROM tool_uses
        {where}
        GROUP BY tool_name
        ORDER BY total DESC
        LIMIT ?
        """,
        [*params, args.limit],
    ).fetchall()

    _print_table(
        ["Tool", "Total", "OK", "Fail", "Denied", "~In Tokens", "~Out Tokens"],
        [[r["tool_name"], r["total"], r["ok"], r["fail"], r["denied"],
          r["in_tok"] or 0, r["out_tok"] or 0]
         for r in rows],
    )
    print()


def cmd_files(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    print(f"\n{'='*60}")
    print("  FILES MOST TOUCHED")
    print(f"{'='*60}")

    where = "WHERE tool_name = ?" if args.tool else "WHERE file_path IS NOT NULL"
    if args.tool:
        where += " AND file_path IS NOT NULL"
    params = [args.tool] if args.tool else []

    rows = conn.execute(
        f"""
        SELECT file_path,
               COUNT(*)                        AS accesses,
               COUNT(DISTINCT tool_name)       AS distinct_tools,
               GROUP_CONCAT(DISTINCT tool_name) AS tools,
               SUM(result_type = 'failure')    AS failures
        FROM tool_uses
        {where}
        GROUP BY file_path
        ORDER BY accesses DESC
        LIMIT ?
        """,
        [*params, args.limit],
    ).fetchall()

    _print_table(
        ["File Path", "Accesses", "Tools Used", "Tool Names", "Failures"],
        [[r["file_path"], r["accesses"], r["distinct_tools"],
          _trunc(r["tools"], 30), r["failures"]]
         for r in rows],
    )
    print()


def cmd_errors(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    print(f"\n{'='*60}")
    print("  ERRORS")
    print(f"{'='*60}")

    where = "WHERE session_id = ?" if args.session else ""
    params = [args.session] if args.session else []

    rows = conn.execute(
        f"""
        SELECT timestamp, error_name, error_message, session_id
        FROM errors
        {where}
        ORDER BY timestamp DESC
        LIMIT ?
        """,
        [*params, args.limit],
    ).fetchall()

    _print_table(
        ["Timestamp", "Error Name", "Message", "Session (tail)"],
        [[_ts(r["timestamp"]), r["error_name"] or "?",
          _trunc(r["error_message"], 50), (r["session_id"] or "")[-20:]]
         for r in rows],
    )
    print()


def cmd_tokens(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    print(f"\n{'='*60}")
    print("  TOKEN ESTIMATES PER SESSION")
    print(f"{'='*60}")

    where = "WHERE s.id = ?" if args.session else ""
    params = [args.session] if args.session else []

    # Correlated subqueries avoid a cartesian product (N prompts x M tool_uses = NxM rows).
    rows = conn.execute(
        f"""
        SELECT s.id,
               s.repository,
               (SELECT COALESCE(SUM(p.estimated_tokens), 0)
                FROM prompts p WHERE p.session_id = s.id)                       AS prompt_tokens,
               (SELECT COALESCE(SUM(t.estimated_input_tokens + t.estimated_output_tokens), 0)
                FROM tool_uses t WHERE t.session_id = s.id)                     AS tool_tokens,
               (SELECT COALESCE(SUM(p.estimated_tokens), 0)
                FROM prompts p WHERE p.session_id = s.id)
               + (SELECT COALESCE(SUM(t.estimated_input_tokens + t.estimated_output_tokens), 0)
                  FROM tool_uses t WHERE t.session_id = s.id)                   AS total_tokens,
               (SELECT COUNT(*) FROM tool_uses t WHERE t.session_id = s.id)     AS tool_calls
        FROM sessions s
        {where}
        ORDER BY total_tokens DESC
        LIMIT ?
        """,
        [*params, args.limit],
    ).fetchall()

    _print_table(
        ["Session (tail)", "Repo", "Prompt Tokens", "Tool Tokens", "Total Tokens", "Tool Calls"],
        [[r["id"][-20:], r["repository"] or "?",
          r["prompt_tokens"], r["tool_tokens"], r["total_tokens"], r["tool_calls"]]
         for r in rows],
    )
    print()


def cmd_prompts(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    print(f"\n{'='*60}")
    print("  USER PROMPTS")
    print(f"{'='*60}")

    where = "WHERE session_id = ?" if args.session else ""
    params = [args.session] if args.session else []

    rows = conn.execute(
        f"""
        SELECT timestamp, contains_error_report, estimated_tokens, prompt, session_id
        FROM prompts
        {where}
        ORDER BY timestamp DESC
        LIMIT ?
        """,
        [*params, args.limit],
    ).fetchall()

    _print_table(
        ["Timestamp", "Error?", "~Tokens", "Prompt", "Session (tail)"],
        [[_ts(r["timestamp"]),
          "YES" if r["contains_error_report"] else "no",
          r["estimated_tokens"],
          _trunc(r["prompt"], 60),
          (r["session_id"] or "")[-20:]]
         for r in rows],
    )

    if rows:
        error_count = sum(1 for r in rows if r["contains_error_report"])
        print(f"\n  Error complaints: {error_count}/{len(rows)} prompts shown\n")


# ---------------------------------------------------------------------------
# Overview commands (composite views)
# ---------------------------------------------------------------------------

def _make_args(base: argparse.Namespace, **overrides) -> argparse.Namespace:
    """Return a shallow copy of *base* with the given keyword overrides applied."""
    ns = argparse.Namespace(**vars(base))
    for k, v in overrides.items():
        setattr(ns, k, v)
    return ns


def cmd_latest(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    # Prefer the session with the most pre_tool_events (i.e. most actual work done).
    # Fall back to most-recent by start_timestamp so short "tail" sessions (e.g. a
    # 2-second task_complete blip) don't shadow a long preceding work session.
    row = conn.execute(
        """
        SELECT s.id, s.repository, s.source, s.start_timestamp, s.end_timestamp,
               s.end_reason, s.initial_prompt,
               COUNT(p.id) AS tool_event_count
        FROM sessions s
        LEFT JOIN pre_tool_events p ON p.session_id = s.id
        GROUP BY s.id
        ORDER BY tool_event_count DESC, s.start_timestamp DESC
        LIMIT 1
        """
    ).fetchone()

    if not row:
        print("\n  (no sessions recorded yet)\n")
        return

    session_id = row["id"]
    print(f"\n{'='*60}")
    print("  LATEST SESSION - FULL OVERVIEW")
    print(f"{'='*60}")
    print(f"  Session : {session_id}")
    print(f"  Repo    : {row['repository'] or '?'}")
    print(f"  Source  : {row['source'] or '?'}")
    print(f"  Started : {_ts(row['start_timestamp'])}")
    print(f"  Duration: {_duration(row['start_timestamp'], row['end_timestamp'])}")
    print(f"  Reason  : {row['end_reason'] or '-'}")
    print(f"  Prompt  : {_trunc(row['initial_prompt'], 70)}")

    scoped = _make_args(args, session=session_id, tool=None)
    cmd_tools(conn, scoped)
    cmd_files(conn, scoped)
    cmd_tokens(conn, scoped)
    cmd_errors(conn, scoped)
    cmd_prompts(conn, scoped)


def cmd_alltime(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    stats = conn.execute(
        """
        SELECT COUNT(DISTINCT s.id)                                                AS sessions,
               MIN(s.start_timestamp)                                              AS first_ts,
               MAX(s.start_timestamp)                                              AS last_ts,
               COUNT(t.id)                                                         AS tool_calls,
               COALESCE(SUM(t.estimated_input_tokens + t.estimated_output_tokens), 0) AS tool_tokens,
               COALESCE(SUM(p.estimated_tokens), 0)                               AS prompt_tokens,
               SUM(t.result_type = 'failure')                                      AS failures,
               SUM(t.result_type = 'denied')                                       AS denied
        FROM sessions s
        LEFT JOIN tool_uses t ON t.session_id = s.id
        LEFT JOIN prompts p   ON p.session_id = s.id
        """
    ).fetchone()

    print(f"\n{'='*60}")
    print("  ALL-TIME OVERVIEW")
    print(f"{'='*60}")
    print(f"  Sessions    : {stats['sessions']}")
    print(f"  Date range  : {_ts(stats['first_ts'])}  ->  {_ts(stats['last_ts'])}")
    print(f"  Tool calls  : {stats['tool_calls']}  "
          f"(failures: {stats['failures'] or 0}, denied: {stats['denied'] or 0})")
    total_tokens = (stats['tool_tokens'] or 0) + (stats['prompt_tokens'] or 0)
    print(f"  ~Tokens     : {total_tokens:,}  "
          f"(prompt: {stats['prompt_tokens'] or 0:,}, tool: {stats['tool_tokens'] or 0:,})")

    global_args = _make_args(args, session=None, tool=None)
    cmd_sessions(conn, global_args)
    cmd_tools(conn, global_args)
    cmd_files(conn, global_args)
    cmd_tokens(conn, global_args)
    cmd_errors(conn, global_args)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Copilot hooks observability reporter",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "command",
        choices=["sessions", "tools", "files", "errors", "tokens", "prompts", "latest", "all-time"],
        help="Report to run",
    )
    parser.add_argument("--limit", type=int, default=20, help="Max rows (default: 20)")
    parser.add_argument("--session", help="Filter by session ID")
    parser.add_argument("--tool", help="Filter by tool name (files command)")
    parser.add_argument("--db", help="Override database path")

    args = parser.parse_args()

    # Resolve DB path
    if args.db:
        os.environ["COPILOT_HOOKS_DB_PATH"] = args.db

    path = dbmod.db_path()
    if not path.exists():
        print(f"No database found at: {path}")
        print("Run a Copilot session with hooks enabled first.")
        sys.exit(1)

    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row

    print(f"  Database: {path}")

    dispatch = {
        "sessions": cmd_sessions,
        "tools": cmd_tools,
        "files": cmd_files,
        "errors": cmd_errors,
        "tokens": cmd_tokens,
        "prompts": cmd_prompts,
        "latest": cmd_latest,
        "all-time": cmd_alltime,
    }
    dispatch[args.command](conn, args)

    conn.close()


if __name__ == "__main__":
    main()
