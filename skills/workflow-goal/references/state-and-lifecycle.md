# State and lifecycle

## Runtime state mapping

In Copilot CLI, use the session-local SQL tool. In another runtime, use an
equivalent session-scoped persistent store if available. If no such store
exists, keep explicit in-session state and disclose that it will not survive
context loss. Do not create repository files as a substitute.

Create these tables idempotently whenever the goal is set, read, or resumed:

```sql
CREATE TABLE IF NOT EXISTS workflow_goal_state (
  id                 INTEGER PRIMARY KEY CHECK (id = 1),
  condition          TEXT NOT NULL,
  status             TEXT NOT NULL DEFAULT 'active',
  set_at             TEXT NOT NULL,
  completed_at       TEXT,
  iterations         INTEGER NOT NULL DEFAULT 0,
  max_iterations     INTEGER NOT NULL DEFAULT 50,
  no_progress_streak INTEGER NOT NULL DEFAULT 0,
  last_check         TEXT,
  last_run_id        TEXT,
  last_run_directory TEXT,
  last_run_status    TEXT,
  prompt_overrides   TEXT,
  evidence           TEXT,
  notes              TEXT
);

CREATE TABLE IF NOT EXISTS workflow_goal_history (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
  iteration   INTEGER NOT NULL,
  event_type  TEXT NOT NULL,
  run_id      TEXT,
  summary     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS workflow_goal_task_retries (
  task_key       TEXT PRIMARY KEY,
  attempts       INTEGER NOT NULL DEFAULT 0,
  last_failure   TEXT,
  last_attempt   TEXT NOT NULL DEFAULT (datetime('now'))
);
```

Valid states are `active`, `achieved`, `cleared`, and `aborted`.

```sql
-- Set or replace
INSERT OR REPLACE INTO workflow_goal_state
  (id, condition, status, set_at, iterations, max_iterations,
   no_progress_streak, prompt_overrides, notes)
VALUES
  (1, ?, 'active', datetime('now'), 0, 50, 0, ?, NULL);

-- A replaced/restarted goal gets a fresh retry budget
DELETE FROM workflow_goal_task_retries;

-- Bump before each active iteration
UPDATE workflow_goal_state
SET iterations = iterations + 1,
    last_check = datetime('now')
WHERE id = 1 AND status = 'active';

-- Record progress
INSERT INTO workflow_goal_history
  (iteration, event_type, run_id, summary)
VALUES (?, ?, ?, ?);

-- Achieve
UPDATE workflow_goal_state
SET status = 'achieved',
    completed_at = datetime('now'),
    evidence = ?
WHERE id = 1;

-- Clear or abort
UPDATE workflow_goal_state SET status = 'cleared' WHERE id = 1;
UPDATE workflow_goal_state
SET status = 'aborted',
    notes = COALESCE(notes, '') || ?
WHERE id = 1;
```

## Set

1. Reject conditions longer than 4000 characters without changing state.
2. Decide whether the condition has an objective completion check before
   replacing or storing anything.
3. If subjective, ask once for a measurable proxy. Do not start or increment an
   iteration. If it remains non-measurable, refuse with:
   `No measurable completion criterion could be established.`
4. Extract explicit worker count, one-per-item cardinality, model, context, and
   hard-limit instructions into canonical JSON in `prompt_overrides`:

```json
{
  "workers": 41,
  "cardinality": {
    "mode": "per-item",
    "itemType": "file",
    "count": 41
  },
  "model": "gpt-5.5-mini",
  "context": "default",
  "hardWorkerLimit": null
}
```

Omit unspecified keys. Use manifest names `workers`, `model`, `context`, and
`hardWorkerLimit` exactly. For `per-item`, `workers` equals
`cardinality.count`.

5. Announce replacement of an existing active goal.
6. Store the goal and render:
   `Workflow goal set (iteration 0/50): <first 100 characters>`
7. Start the first iteration immediately.

## Status

Render one concise line, then the latest three history entries:

- Active: `Workflow goal active (iteration N/MAX): <condition>`
- Achieved: `Workflow goal achieved: <condition>`
- Cleared: `Workflow goal cleared`
- Aborted: `Workflow goal aborted: <reason>`
- Missing: `No workflow goal set. Usage: workflow-goal <condition>`

Bare `workflow-goal` uses the same status line and then continues an active
goal.

## Clear

1. Set `status = 'cleared'` immediately.
2. In Copilot CLI only, if the last launcher run is `starting` or `running` and
   has a directory, follow the cancellation procedure in
   [`copilot-launcher.md`](copilot-launcher.md).
3. Record the cancellation result. Ignore results returned after the clear.
4. Render `Workflow goal cleared` and stop. Do not invoke the runtime's task
   completion action.

Other runtimes cancel only their own native workers using documented native
mechanisms. They must not use the bundled launcher.

## Active iteration

1. Increment the iteration counter.
2. Render the active status line.
3. Re-evaluate the goal against fresh evidence.
4. If achieved, store evidence, render the achieved line, and invoke the
   runtime's task-completion action once when available. Otherwise return the
   final completion response and stop.
5. If incomplete, identify the smallest concrete next step.
6. Decide whether to work inline or fan out.
7. Execute, record the measurable result, and re-evaluate.
8. Reset `no_progress_streak` to `0` when the iteration adds verified evidence,
   reduces unresolved items/failures, creates a relevant source diff, advances
   validation, or resolves a blocker. Otherwise increment it and record
   `progress` or `no_progress` with the concrete delta.
9. Abort at `no_progress_streak >= 3`.
10. Repeat. New independent topics may justify later fan-out.

## Safety stops

Abort without task completion when:

- The iteration count reaches the active maximum.
- Three consecutive iterations make no measurable progress.
- The same unchanged worker dispatch fails three times. Dispatch failures
  include start exceptions, non-zero exits, empty output, and timeouts.
- A requested model is rejected without a user-approved alternative.
- A configured hard worker limit blocks an explicit request.
- Continuing requires destructive or disallowed behavior.
- The user stops or clears the goal.

Record the reason, latest evidence, failed task IDs, and next recovery step.

## Completion evidence

Examples:

- Tests pass after the last edit with a current successful command.
- A current build succeeds.
- Every requested file has a valid research result and the parent resolves all
  gaps.
- A fresh GitHub query reports the required issue or PR state.
- The artifact exists and its required content validates.
- A subjective request has been converted to an objective proxy before work
  begins.
