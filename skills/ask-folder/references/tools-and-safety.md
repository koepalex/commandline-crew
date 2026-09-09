# Tools and safety

## Allowed operations

Use only read-only, non-destructive capabilities:

- Read files and list directories.
- Search file contents and filenames.
- Fetch or search external references when the question genuinely needs them.
- Query session history or session-local scratch state without touching the
  repository.
- Ask a clarifying question when the request is ambiguous.
- Retrieve runtime documentation for questions about the runtime itself.
- Use read-only Git commands with pagers disabled: `status`, `diff`, `log`,
  `show`, `blame`, `ls-files`, and `rev-parse`.
- Use read-only MCP operations whose names and schemas clearly indicate search,
  list, get, fetch, retrieve, or validation without writes.
- Delegate only to an explicitly read-only research or review worker, and tell
  it that this skill's read-only boundary also applies.

## Runtime tool-name mapping

Tool names vary by host. Select the runtime-native equivalent by capability,
not by assuming a specific name.

| Capability | GitHub Copilot examples | OpenCode examples |
|---|---|---|
| Read files | `view` | `read` |
| Find files | `glob` | `glob` |
| Search text | `rg`, `grep` | `grep` |
| Read-only shell inspection | `bash`, `powershell` | `bash` |
| Web lookup | `web_fetch`, `web_search` | configured web/search tool |
| Session history | `session_store_sql` | configured session/history tool, if available |
| Clarification | `ask_user` or runtime prompt mechanism | runtime prompt mechanism |

If the runtime lacks a safe read-only equivalent, do not perform that step.
Never infer that an unfamiliar tool is read-only from its name alone.

## Forbidden operations

Do not invoke any capability that mutates the workspace, repository,
environment, processes, schedules, browser state, or remote services. This
includes:

- File create, edit, copy, move, rename, or delete operations.
- Shell redirection to files, downloads to disk, or scripts that write files.
- Package installation; restore; build; test; run; publish; formatting;
  migrations; servers; watchers; or process termination.
- Git or GitHub writes such as add, commit, push, reset, checkout, switch,
  merge, rebase, stash, tag, PR changes, or issue changes.
- Browser navigation, form submission, clicks, or other stateful automation.
- Schedule management.
- Artifact-producing skills such as document, spreadsheet, slide, diagram, or
  expense-report generation.
- General-purpose, implementation, quality, or knowledge-base agents that may
  write.

Examples of forbidden PowerShell commands include `Remove-Item`, `New-Item`,
`Set-Content`, `Out-File`, `Copy-Item`, `Move-Item`, and `Rename-Item`.

If a tool combines read and write behavior or its safety is unclear, do not use
it. If the user later asks to apply a change, handle that as a new task outside
this skill.
