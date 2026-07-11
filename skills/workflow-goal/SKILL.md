---
name: workflow-goal
description: |
  Run a bounded autonomous goal loop with dynamic fan-out/fan-in research.
  Use for /workflow-goal, "workflow goal", "keep working toward this goal with parallel research",
  or when the user wants independent topics/files analyzed by separate Copilot CLI prompt-mode workers.
  Workers hand results back through files; only the parent session may edit source or complete the goal.
user-invocable: true
argument-hint: "<condition> | status | config | clear"
---

# /workflow-goal - Bounded Goal Loop with Dynamic Workflows

Set a measurable stop condition, keep working toward it, and use parallel
`copilot -p` workers when independent read-only research can shorten the path.
The parent session owns all implementation, validation, user interaction, and
the final completion decision.

This skill is separate from `/goal`. Its state lasts for the current Copilot
session only.

## Command surface

| Invocation | Action |
|---|---|
| `workflow-goal <condition>` | Set or replace the active goal and start working immediately. |
| `workflow-goal` | Show the current goal and continue it if active. |
| `workflow-goal status` | Show goal state, iteration count, and recent workflow runs. |
| `workflow-goal config` | Show effective defaults and the installed `config.json` path. |
| `workflow-goal clear` | Clear the goal. Do not report success or call `task_complete`. |

Natural-language equivalents count. Treat the complete remainder as the goal
condition unless it is exactly `status`, `config`, or `clear`.

## Non-negotiable boundaries

1. Only the parent session may modify repository files, run implementation
   commands, validate the final result, ask the user questions, or decide that
   the goal is achieved.
2. Workers are read-only researchers. They may read/search local files, search
   and fetch the web, and invoke configured read-only MCP tools. They must not
   write files, use shell commands, store memories, invoke
   `/workflow-goal`, `/goal`, `/fleet`, launch subagents, or claim completion.
   The helper also excludes the `task` and `ask_user` tools by default. Skill
   invocation itself has no dedicated CLI deny switch, so the no-recursion
   prompt rule remains a required defense-in-depth instruction.
3. Worker output is evidence, not truth. Check citations and important claims
   before using them.
4. Never mark a goal achieved without current, objective evidence.
5. Do not weaken normal Copilot guardrails to chase a goal.
6. Child sessions consume AI credits. Respect explicit user count/model
   instructions and show the chosen worker count and model before launch.

## State storage

Create these tables idempotently whenever the skill is set, read, or resumed:

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

Core operations:

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

## Goal lifecycle

### Set

1. Reject conditions longer than 4000 characters without changing state.
2. Decide whether the condition has an objective completion check before
   replacing or storing anything.
3. If it is subjective, ask once for a measurable proxy. Do not start or bump
   an iteration yet. If the answer is still non-measurable, refuse to set the
   goal with `No measurable completion criterion could be established.`
4. Extract explicit worker count, one-per-item cardinality, model, context, and
   hard-limit instructions into canonical JSON and store it in
   `prompt_overrides`:

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

Omit keys the user did not specify. Use manifest setting names (`workers`,
`model`, `context`, `hardWorkerLimit`) exactly. When `cardinality.mode` is
`per-item`, `workers` must equal `cardinality.count`.
5. If another goal is active, announce that it is being replaced.
6. Store the measurable goal and render:
   `Workflow goal set (iteration 0/50): <first 100 characters>`
7. Start the first iteration immediately.

### Status

Render one concise line followed by the latest three history entries:

- Active: `Workflow goal active (iteration N/MAX): <condition>`
- Achieved: `Workflow goal achieved: <condition>`
- Cleared: `Workflow goal cleared`
- Aborted: `Workflow goal aborted: <reason>`
- Missing: `No workflow goal set. Usage: workflow-goal <condition>`

Bare `workflow-goal` uses this same status-line format, then continues the
active goal.

### Clear

1. Set `status = 'cleared'` immediately.
2. If `last_run_status` is `starting` or `running` and
   `last_run_directory` is set, invoke:

```powershell
& "<skill-dir>\Invoke-WorkflowGoal.ps1" `
  -Mode Cancel `
  -RunDirectory "<last-run-directory>"
```

3. Record the cancellation result in history. Do not use results returned after
   the clear request.
4. Render `Workflow goal cleared` and stop. Do not call `task_complete`.

Cancellation stops the specifically recorded worker process IDs and asks the
helper to exit. Keep the cancelled run directory for diagnosis; it may be
cleaned explicitly later.

## Active iteration

For every iteration while the state is active:

1. Bump the iteration counter.
2. Render the active status line.
3. Re-evaluate the goal against fresh evidence.
4. If achieved, store the evidence, render the achieved line, and call
   `task_complete` once when that tool is available. Otherwise return the final
   completion response and stop the loop.
5. If not achieved, identify the smallest concrete next step.
6. Decide whether that step should be handled inline or through fan-out.
7. Execute the step, record its measurable result in history, and re-evaluate.
8. Update `no_progress_streak`:
   - Reset it to `0` when the iteration adds verified evidence, reduces the
     unresolved item/failure count, produces a relevant source diff, advances
     validation, or resolves a blocker.
   - Increment it by `1` when none of those changed.
   - Record `progress` or `no_progress` in history with the concrete delta.
9. Abort when `no_progress_streak >= 3`.
10. Repeat. Fan-out may occur again later in the same iteration or in any later
   iteration whenever new independent topics appear.

## Dynamic fan-out decision

Fan out when all of these are true:

- There are at least two independent topics, files, hypotheses, sources, or
  questions.
- Each worker can finish without another worker's result.
- The work is read-only research or analysis.
- Results can be merged through a stable output contract.
- Parallel startup cost is justified.

Stay inline when work is sequential, implementation-oriented, very small,
requires shared evolving context, modifies files, runs tests/builds, or needs
user clarification.

Examples that should fan out:

- Analyze 12 unrelated files for the same concern.
- Research three independent libraries.
- Compare several implementation approaches using separate evidence.
- Inspect independent failure clusters before the parent fixes them.

Examples that should remain in the parent:

- Edit code and then run its tests.
- Trace one call chain.
- Apply a migration whose later steps depend on earlier output.
- Make a design decision requiring user input.

## Prompt overrides

Resolve worker settings in this order:

1. Explicit instructions in the active user prompt or goal.
2. Explicit helper parameters.
3. `WORKFLOW_GOAL_*` environment variables.
4. Installed `config.json`.
5. Built-in defaults.

Defaults are eight concurrent workers, `claude-haiku-4.5`, and the `default`
context tier. They are not hard limits.

Interpret explicit user instructions literally:

- `use 3 workers` -> concurrency `3`.
- `one agent per file` with 41 files -> create 41 tasks and use concurrency
  `41`.
- `use gpt-5.5-mini` -> pass `gpt-5.5-mini` to `--model` exactly.
- `use long context` -> pass `long_context`.

Do not silently replace an unavailable model or reduce an explicit worker
count. Surface the CLI error and let the parent decide how to proceed. A
configured non-null `hardWorkerLimit` is the only ceiling and must be reported
before launch if it blocks the request.

## Task manifest

Before fan-out, create a JSON task manifest in the system temporary directory:

```json
{
  "runId": "goal-iteration-3-api-files",
  "goal": "All public API files have documented error behavior",
  "repository": "C:\\work\\project",
  "settings": {
    "workers": 41,
    "model": "claude-haiku-4.5",
    "context": "default"
  },
  "tasks": [
    {
      "id": "api-file-001",
      "title": "Analyze src\\Api\\Users.cs",
      "prompt": "Inspect src\\Api\\Users.cs for undocumented error behavior. Cite file and line evidence."
    }
  ]
}
```

Requirements:

- IDs are unique and match `[A-Za-z0-9][A-Za-z0-9._-]{0,63}`.
- Run IDs are unique, at most 128 characters, and include the iteration plus a
  random suffix, for example `goal-i3-api-files-a1b2c3d4`.
- Create one task per requested item when the user says one worker/agent per
  item.
- Prompts contain only the context needed for that topic.
- Do not place secrets or credentials in manifests.
- Include a concrete evidence/output request.

## Launching workers

The helper lives beside this file:

```powershell
& "<skill-dir>\Invoke-WorkflowGoal.ps1" `
  -Mode Run `
  -TasksFile "<temporary-manifest.json>"
```

The helper:

- launches `copilot -p` from the target repository;
- captures each response as `<run-dir>\<task-id>\result.md`;
- captures stderr separately;
- continuously updates `<run-dir>\run-manifest.json`;
- returns a JSON summary containing the run directory and result paths.

Before invoking it, derive the run directory from the effective artifact root
and run ID, then store `last_run_id`, `last_run_directory`, and
`last_run_status = 'starting'` in SQL. This value is sufficient for
`workflow-goal clear` to trigger cancellation. When the shell/tool API provides
an asynchronous launch acknowledgement, update it to `running`; for a
synchronous invocation, the helper's own `run-manifest.json` is the
authoritative running state. On return, store the helper's final status.

Do not launch workers directly when the helper is available.

## Worker output contract

Every generated worker prompt must require this shape:

```markdown
## Findings
- Concrete findings with file/URL/tool citations.

## Evidence
- Exact paths, line ranges, commands, URLs, or MCP sources.

## Risks and unknowns
- Missing context, uncertainty, or conflicting evidence.

## Recommended parent action
- One concise next step for the parent session.
```

The helper adds the read-only and no-recursion rules automatically.

## Fan-in

After the helper exits:

1. Read `run-manifest.json`.
2. Reject missing, malformed, or empty successful outputs.
3. For every failed, timed-out, or cancelled task, read `stderrPath` when it
   exists. Include a short sanitized cause in history and the user-visible
   failure report.
4. Read every successful `result.md`.
5. Group overlapping findings and identify conflicts.
6. Verify claims that affect edits, security, or completion.
7. Record a concise run summary and failed task IDs in
   `workflow_goal_history`.
8. For each failed task, update `workflow_goal_task_retries` using the
   lowercase SHA-256 `taskKey` emitted in the run manifest. The helper computes
   it from canonical compact JSON containing repository, task ID, trimmed
   prompt, model, context, URL policy, sorted read-only MCP servers, and sorted
   exact MCP tool permissions.
   - Reset/delete the retry row after success or changed input.
   - Do not dispatch the same unchanged task more than three times.
   - On the third unchanged failure, work inline, ask for guidance, or abort;
     never schedule a fourth identical attempt.
   - Use the helper's `succeededTaskKeys` array to batch-delete successful retry
     rows after each run.
9. Use partial successes, but retry eligible failed topics inline or in a later
   bounded fan-out. Never present partial output as complete.
10. If stderr identifies an unavailable requested model, surface the exact CLI
    error and ask for an alternative. Do not retry or substitute a model
    without user approval.
11. Continue the goal from the synthesized result.
12. If the run succeeded and `retainArtifactsOnSuccess` is false, call:

```powershell
& "<skill-dir>\Invoke-WorkflowGoal.ps1" `
  -Mode Cleanup `
  -RunDirectory "<run-dir>"
```

Keep failed/timed-out run artifacts for diagnosis.

## Safety stops

Abort without `task_complete` when any condition is met:

- The iteration count reaches the active maximum.
- Three consecutive iterations make no measurable progress.
- The same worker dispatch failure repeats three times without changed input.
  Dispatch failures include process-start exceptions, non-zero exits, empty
  output, and timeouts.
- A requested model is rejected and no user-approved alternative exists.
- A configured hard worker limit blocks the explicit request.
- Continuing requires destructive or disallowed behavior.
- The user says stop or clears the goal.

When aborting, record the reason, the latest evidence, failed task IDs, and the
next actionable recovery step.

## Completion evidence examples

- Tests pass: a current test command exited successfully after the last edit.
- Build succeeds: a current build command exited successfully.
- Every file reviewed: the fan-in manifest contains one valid result for every
  requested file and the parent resolved all reported gaps.
- Issue/PR state: a fresh GitHub query reports the required state.
- Artifact exists: inspect the file and validate its required contents.
- Subjective goal: ask once before storing or starting the goal. If the proxy
  remains subjective, do not set the goal.

## Configuration

The default configuration is `config.json` beside this file. Users may edit the
installed copy under `~\.copilot\skills\workflow-goal\config.json`.

`workflow-goal config` must show defaults, environment overrides, active
prompt overrides from the stored `prompt_overrides` JSON, the resolved artifact
root, and any configured hard worker limit. Never print secrets.
