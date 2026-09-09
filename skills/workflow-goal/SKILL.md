---
name: workflow-goal
description: "Run a bounded autonomous goal loop with measurable completion, progress tracking, and optional parallel read-only research. Use for workflow-goal requests or when the user asks the agent to keep working toward an objective. Copilot CLI may use the bundled PowerShell launcher for copilot -p fan-out; other runtimes may use the goal-loop guidance but must not claim launcher compatibility."
user-invocable: true
argument-hint: "<condition> | status | config | clear"
---

# Workflow Goal

Set a measurable stop condition, make bounded progress toward it, and verify the
result before declaring success. The parent session owns implementation,
validation, user interaction, and the completion decision.

## Runtime gate

The goal lifecycle and safety rules are runtime-neutral. The bundled
`Invoke-WorkflowGoal.ps1` launcher and its `copilot -p` workers are **Copilot
CLI-only**.

- **Copilot CLI:** may use the launcher exactly as documented after reading the
  fan-out references.
- **OpenCode or any other runtime:** may follow the bounded goal guidance and
  may use native, read-only parallel research features when available, but must
  not invoke, emulate, or claim compatibility with `Invoke-WorkflowGoal.ps1`,
  `copilot -p`, its run manifests, or its cancellation/cleanup modes.

## Command surface

| Invocation | Action |
|---|---|
| `workflow-goal <condition>` | Set or replace the goal and start immediately. |
| `workflow-goal` | Show the current goal and continue it if active. |
| `workflow-goal status` | Show state, iteration count, and recent runs. |
| `workflow-goal config` | Show effective defaults and configuration location. |
| `workflow-goal clear` | Clear the goal without reporting success. |

Natural-language equivalents count. Unless the remainder is exactly `status`,
`config`, or `clear`, treat it as the goal condition.

## Non-negotiable boundaries

1. Only the parent may edit source, run implementation or final validation,
   ask the user questions, or decide the goal is achieved.
2. Research workers are read-only, non-recursive, and cannot claim completion.
3. Verify important worker claims; worker output is evidence, not truth.
4. Require current objective evidence before marking a goal achieved.
5. Never weaken normal runtime guardrails to pursue a goal.
6. Parallel workers consume credits. Honor explicit count/model instructions
   and show effective settings before launch.
7. Stop at the iteration, no-progress, repeated-failure, user-stop, or safety
   bounds.

## Essential workflow

1. Establish an objective completion check before storing the goal.
2. Persist state and increment the bounded iteration counter.
3. Re-evaluate against fresh evidence.
4. If incomplete, choose the smallest concrete next step.
5. Work inline unless independent read-only research justifies fan-out.
6. Record the measurable delta, update the no-progress streak, and re-evaluate.
7. Complete only with fresh evidence; otherwise continue or abort at a safety
   stop.

**Read
[`references/state-and-lifecycle.md`](references/state-and-lifecycle.md) whenever
setting, resuming, showing, clearing, completing, or aborting a goal.** It
defines SQL state, lifecycle behavior, status output, progress accounting, and
completion evidence.

**Before deciding on parallel work, read
[`references/fan-out-and-fan-in.md`](references/fan-out-and-fan-in.md).** It
defines eligibility, settings, task/output contracts, retries, and synthesis.

**Copilot CLI only: before invoking, cancelling, or cleaning up the bundled
launcher, read
[`references/copilot-launcher.md`](references/copilot-launcher.md).** Other
runtimes must not follow that launcher procedure.

Attribution and license details remain in
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).
