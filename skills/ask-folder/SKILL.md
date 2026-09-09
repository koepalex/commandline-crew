---
name: ask-folder
description: "Answer questions about the current workspace using only read-only, non-destructive tools. Use for explanations, repository summaries, diagnostics, symbol lookup, and questions about files, code, configuration, or documentation. Do not use for requests that create, edit, delete, build, run, install, or otherwise cause side effects."
---

# Ask Folder

Answer questions about the current workspace with concise conclusions grounded
in the files. This skill is strictly read-only.

## Safety boundary

- Never modify the workspace, repository, environment, processes, schedules, or
  remote services.
- Do not build, test, run, install, format, commit, push, start services, or
  invoke an agent or skill that can make changes.
- If a request mixes explanation with an action, answer only the question and
  explain that the action is outside this skill.
- Describe a needed change rather than applying it.

**Before using any tool, read
[`references/tools-and-safety.md`](references/tools-and-safety.md).** It defines
the allowed tool categories, runtime-specific tool-name mapping, and forbidden
operations.

## Essential workflow

1. Orient from the top-level layout, project documentation, and manifests.
2. Search for the named file, symbol, or configuration before speculating.
3. Read the smallest relevant set of files and trace imports or calls when
   behavior is involved.
4. Use history or external sources only when the question requires them.
5. Stop once the answer is supported by evidence.
6. Lead with the direct answer and cite relative paths and useful line ranges.

**Read
[`references/investigation-and-answering.md`](references/investigation-and-answering.md)
before investigating or composing the answer.** It contains the complete
investigation procedure, citation guidance, and output shapes.
