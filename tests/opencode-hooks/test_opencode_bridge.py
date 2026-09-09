from __future__ import annotations

import importlib.util
import os
import shutil
import sqlite3
import subprocess
import sys
import unittest
import uuid
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HOOKS = ROOT / "hooks"
sys.path.insert(0, str(HOOKS))
SPEC = importlib.util.spec_from_file_location("opencode_bridge", HOOKS / "opencode_bridge.py")
assert SPEC and SPEC.loader
BRIDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BRIDGE)


class OpenCodeBridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.work = Path(__file__).parent / ".work" / uuid.uuid4().hex
        self.work.mkdir(parents=True)
        self.db_path = self.work / "hooks.db"
        self.previous_db_path = os.environ.get("COPILOT_HOOKS_DB_PATH")
        os.environ["COPILOT_HOOKS_DB_PATH"] = str(self.db_path)

    def tearDown(self) -> None:
        if self.previous_db_path is None:
            os.environ.pop("COPILOT_HOOKS_DB_PATH", None)
        else:
            os.environ["COPILOT_HOOKS_DB_PATH"] = self.previous_db_path
        shutil.rmtree(self.work)

    def rows(self, table: str) -> list[sqlite3.Row]:
        connection = sqlite3.connect(self.db_path)
        connection.row_factory = sqlite3.Row
        try:
            return connection.execute(f"SELECT * FROM {table}").fetchall()
        finally:
            connection.close()

    def test_maps_session_prompt_tool_and_error_events(self) -> None:
        common = {"cwd": str(self.work), "session_id": "ses_123"}
        BRIDGE.process_event(
            {**common, "kind": "session_start", "timestamp": 100, "source": "opencode"}
        )
        BRIDGE.process_event(
            {**common, "kind": "prompt", "timestamp": 101, "prompt": "fix broken.py"}
        )
        BRIDGE.process_event(
            {
                **common,
                "kind": "pre_tool",
                "timestamp": 102,
                "tool_name": "read",
                "tool_args": {"filePath": "broken.py"},
            }
        )
        BRIDGE.process_event(
            {
                **common,
                "kind": "post_tool",
                "timestamp": 103,
                "tool_name": "read",
                "tool_args": {"path": "broken.py"},
                "result_type": "completed",
                "result_text": "contents",
            }
        )
        BRIDGE.process_event(
            {
                **common,
                "kind": "post_tool",
                "timestamp": 104,
                "tool_name": "read",
                "tool_args": {"path": "broken.py"},
                "result_type": "error",
                "result_text": "boom",
            }
        )
        BRIDGE.process_event(
            {
                **common,
                "kind": "error",
                "timestamp": 105,
                "error_name": "APIError",
                "error_message": "unavailable",
            }
        )
        BRIDGE.process_event(
            {**common, "kind": "session_end", "timestamp": 106, "reason": "idle"}
        )

        session = self.rows("sessions")[0]
        self.assertEqual("opencode", session["source"])
        self.assertEqual(106, session["end_timestamp"])
        self.assertEqual(1, self.rows("prompts")[0]["contains_error_report"])
        tool_uses = self.rows("tool_uses")
        self.assertEqual(["success", "failure"], [row["result_type"] for row in tool_uses])
        self.assertEqual("broken.py", tool_uses[0]["file_path"])
        self.assertEqual("APIError", self.rows("errors")[0]["error_name"])

        tools_report = subprocess.run(
            [
                sys.executable,
                str(HOOKS / "report.py"),
                "tools",
                "--db",
                str(self.db_path),
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        failures_report = subprocess.run(
            [
                sys.executable,
                str(HOOKS / "report.py"),
                "failures",
                "--db",
                str(self.db_path),
            ],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        self.assertRegex(tools_report, r"read\s+2\s+1\s+1")
        self.assertIn("boom", failures_report)

    def test_tolerates_unknown_event_and_missing_optional_fields(self) -> None:
        BRIDGE.process_event({"kind": "unknown", "cwd": str(self.work)})
        BRIDGE.process_event({"kind": "error", "cwd": str(self.work)})
        self.assertEqual("", self.rows("errors")[0]["error_message"])


if __name__ == "__main__":
    unittest.main()
