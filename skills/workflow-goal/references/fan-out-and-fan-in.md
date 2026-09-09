# Fan-out and fan-in

## Decision

Fan out only when all are true:

- At least two topics, files, hypotheses, sources, or questions are independent.
- Each worker can finish without another worker's result.
- Work is read-only research or analysis.
- Results share a stable output contract.
- Parallel startup cost is justified.

Stay inline for sequential, implementation-oriented, very small, shared-context,
editing, build/test, or user-clarification work.

Good candidates include unrelated-file review, independent library research,
evidence-based approach comparisons, and separate failure clusters. Keep code
editing plus tests, one call-chain trace, dependent migrations, and
user-dependent design decisions in the parent.

## Worker boundary

Workers may read/search local files, search/fetch the web, and use configured
read-only MCP tools. They must not:

- write files or run implementation commands;
- store memories or ask the user questions;
- invoke workflow-goal, goal, fleet, skills recursively, or subagents;
- claim completion.

Where supported, deny task-launch and clarification tools. Because skill
invocation may lack a dedicated deny switch, the no-recursion prompt remains
required defense in depth.

## Settings

Resolve worker settings in this order:

1. Explicit active prompt or goal instructions.
2. Explicit helper parameters.
3. `WORKFLOW_GOAL_*` environment variables.
4. Installed `config.json`.
5. Built-in defaults.

Copilot launcher defaults are eight workers, `claude-haiku-4.5`, and `default`
context. They are not hard limits.

Interpret explicit instructions literally:

- `use 3 workers` means concurrency `3`.
- `one agent per file` with 41 files means 41 tasks and concurrency `41`.
- `use gpt-5.5-mini` passes that exact model.
- `use long context` means `long_context`.

Do not silently replace an unavailable model or reduce an explicit worker
count. Surface the error. Only a configured non-null `hardWorkerLimit` may cap
the request, and it must be reported before launch.

## Task contract

Create one task per requested item. IDs are unique and match
`[A-Za-z0-9][A-Za-z0-9._-]{0,63}`. Prompts contain only needed context, no
credentials, and request concrete evidence.

Every worker prompt requires:

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

## Fan-in

1. Reject missing, malformed, or empty successful outputs.
2. For failed, timed-out, or cancelled tasks, inspect available error output and
   report a short sanitized cause.
3. Read all successful results, group overlaps, and identify conflicts.
4. Verify claims that affect edits, security, or completion.
5. Record a concise run summary and failed task IDs.
6. Track retries by stable task identity. Reset after success or changed input.
   Never dispatch the same unchanged task more than three times; after the
   third failure, work inline, ask for guidance, or abort.
7. Use partial successes, but never present them as complete. Retry eligible
   topics inline or in later bounded fan-out.
8. If the requested model is unavailable, surface the exact error and request
   an alternative. Never substitute without approval.
9. Continue the goal from the synthesized result.

Copilot CLI launcher-specific manifests, task keys, artifact cleanup, and error
paths are defined in [`copilot-launcher.md`](copilot-launcher.md). Other
runtimes use their native result and retry identifiers without claiming
launcher compatibility.
