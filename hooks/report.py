#!/usr/bin/env python3
"""
Copilot Hooks Observability Reporter

Usage:
  python hooks/report.py sessions   [--limit N] [--db PATH]
  python hooks/report.py tools      [--session ID] [--limit N] [--db PATH]
  python hooks/report.py files      [--tool NAME] [--limit N] [--db PATH]
  python hooks/report.py errors     [--session ID] [--limit N] [--db PATH]
  python hooks/report.py tokens     [--session ID] [--db PATH]
  python hooks/report.py prompts    [--session ID] [--limit N] [--db PATH]
  python hooks/report.py latest     [--limit N] [--db PATH]
  python hooks/report.py all-time   [--limit N] [--db PATH]
  python hooks/report.py failures   [--session ID] [--limit N] [--db PATH]
  python hooks/report.py patterns   [--limit N] [--db PATH]
  python hooks/report.py dashboard  [--limit N] [--db PATH] [--output PATH]

Options:
  --limit N      Maximum rows to display (default: 20)
  --session ID   Filter to a specific session ID
  --tool NAME    Filter to a specific tool name
  --db PATH      Override the database path
  --output PATH  Output file for dashboard (default: observability/dashboard.html)
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
# New enhanced sub-commands
# ---------------------------------------------------------------------------

# How far back (in ms) to look for the prompt that preceded a failed tool call.
_PROMPT_LOOKBACK_MS = 30_000


def cmd_failures(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    """Show failed tool calls alongside the prompt that most likely triggered them."""
    print(f"\n{'='*60}")
    print("  FAILED TOOL CALLS WITH CONTEXT")
    print(f"{'='*60}")

    where = "WHERE t.session_id = ?" if args.session else "WHERE 1=1"
    params: list = [args.session] if args.session else []

    rows = conn.execute(
        f"""
        SELECT t.timestamp,
               t.tool_name,
               t.file_path,
               t.result_text,
               t.session_id,
               (
                   SELECT p.prompt
                   FROM prompts p
                   WHERE p.session_id = t.session_id
                     AND p.timestamp  <= t.timestamp
                     AND p.timestamp  >= t.timestamp - {_PROMPT_LOOKBACK_MS}
                   ORDER BY p.timestamp DESC
                   LIMIT 1
               ) AS triggering_prompt
        FROM tool_uses t
        {where}
          AND t.result_type = 'failure'
        ORDER BY t.timestamp DESC
        LIMIT ?
        """,
        [*params, args.limit],
    ).fetchall()

    _print_table(
        ["Timestamp", "Tool", "File", "Result Snippet", "Triggering Prompt"],
        [
            [
                _ts(r["timestamp"]),
                r["tool_name"] or "?",
                _trunc(r["file_path"] or "", 30),
                _trunc(r["result_text"] or "", 50),
                _trunc(r["triggering_prompt"] or "(none in window)", 55),
            ]
            for r in rows
        ],
    )
    print(f"\n  Total shown: {len(rows)}\n")


def cmd_patterns(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    """Detect recurring error and failure patterns across all sessions."""
    print(f"\n{'='*60}")
    print("  RECURRING ERROR PATTERNS")
    print(f"{'='*60}")

    error_rows = conn.execute(
        """
        SELECT e.error_name,
               e.error_message,
               COUNT(*)                          AS occurrences,
               GROUP_CONCAT(DISTINCT t.file_path) AS affected_files
        FROM errors e
        LEFT JOIN tool_uses t
               ON t.session_id = e.session_id
              AND ABS(CAST(e.timestamp AS INTEGER) - CAST(t.timestamp AS INTEGER)) < 5000
              AND t.file_path IS NOT NULL
        GROUP BY e.error_name, e.error_message
        ORDER BY occurrences DESC
        LIMIT ?
        """,
        (args.limit,),
    ).fetchall()

    _print_table(
        ["Error Name", "Message", "Count", "Affected Files"],
        [
            [
                r["error_name"] or "?",
                _trunc(r["error_message"] or "", 45),
                r["occurrences"],
                _trunc(r["affected_files"] or "", 40),
            ]
            for r in error_rows
        ],
    )

    print(f"\n{'='*60}")
    print("  FAILURE HOT-SPOTS  (tool + file pairs)")
    print(f"{'='*60}")

    hotspot_rows = conn.execute(
        """
        SELECT tool_name,
               file_path,
               COUNT(*)       AS failures,
               MAX(timestamp) AS last_seen
        FROM tool_uses
        WHERE result_type = 'failure'
          AND file_path IS NOT NULL
        GROUP BY tool_name, file_path
        ORDER BY failures DESC
        LIMIT ?
        """,
        (args.limit,),
    ).fetchall()

    _print_table(
        ["Tool", "File", "Failures", "Last Seen"],
        [
            [
                r["tool_name"] or "?",
                _trunc(r["file_path"] or "", 45),
                r["failures"],
                _ts(r["last_seen"]),
            ]
            for r in hotspot_rows
        ],
    )
    print()


def cmd_dashboard(conn: sqlite3.Connection, args: argparse.Namespace) -> None:
    """Generate a self-contained HTML dashboard with Chart.js visualisations."""

    # ── 1. Gather data ──────────────────────────────────────────────────────

    tool_stats = conn.execute(
        """
        SELECT tool_name,
               SUM(result_type = 'success') AS ok,
               SUM(result_type = 'failure') AS fail,
               SUM(result_type = 'denied')  AS denied
        FROM tool_uses
        GROUP BY tool_name
        ORDER BY (SUM(result_type = 'failure') + SUM(result_type = 'denied')) DESC,
                 SUM(result_type = 'success') DESC
        LIMIT ?
        """,
        (args.limit,),
    ).fetchall()

    token_series = conn.execute(
        """
        SELECT s.id,
               s.start_timestamp,
               COALESCE(SUM(t.estimated_input_tokens + t.estimated_output_tokens), 0)
               + COALESCE((SELECT SUM(p.estimated_tokens) FROM prompts p WHERE p.session_id = s.id), 0)
               AS total_tokens
        FROM sessions s
        LEFT JOIN tool_uses t ON t.session_id = s.id
        GROUP BY s.id
        ORDER BY s.start_timestamp ASC
        LIMIT ?
        """,
        (args.limit,),
    ).fetchall()

    file_stats = conn.execute(
        """
        SELECT file_path, COUNT(*) AS accesses
        FROM tool_uses
        WHERE file_path IS NOT NULL
        GROUP BY file_path
        ORDER BY accesses DESC
        LIMIT ?
        """,
        (args.limit,),
    ).fetchall()

    error_timeline = conn.execute(
        """
        SELECT timestamp, error_name
        FROM errors
        ORDER BY timestamp DESC
        LIMIT ?
        """,
        (args.limit,),
    ).fetchall()

    sessions_summary = conn.execute(
        """
        SELECT id, repository, source, start_timestamp, end_timestamp, end_reason,
               substr(initial_prompt, 1, 60) AS prompt
        FROM sessions
        ORDER BY start_timestamp DESC
        LIMIT ?
        """,
        (args.limit,),
    ).fetchall()

    # Top recurring failure patterns for "Lessons Learned"
    lessons = conn.execute(
        """
        SELECT e.error_name,
               t.tool_name,
               t.file_path,
               COUNT(*) AS occurrences
        FROM errors e
        JOIN tool_uses t
          ON t.session_id = e.session_id
         AND ABS(CAST(e.timestamp AS INTEGER) - CAST(t.timestamp AS INTEGER)) < 5000
         AND t.result_type = 'failure'
        WHERE e.error_name IS NOT NULL
        GROUP BY e.error_name, t.tool_name, t.file_path
        ORDER BY occurrences DESC
        LIMIT 10
        """,
    ).fetchall()

    # ── 2. Serialise to JS-safe JSON fragments ───────────────────────────────
    import json as _json

    tool_labels = _json.dumps([r["tool_name"] for r in tool_stats])
    tool_ok     = _json.dumps([r["ok"]   or 0 for r in tool_stats])
    tool_fail   = _json.dumps([r["fail"] or 0 for r in tool_stats])
    tool_denied = _json.dumps([r["denied"] or 0 for r in tool_stats])

    token_labels = _json.dumps([_ts(r["start_timestamp"]) for r in token_series])
    token_data   = _json.dumps([r["total_tokens"] for r in token_series])

    file_labels  = _json.dumps([r["file_path"] for r in file_stats])
    file_data    = _json.dumps([r["accesses"]  for r in file_stats])

    error_points = _json.dumps([
        {"x": _ts(r["timestamp"]), "y": r["error_name"] or "unknown"}
        for r in error_timeline
    ])

    # ── 3. Build sessions table HTML ─────────────────────────────────────────
    def _esc(s: str) -> str:
        return (s or "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")

    session_rows_html = "\n".join(
        f"<tr><td>{_esc(r['id'][-20:])}</td>"
        f"<td>{_esc(r['repository'] or '?')}</td>"
        f"<td>{_esc(r['source'] or '?')}</td>"
        f"<td>{_esc(_ts(r['start_timestamp']))}</td>"
        f"<td>{_esc(_duration(r['start_timestamp'], r['end_timestamp']))}</td>"
        f"<td>{_esc(r['end_reason'] or '-')}</td>"
        f"<td>{_esc(r['prompt'] or '')}</td></tr>"
        for r in sessions_summary
    )

    # ── 4. Build "Lessons Learned" cards HTML ────────────────────────────────
    if lessons:
        cards_html = "\n".join(
            f"""<div class="card">
  <div class="card-line">When : <span>{_esc(r['tool_name'] or '?')} fails on {_esc(r['file_path'] or '(unknown file)')}</span></div>
  <div class="card-line">Error: <span>{_esc(r['error_name'] or '?')}</span></div>
  <div class="card-line">Seen : <span>{r['occurrences']}×</span></div>
</div>"""
            for r in lessons
        )
    else:
        cards_html = "<p>No correlated error+failure patterns found yet.</p>"

    # ── 5. Render HTML ───────────────────────────────────────────────────────
    generated_at = datetime.now(tz=timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Copilot Hooks Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4"></script>
<style>
  body {{ font-family: system-ui, sans-serif; background: #0d1117; color: #c9d1d9; margin: 0; padding: 1rem 2rem; }}
  h1   {{ color: #58a6ff; }}
  h2   {{ color: #79c0ff; border-bottom: 1px solid #30363d; padding-bottom: .3rem; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(480px, 1fr)); gap: 1.5rem; }}
  .chart-box {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 1rem; }}
  table {{ width: 100%; border-collapse: collapse; font-size: .85rem; }}
  th    {{ background: #21262d; color: #8b949e; text-align: left; padding: .4rem .6rem; }}
  td    {{ padding: .35rem .6rem; border-bottom: 1px solid #21262d; word-break: break-all; }}
  tr:hover td {{ background: #1c2128; }}
  .card {{ background: #161b22; border: 1px solid #30363d; border-radius: 6px;
           padding: .8rem 1rem; margin: .5rem 0; font-family: monospace; font-size: .9rem; }}
  .card-line {{ margin: .2rem 0; color: #8b949e; }}
  .card-line span {{ color: #ffa657; }}
  footer {{ margin-top: 2rem; font-size: .75rem; color: #484f58; }}
</style>
</head>
<body>
<h1>🔭 Copilot Hooks Dashboard</h1>
<p>Generated: {generated_at}</p>

<div class="grid">
  <div class="chart-box">
    <h2>Tool Success Rate</h2>
    <canvas id="toolChart"></canvas>
  </div>
  <div class="chart-box">
    <h2>Token Usage Over Time</h2>
    <canvas id="tokenChart"></canvas>
  </div>
  <div class="chart-box">
    <h2>File Heat Map (most-touched files)</h2>
    <canvas id="fileChart"></canvas>
  </div>
  <div class="chart-box">
    <h2>Error Timeline</h2>
    <canvas id="errorChart"></canvas>
  </div>
</div>

<h2 style="margin-top:2rem">Sessions</h2>
<table>
  <tr><th>Session (tail)</th><th>Repo</th><th>Source</th><th>Started</th><th>Duration</th><th>Reason</th><th>Prompt</th></tr>
  {session_rows_html}
</table>

<h2 style="margin-top:2rem">💡 Lessons Learned</h2>
{cards_html}

<footer>Powered by Copilot Hooks Observability · commandline-crew</footer>

<script>
const toolLabels  = {tool_labels};
const toolOk      = {tool_ok};
const toolFail    = {tool_fail};
const toolDenied  = {tool_denied};

new Chart(document.getElementById('toolChart'), {{
  type: 'bar',
  data: {{
    labels: toolLabels,
    datasets: [
      {{ label: 'Success', data: toolOk,     backgroundColor: '#3fb950' }},
      {{ label: 'Failure', data: toolFail,   backgroundColor: '#f85149' }},
      {{ label: 'Denied',  data: toolDenied, backgroundColor: '#d29922' }},
    ]
  }},
  options: {{ indexAxis: 'y', plugins: {{ legend: {{ labels: {{ color: '#c9d1d9' }} }} }},
             scales: {{ x: {{ stacked: true, ticks: {{ color: '#8b949e' }} }},
                        y: {{ stacked: true, ticks: {{ color: '#8b949e' }} }} }} }}
}});

new Chart(document.getElementById('tokenChart'), {{
  type: 'line',
  data: {{
    labels: {token_labels},
    datasets: [{{ label: '~Tokens', data: {token_data},
                  borderColor: '#58a6ff', backgroundColor: 'rgba(88,166,255,.15)',
                  tension: .3, fill: true }}]
  }},
  options: {{ plugins: {{ legend: {{ labels: {{ color: '#c9d1d9' }} }} }},
             scales: {{ x: {{ ticks: {{ color: '#8b949e', maxRotation: 45 }} }},
                        y: {{ ticks: {{ color: '#8b949e' }} }} }} }}
}});

new Chart(document.getElementById('fileChart'), {{
  type: 'bar',
  data: {{
    labels: {file_labels},
    datasets: [{{ label: 'Accesses', data: {file_data}, backgroundColor: '#388bfd' }}]
  }},
  options: {{ indexAxis: 'y', plugins: {{ legend: {{ labels: {{ color: '#c9d1d9' }} }} }},
             scales: {{ x: {{ ticks: {{ color: '#8b949e' }} }},
                        y: {{ ticks: {{ color: '#8b949e' }} }} }} }}
}});

// Error timeline as a simple bar chart (count per error name)
const errorRaw = {error_points};
const errCounts = {{}};
errorRaw.forEach(p => {{ errCounts[p.y] = (errCounts[p.y] || 0) + 1; }});
new Chart(document.getElementById('errorChart'), {{
  type: 'bar',
  data: {{
    labels: Object.keys(errCounts),
    datasets: [{{ label: 'Occurrences', data: Object.values(errCounts),
                  backgroundColor: '#f85149' }}]
  }},
  options: {{ indexAxis: 'y', plugins: {{ legend: {{ labels: {{ color: '#c9d1d9' }} }} }},
             scales: {{ x: {{ ticks: {{ color: '#8b949e' }} }},
                        y: {{ ticks: {{ color: '#8b949e' }} }} }} }}
}});
</script>
</body>
</html>
"""

    # ── 6. Write output ──────────────────────────────────────────────────────
    out_path = Path(getattr(args, "output", None) or dbmod.db_path().parent / "dashboard.html")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")
    print(f"\n  Dashboard written to: {out_path}")
    print(f"  Open in a browser to view charts (requires internet for Chart.js CDN).\n")


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
        choices=["sessions", "tools", "files", "errors", "tokens", "prompts",
                 "latest", "all-time", "failures", "patterns", "dashboard"],
        help="Report to run",
    )
    parser.add_argument("--limit", type=int, default=20, help="Max rows (default: 20)")
    parser.add_argument("--session", help="Filter by session ID")
    parser.add_argument("--tool", help="Filter by tool name (files command)")
    parser.add_argument("--db", help="Override database path")
    parser.add_argument("--output", help="Output file for dashboard (default: observability/dashboard.html)")

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
        "failures": cmd_failures,
        "patterns": cmd_patterns,
        "dashboard": cmd_dashboard,
    }
    dispatch[args.command](conn, args)

    conn.close()


if __name__ == "__main__":
    main()
