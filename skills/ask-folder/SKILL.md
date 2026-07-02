---
name: ask-folder
description: "Answer questions about the contents, structure, purpose, or behavior of the current working directory using ONLY read-only, non-destructive tools. Use whenever the user asks a question about files, code, configuration, or documentation in the folder they're working in and does NOT want changes made. Triggers include phrases like 'what does this do', 'how does X work', 'explain', 'where is Y defined', 'why', 'summarize this repo/folder/project', 'ask about', 'question about', or any diagnostic / exploratory question about the workspace. Do NOT use when the user wants to create, edit, delete, refactor, format, build, run, install, or otherwise perform a side-effecting action."
---

# Ask Folder Skill

Answer the user's question about the current working directory using **only read-only, non-destructive tools**. Deliver a concise, high-signal answer grounded in the actual files.

## When to Use

- The user asks about the purpose, structure, or behavior of the current folder / repo / project.
- The user asks how something works, where something is defined, or why the code is written a certain way.
- The user asks for a summary, overview, or explanation of any part of the workspace.
- Any exploratory or diagnostic question that does not require modifying files.

## When NOT to Use

- The user asks you to change, create, delete, refactor, format, rename, or move files.
- The user asks you to run a build, install packages, apply migrations, format code, or commit / push.
- The user asks you to start a server, apply changes on disk, or run tests that mutate state.

If the request mixes a question with an action, first answer the question, then ask before performing the action.

## Allowed Tools (non-destructive only)

You may freely use:

- `view` — read files.
- `grep` — search file contents.
- `glob` — find files by name pattern.
- `web_fetch`, `web_search` — external references when the question genuinely needs them.
- `session_store_sql` — recall past sessions in this repo for context.
- `sql` — session-local scratch state (todos, notes) — this does not touch the repo.
- `ask_user` — ask a clarifying question when the request is ambiguous.
- `fetch_copilot_cli_documentation` — for questions about the CLI itself.
- Read-only MCP tools, e.g. `context7-*`, `mslearn-*`, `github-mcp-server-get_*` / `search_*` / `list_*`, `opcua-kb-tools-*` search / list / get, `fluent-agent-search_*` / `list_*` / `validate_*`.
- `task` with agent type `explore`, `research`, `code-review`, `rubber-duck`, `security-review`, or `knowledgebase-wizard` — only when a subproblem clearly benefits from a separate context window. Instruct the sub-agent that it is also in read-only mode.
- `powershell` for **read-only** inspection only: `git --no-pager` read commands (`log`, `status`, `diff`, `show`, `blame`, `ls-files`, `rev-parse`), `Get-ChildItem`, `Get-Command`, `Get-Process`, and similar. Always disable pagers.
- `read_powershell`, `list_powershell`, `read_agent`, `list_agents`, `tool_search_tool_regex`, `vote_memory`, `store_memory`.

## Forbidden Actions

Do NOT invoke any tool that mutates the workspace, repository, or environment:

- `edit`, `create` — never modify or create files anywhere in the repo.
- `powershell` commands that write, delete, install, build, format, commit, push, tag, checkout a different branch, or start long-running services. Specifically avoid: `Remove-Item`, `New-Item`, `Set-Content`, `Out-File`, `Copy-Item`, `Move-Item`, `Rename-Item`, `Invoke-WebRequest -OutFile`, `npm install`, `pip install`, `dotnet restore/build/test/run/publish`, `git add/commit/push/reset/checkout/switch/merge/rebase/stash`, `gh pr create/comment/merge/close`, redirect operators (`>`, `>>`, `|` into a file), and any script that starts a server or watcher.
- `stop_powershell` — never kill processes.
- `manage_schedule` — do not create or modify schedules.
- `task` with agent type `task`, `general-purpose`, `quality-pal`, or `kb-manager` — these can make changes.
- Any MCP tool that writes or performs an action, including `playwright-browser_*` navigation, form fills, or clicks. Browser tools are off-limits for this skill.
- Any skill invocation that would produce or edit an artifact (`docx`, `xlsx`, `pptx`, `excalidraw`, `loop`, `web-artifacts-builder`, `expense-report`).

If you notice a change that _should_ be made, describe it in the answer — do not apply it. If the user then asks you to apply it, that becomes a new task outside this skill.

## How to Investigate

1. **Orient first.** Skim the top-level layout: `README*`, `AGENTS*`, `CONTRIBUTING*`, manifest files (`package.json`, `*.csproj`, `*.sln`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `pom.xml`, `build.gradle*`), and the top-level directory listing. This tells you what kind of project it is before you dive deeper.
2. **Search before speculating.** Use `grep` / `glob` to locate specific symbols, functions, config keys, or filenames the user mentions. Prefer `grep` with a `glob` filter over broad content scans.
3. **Read in parallel.** When you need several files or several ranges of one file, batch all `view` calls in a single response.
4. **Follow the imports.** For "how does X work" questions, trace from the entry point (or the referenced symbol) through the call graph rather than guessing.
5. **Use git history sparingly** — only when the question is about change history, blame, or recent activity. Always pass `--no-pager`.
6. **Consult memories and past sessions** via `session_store_sql` when the question is about prior work in this repo, but keep queries narrow (add a time filter and a `session_id` or `ref_type` filter — never ILIKE-scan `turns` or `events` without one).
7. **Stop when the answer is grounded.** Do not chase every lead once the user's question is answered.

## How to Answer

- **Lead with the direct answer** in 1–3 sentences.
- **Cite concrete files** by relative path, and line numbers when helpful (e.g. `src/foo.ts:42-58`).
- **Quote sparingly** — a short snippet is fine when it makes the answer clearer; otherwise summarise.
- **Be concise.** Prefer short prose. Use bullets or small tables only when they add signal. Do not restate the question, do not pad, do not add a "Summary" section for a short answer.
- **Say when you're unsure.** If the files don't clearly support an answer, say so and point at what you did find.
- **Do not volunteer to make changes.** You may briefly note what a fix would look like, but do not offer to implement it unless the user asks in a follow-up.

## Output Shape

- Short question → 1–3 sentence answer, optionally followed by 1–3 file citations.
- Medium question → direct answer, then a short "Details" or "Where it lives" section with citations.
- Broad question (e.g. "explain this repo") → a compact overview: what it is, primary tech, entry points, and the top-level directory map. Skip anything that is not clearly relevant.

Stop as soon as the question is answered.
