# Copilot CLI launcher

> **Runtime gate:** This document applies only to GitHub Copilot CLI. OpenCode
> and other runtimes must not invoke, emulate, or claim compatibility with
> `Invoke-WorkflowGoal.ps1`, `copilot -p`, or the artifacts described here.

The helper lives beside `SKILL.md` and launches `copilot -p` workers. Do not
launch workers directly while the helper is available.

## Task manifest

Create a JSON task manifest in the system temporary directory:

```json
{
  "runId": "goal-i3-api-files-a1b2c3d4",
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

- Run IDs are unique, no more than 128 characters, and contain the iteration
  plus a random suffix.
- Task IDs follow the contract in
  [`fan-out-and-fan-in.md`](fan-out-and-fan-in.md).
- Create one task per item when explicitly requested.
- Prompts request concrete evidence and contain no secrets.

## Run

```powershell
& "<skill-dir>\Invoke-WorkflowGoal.ps1" `
  -Mode Run `
  -TasksFile "<temporary-manifest.json>"
```

Before invocation, derive the run directory from the effective artifact root
and run ID. Store `last_run_id`, `last_run_directory`, and
`last_run_status = 'starting'`. After an asynchronous acknowledgement, set
`running`; for synchronous invocation, `run-manifest.json` is authoritative.
Store the final helper status on return.

The helper:

- launches `copilot -p` from the target repository;
- automatically adds read-only and no-recursion rules;
- writes each response to `<run-dir>\<task-id>\result.md`;
- writes stderr separately;
- continuously updates `<run-dir>\run-manifest.json`;
- returns JSON with the run directory and result paths.

## Fan-in details

1. Read `run-manifest.json`.
2. Reject missing, malformed, or empty successful outputs.
3. For failures, timeouts, or cancellations, read `stderrPath` when present and
   include a short sanitized cause in history and the visible report.
4. Read every successful `result.md`, synthesize it, and verify consequential
   claims.
5. Record the run summary and failed IDs.
6. Update retries using the lowercase SHA-256 `taskKey` emitted by the helper.
   It hashes canonical compact JSON containing repository, task ID, trimmed
   prompt, model, context, URL policy, sorted read-only MCP servers, and sorted
   exact MCP tool permissions.
7. Batch-delete retry rows listed in `succeededTaskKeys`. Reset a row after
   changed input. Do not dispatch an unchanged task more than three times.
8. Use partial success without claiming completeness.
9. Surface unavailable-model CLI errors exactly; do not retry or substitute
   without approval.

If the run succeeds and `retainArtifactsOnSuccess` is false:

```powershell
& "<skill-dir>\Invoke-WorkflowGoal.ps1" `
  -Mode Cleanup `
  -RunDirectory "<run-dir>"
```

Keep failed and timed-out artifacts for diagnosis.

## Cancel

After state is marked cleared, cancel only the recorded active run:

```powershell
& "<skill-dir>\Invoke-WorkflowGoal.ps1" `
  -Mode Cancel `
  -RunDirectory "<last-run-directory>"
```

Record the cancellation result and ignore later worker output. Cancellation
stops recorded worker process IDs and asks the helper to exit. Keep the run
directory for diagnosis.

## Configuration

The default configuration is `config.json` beside `SKILL.md`. Users may edit
the installed copy at `~/.copilot/skills/workflow-goal/config.json`.

`workflow-goal config` shows built-in defaults, file and environment
overrides, stored prompt overrides, resolved artifact root, and any hard worker
limit. Never print secrets.
