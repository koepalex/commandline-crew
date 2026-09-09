![commandline-crew logo](./docs/images/commandline-crew.png)

# commandline-crew

Your AI-powered dev team in the terminal — a curated collection of specialized
agents and skills for
[GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli) and
[OpenCode](https://opencode.ai/), designed to work together on real engineering
tasks.

---

## What's in This Repo?

Five specialized agents, the MCP servers they depend on, install/uninstall scripts, and a knowledge base system — all ready to drop into your workflow.

| Agent | Role | Model |
|-------|------|-------|
| [`@dotnet-bot`](#dotnet-bot) | C# / .NET 10 implementation expert | claude-sonnet-4.6 |
| [`@quality-pal`](#quality-pal) | Code quality, linting, builds & tests | claude-sonnet-4.6 |
| [`@deep-thought`](#deep-thought) | Architecture consultant & system design | claude-opus-4.6 |
| [`@knowledgebase-wizard`](#knowledgebase-wizard) | Documentation & library research | claude-haiku-4.5 |
| [`@kb-manager`](#kb-manager) | Knowledge base administration | 	claude-haiku-4.5 |

Agents collaborate: `@dotnet-bot` and `@deep-thought` delegate research to `@knowledgebase-wizard`, and both use `@quality-pal` as a quality gate before declaring work done.

---

## Why Use It?

- **Specialized > generalist.** Each agent has a focused role, tuned tools, and restricted permissions — it won't edit files when it shouldn't, and won't invent answers when it can search for the real one.
- **Multi-agent pipelines out of the box.** Agents call each other with a structured `[AGENT-CALL]` protocol for compact, citation-rich responses.
- **Bring your own docs.** The knowledge base system lets you register local folders of markdown/PDFs so `@knowledgebase-wizard` searches *your* documentation first.
- **Safe to install globally.** PowerShell and zsh installers merge only the
  selected runtime entries, track repository-owned assets, and preserve
  unrelated Copilot and OpenCode configuration.

---

## 📦 Installation

```powershell
# Clone the repo
git clone https://github.com/your-org/commandline-crew.git
cd commandline-crew

# PowerShell: choose Copilot, OpenCode, or both
.\install.ps1 -Runtime both

# zsh
./install.zsh --runtime both

# Omit the runtime flag to choose interactively
.\install.ps1
./install.zsh

# Force overwrite repository-owned agents and MCP entries
.\install.ps1 -Runtime both -Force
./install.zsh --runtime both --force
```

What gets installed:

| Runtime | Agents | MCP configuration |
|---------|--------|-------------------|
| Copilot | `.github/agents/*.agent.md` → `~/.copilot/agents/` | `.copilot/mcp-config.json` merged into `~/.copilot/mcp-config.json` |
| OpenCode | `.opencode/agents/*.md` → `~/.config/opencode/agents/` | `.opencode/opencode.json` `mcp` entries merged into `~/.config/opencode/opencode.json` |

OpenCode paths honor `XDG_CONFIG_HOME`.

To remove everything:

```powershell
.\uninstall.ps1 -Runtime both
.\uninstall.ps1 -Runtime both -Force

./uninstall.zsh --runtime both
./uninstall.zsh --runtime both --force
```

Only servers and agents *from this repo* are removed — your own customizations are untouched.

---

## 🚀 Quick Start

After installing, agents are available in any directory:

```powershell
copilot --agent dotnet-bot          -p "Design a repository pattern with DI for a user service"
copilot --agent quality-pal         -p "Run full quality assurance on the codebase"
copilot --agent deep-thought        -p "Analyze this codebase and recommend a migration to Clean Architecture"
copilot --agent knowledgebase-wizard -p "How do I use ConfigureAwait correctly?"
copilot --agent kb-manager          -p "List all registered knowledge bases"
```

---

## 🤖 Agent Reference

### @dotnet-bot

C# implementation specialist for .NET 10 projects.

**Workflow:** Design public interface → write xUnit tests → implement → validate with `@quality-pal`

**Strengths:**
- Modern C# 14 idioms (primary constructors, collection expressions, raw string literals)
- API-first design with XML documentation
- Async/await correctness (`ConfigureAwait`, `CancellationToken`, `IAsyncEnumerable<T>`)
- Dependency injection patterns (Microsoft.Extensions.DependencyInjection)
- Performance-aware code (`Span<T>`, `ValueTask<T>`, `StringBuilder`)
- xUnit + NSubstitute test authoring

**Tools:** grep, glob, view, powershell, task, web_search, web_fetch, context7, mslearn

```powershell
copilot --agent dotnet-bot -p "Implement an async service that validates and persists user data"
copilot --agent dotnet-bot -p "Create xUnit tests for this interface: @src/Services/IOrderService.cs"
copilot --agent dotnet-bot -p "Review @src/Services/UserService.cs for SOLID compliance and async best practices"
```

---

### @quality-pal

Code quality gate — runs linters, builds, and tests across multiple languages.

**Workflow:** Identify changed files → skip generated code → run per-language tooling → classify findings → produce markdown report

**Language support:**

| Language | Tools |
|----------|-------|
| C# / .NET | `dotnet format`, `dotnet build`, `dotnet test` |
| TypeScript / JS | ESLint, `npm audit`, `npm run build` |
| PowerShell | Invoke-ScriptAnalyzer |
| Python | pylint, flake8, pytest |
| Rust | `cargo clippy`, `cargo audit` |
| Go | golangci-lint |

Findings are classified 🔴 HIGH / 🟡 MEDIUM / 🟢 LOW. Read-only: never modifies files.

```powershell
copilot --agent quality-pal -p "Run full quality assurance on the codebase"
copilot --agent quality-pal -p "Review @src/api/user-service.ts for quality issues"
copilot --agent quality-pal -p "Run linters, build, and test suite"
```

---

### @deep-thought

Strategic technical advisor for architecture, system design, and high-stakes decisions.

**Workflow:** Classify request → explore codebase → reason with sequential thinking → produce structured report with Mermaid diagrams and ADRs

**Output always includes:**
- Executive summary
- Architecture diagrams (Mermaid.js)
- Approach comparison table with trade-offs
- Architectural Decision Records (ADRs)
- Implementation strategy and risk assessment

Delegates web research to `@knowledgebase-wizard`. Read-only: never modifies files or executes commands.

```powershell
copilot --agent deep-thought -p "Analyze this codebase and design a migration path to Clean Architecture"
copilot --agent deep-thought -p "Compare gRPC vs REST vs GraphQL for our internal service mesh"
copilot --agent deep-thought -p "Design a scalable event-driven order processing system"
```

---

### @knowledgebase-wizard

Documentation and library research agent. Searches your local knowledge bases *and* the web.

**Sources searched:**
- Local knowledge bases registered in `docs/knowledge-bases.md`
- Microsoft Learn / Azure docs (via `mslearn` MCP)
- Versioned library docs (via `context7` MCP)
- General web search

Used directly or called by other agents with `[AGENT-CALL]` prefix for compact structured responses. Read-only.

```powershell
# General how-to questions
copilot --agent knowledgebase-wizard -p "How do I use async/await correctly in C#?"

# Search a specific knowledge base
copilot --agent knowledgebase-wizard -p "Search mqtt for: clean session false in MQTT V5"

# Search multiple knowledge bases
copilot --agent knowledgebase-wizard -p "Search backend and frontend for: authentication patterns"
```

---

### @kb-manager

Manages the knowledge base registry (`docs/knowledge-bases.md`). Converts non-markdown files automatically using `markitdown`.

**Operations:** `LIST` · `ADD` · `REMOVE`

```powershell
# See all registered knowledge bases
copilot --agent kb-manager -p "List all knowledge bases"

# Add a new knowledge base (converts PDFs automatically)
copilot --agent kb-manager -p "Add knowledge base 'mqtt' from ./resources/mqtt with description 'MQTT V5 specification'"

# Remove a knowledge base
copilot --agent kb-manager -p "Remove the 'old-docs' knowledge base"
```

---

## 📚 Knowledge Base Setup

Knowledge bases let `@knowledgebase-wizard` search your local documentation.

### Quick Setup

**1. Create a folder and add your files:**
```powershell
mkdir ./resources/mqtt
# Copy markdown or text files here.
# For PDFs: markitdown .\spec.pdf -o spec.md
```

**2. Register via `@kb-manager`:**
```powershell
copilot --agent kb-manager -p "Add knowledge base 'mqtt' from ./resources/mqtt"
```

Or edit `docs/knowledge-bases.md` directly — it's a simple markdown table:

| Name | Description | Paths | Types |
|------|-------------|-------|-------|
| `mqtt` | MQTT V5 specification | `` `./resources/mqtt` `` | markdown |

**3. Query:**
```powershell
copilot --agent knowledgebase-wizard -p "Search mqtt for: What does clean session = false mean?"
```

### Path Rules

✅ `./resources/topic` — relative, forward slashes  
✅ `./docs/backend`, `./docs/frontend` — multiple paths, comma-separated  
❌ `C:\absolute\path` — no absolute paths  
❌ `.\resources\topic` — no backslashes  

---

## 🔌 MCP Servers

The following MCP servers are configured in `.copilot/mcp-config.json` and installed alongside the agents:

| Server | Purpose |
|--------|---------|
| **mslearn** | Microsoft Learn & Azure documentation API |
| **context7** | Versioned library documentation (via Upstash) |
| **sequentialthinking** | Multi-step reasoning for complex architectural decisions |
| **markitdown** | Convert PDF, DOCX, PPTX, Excel → markdown |
| **playwright** | Browser automation |

---

## 🧠 Skills

Skills are lightweight, model-invoked instruction packs. Each canonical
`skills/<name>/SKILL.md` contains activation, safety, and essential workflow
guidance; detailed procedures live in linked `references/*.md` files and are
loaded only when needed.

The same source is installed to:

- Copilot CLI: `~/.copilot/skills/<name>/`
- OpenCode: `~/.config/opencode/skills/<name>/`

| Skill | Trigger | What it does |
|-------|---------|--------------|
| `ask-folder` | Any exploratory question about the current folder (e.g. *"what does this do"*, *"how does X work"*, *"where is Y defined"*, *"explain this repo"*) | Answers using **only read-only tools** (`view`, `grep`, `glob`, read-only MCP calls, `git --no-pager` inspection). Never edits, creates, builds, or runs side-effecting commands. Delivers concise, file-cited answers. |
| `okf-wiki` | Requests to create, update, validate, or preview an LLM wiki / Open Knowledge Format bundle | Curates workspace files and supplied URLs into OKF v0.1 markdown concepts, then uses a deterministic .NET/YamlDotNet tool to preserve frontmatter, regenerate indexes, append logs, preview changes, and validate conformance. |
| `unslop` | Drafting or editing documentation, README content, release notes, pull request descriptions, issue text, emails, reports, and other human-facing prose | Removes common AI-writing tells such as filler, vague claims, inflated vocabulary, forced patterns, weak verbs, and chatbot phrases. Preserves facts, technical terms, citations, code, and the intended tone. |
| `workflow-goal` | `/workflow-goal <condition>`, *"workflow goal"*, or requests for bounded autonomous work with parallel research | Maintains a measurable goal loop and dynamically launches read-only `copilot -p` workers for independent topics. Results are handed back through files; the parent session alone edits, validates, and completes the goal. |

### Install / Uninstall

```powershell
# Choose skills and runtime interactively
.\install-skills.ps1

# Install specific skills for one or both runtimes
.\install-skills.ps1 -Runtime both -Skill ask-folder,unslop,workflow-goal
./install-skills.zsh --runtime both --skill ask-folder,unslop,workflow-goal

# Install every skill and overwrite existing copies without prompting
.\install-skills.ps1 -Runtime both -Force
./install-skills.zsh --runtime both --force

# Remove skills installed by this repo (other skills are preserved)
.\uninstall-skills.ps1 -Runtime both -Force
./uninstall-skills.zsh --runtime both --force
```

The installers discover every subfolder of `skills/` and copy each selected
skill recursively, including references, scripts, configuration, and tools.
Generated `bin/` and `obj/` directories are excluded. Uninstallation removes
only skill folders represented in this repository and preserves unrelated
user-created skills.

New or updated skills must follow
`.github/instructions/skills.instructions.md`: use a matching kebab-case folder
and frontmatter name, keep safety and the essential workflow in `SKILL.md`,
move detailed guidance into `references/*.md`, use relative links, and gate
runtime-specific behavior explicitly.

`workflow-goal` is partially portable: its bounded goal-loop guidance works in
both runtimes, but `Invoke-WorkflowGoal.ps1` and `copilot -p` fan-out remain
Copilot CLI-only.

### Unslop

`unslop` edits human-facing prose so it sounds direct and intentional. It
removes filler, unsupported generalizations, inflated vocabulary, repeated
sentence patterns, decorative formatting, and stock chatbot phrases. It keeps
the original meaning, certainty, technical terms, citations, commands, code,
and requested tone.

The skill activates for writing and editing tasks such as:

```text
Rewrite this README section so it sounds less AI-generated
Draft concise release notes from these changes
Edit this pull request description for direct, plain language
Remove filler from this technical explanation without changing its meaning
```

It can also be invoked explicitly as `/unslop`. This Copilot version adapts the
ideas from Cursor's
[`unslop` skill](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md)
to Copilot CLI skill metadata and behavior.

### OKF Wiki

`okf-wiki` creates and maintains LLM wikis based on Open Knowledge Format
(OKF) v0.1. It can use the current workspace, explicitly supplied local files,
and user-specified URLs as source material.

```text
Create an OKF wiki from the API docs in this repository
Update .\knowledge with the customer schema from .\schemas\customer.json
Preview adding https://example.com/runbook to .\llm-wiki
Validate the OKF bundle at .\llm-wiki
```

The skill supports four operations:

| Operation | Behavior |
|-----------|----------|
| Create | Writes new concept documents with required YAML frontmatter. |
| Update | Matches by explicit concept path first, then by a unique `resource` URI. |
| Preview | Reports concept, index, and log changes without writing files. |
| Validate | Checks concept frontmatter plus reserved `index.md` / `log.md` structure. |

When no bundle path is supplied for a write, the skill proposes
`.\llm-wiki` and confirms it before continuing. Successful changes regenerate
the affected directory indexes and their ancestors, then append entries to the
root log and the changed concept's directory log.

The deterministic helper is installed with the skill and requires the
**.NET 10 SDK**. It uses a pinned YamlDotNet dependency to parse real YAML,
preserve unknown frontmatter fields, reject unsafe paths and ambiguous resource
matches, and keep dry runs free of filesystem writes.

### Workflow Goal

`/workflow-goal` combines an evidence-based autonomous goal loop with dynamic
fan-out/fan-in research:

```text
/workflow-goal fix every failing test and prove the full suite passes
/workflow-goal review each of these 41 files with one agent per file
/workflow-goal compare the three approaches; use gpt-5.5-mini for workers
/workflow-goal status
/workflow-goal clear
```

The skill defaults to eight concurrent `claude-haiku-4.5` workers with the
normal context tier. Explicit prompt instructions override those defaults:
one-agent-per-file over 41 files starts 41 workers, and a requested model is
passed to Copilot CLI exactly rather than silently replaced.

Workers run in non-interactive prompt mode and are restricted to
non-destructive research: local file reads/search, web search/fetch, and
configured read-only MCP tools. Mixed-capability MCP servers require exact
read-only tool names. Workers cannot edit source, use shell commands, store
memory, recursively orchestrate, or decide that the goal is complete.
`/workflow-goal clear` sends a cancellation request to the active helper and
stops its recorded worker process IDs before clearing the session goal.

Configuration is installed at:

```text
~\.copilot\skills\workflow-goal\config.json
```

Key settings include `defaultWorkers`, `workerModel`, `workerContext`,
`workerTimeoutSeconds`, `workerMaxAiCredits`, `hardWorkerLimit`, artifact
retention, URL access, and read-only MCP allowlists. Environment overrides use
the `WORKFLOW_GOAL_*` prefix. The default artifact root is
`%TEMP%\copilot-workflow-goal`; successful runs are removable after fan-in,
while failed, timed-out, or cancelled runs are preserved for diagnosis.

Each worker is a separate Copilot CLI session and consumes AI credits. Use an
explicit worker count, model, or optional hard limit when cost or local process
capacity matters.

---

## 🔭 Hooks Observability

Track what Copilot agents are doing across sessions — tool usage, files touched, errors, user complaints, and estimated token consumption — all stored in a per-project SQLite database.

### How It Works

Six Python hook scripts fire at each lifecycle event and write structured records to `observability/hooks.db`:

| Hook | What is logged |
|------|----------------|
| `sessionStart` | Session ID, source (new/resume), initial prompt |
| `sessionEnd` | End reason (complete/error/abort/timeout/user_exit) |
| `userPromptSubmitted` | Prompt text, token estimate, error-complaint flag |
| `preToolUse` | Tool name + args before execution |
| `postToolUse` | Tool name, file path, result type, token estimates |
| `errorOccurred` | Error name, message, and stack trace |

### Install into any repository

> Requires Python 3.9+ (uses only the standard library).

```powershell
# PowerShell
.\install-hooks.ps1 -TargetRepo C:\projects\my-app -Runtime both
.\install-hooks.ps1 -TargetRepo C:\projects\my-app -Runtime both -Force
```

```zsh
# zsh
./install-hooks.zsh --target-repo ~/projects/my-app --runtime both
./install-hooks.zsh --target-repo ~/projects/my-app --runtime both --force
```

For Copilot, this copies the Python hooks and writes two `hooks.json` files:
- `{repo}/hooks.json` — used by **Copilot CLI** (loaded from cwd)
- `{repo}/.github/hooks/hooks.json` — used by **Copilot coding agent**

For OpenCode, it installs the local plugin under
`{repo}/.opencode/plugins/` plus the Python bridge and shared database module.
The adapter records supported session, message, tool, and error events in the
same observability database. OpenCode event payloads are not identical to
Copilot hooks, so unavailable fields remain empty rather than being inferred.

Add the database directory to `.gitignore`:
```
observability/
```

### View reports

Run any of these from inside the target repository:

```powershell
python hooks/report.py sessions          # recent sessions with duration
python hooks/report.py tools             # tool usage counts, failures, tokens
python hooks/report.py files             # files most frequently touched
python hooks/report.py errors            # agent errors
python hooks/report.py tokens            # estimated token usage per session
python hooks/report.py prompts           # user prompts with error-complaint detection
python hooks/report.py failures          # failed tool calls with the triggering prompt
python hooks/report.py patterns          # recurring error + failure hot-spot patterns
python hooks/report.py dashboard         # generate observability/dashboard.html
```

All commands accept `--limit N`, `--session <id>`, and `--db <path>`.
The `dashboard` command also accepts `--output <path>` (default: `observability/dashboard.html`).
The generated HTML dashboard requires internet access to load Chart.js from the CDN.

### Uninstall

```powershell
# Remove runtime integrations but keep the database
.\uninstall-hooks.ps1 -TargetRepo C:\projects\my-app -Runtime both

# Remove integrations and observability data
.\uninstall-hooks.ps1 -TargetRepo C:\projects\my-app -Runtime both -Force -PurgeData
```

```zsh
./uninstall-hooks.zsh --target-repo ~/projects/my-app --runtime both
./uninstall-hooks.zsh --target-repo ~/projects/my-app --runtime both --force --purge-data
```

### Override the database path

Set `COPILOT_HOOKS_DB_PATH` to write all events to a single central database:

```powershell
$env:COPILOT_HOOKS_DB_PATH = "C:\observability\copilot-hooks.db"
python hooks/report.py sessions --db C:\observability\copilot-hooks.db
```

---

## 🧪 Samples

Ready-to-run examples that demonstrate what you can build with the [GitHub Copilot SDK](https://github.com/github/copilot-sdk).

### Release Note Generator

Generates structured release notes from local git commit messages using the Copilot SDK.
Copilot drives the conversation — it asks for any missing inputs, runs `git log`, and categorizes commits automatically.

**Output sections:** 💥 Breaking Changes · ✨ New Features · 🔧 Improvements · 🐛 Bug Fixes

**Requirements:** .NET 9+ with the `dotnet run` [single-file execution](https://learn.microsoft.com/dotnet/core/tools/dotnet-run) feature (no project file needed).

```powershell
# Let Copilot ask for everything interactively
dotnet run samples/copilot-sdk/release-note-generator.cs

# Or supply args directly
dotnet run samples/copilot-sdk/release-note-generator.cs -- \
  --repo C:\projects\my-app \
  --since 2025-10-15 \
  --branch main
```

| Flag | Description | Default |
|------|-------------|---------|
| `--repo <path>` | Path to a local git repository | Copilot asks |
| `--since <date>` | Include commits after this date (`2025-10-15`, `15.10.2025`, …) | Copilot asks |
| `--branch <branch>` | Branch to read commits from | Copilot asks (optional) |

---

### SKILL.md Generator

Analyses a source repository (local path **or** remote URL) and produces a concise
`/<package>/SKILL.md` that helps AI assistants super-charge usage of that library.

Copilot drives the analysis — it reads README, samples, and tests to extract real APIs grouped by
functional area. Falls back to scanning the public API surface when no usage examples are found.

**What gets extracted:**
- Core APIs grouped by usage, with one-line comments from XML docs
- Logging & tracing — how to enable and configure
- Error handling pattern (exceptions, Result types, callbacks…)
- Architecture & design patterns observed in the source
- `⚠️ Caveats` section (staleness, license warnings, missing docs)

**Requirements:** .NET 9+ with the `dotnet run` [single-file execution](https://learn.microsoft.com/dotnet/core/tools/dotnet-run) feature (no project file needed).

```powershell
# Let Copilot ask for everything interactively
dotnet run samples/copilot-sdk/skill-md-generator.cs

# Supply args directly — local path
dotnet run samples/copilot-sdk/skill-md-generator.cs -- \
  --source C:\projects\my-library \
  --target C:\skills

# Supply args directly — remote URL
dotnet run samples/copilot-sdk/skill-md-generator.cs -- \
  --source https://github.com/org/repo \
  --target C:\skills
```

| Flag | Description | Default |
|------|-------------|---------|
| `--source <path-or-url>` | Local path to a git repo **or** a remote git URL | Copilot asks |
| `--target <folder>` | Output folder; SKILL.md is written to `<folder>/<package>/SKILL.md` | Copilot asks |

**Automatic checks:**
- ⚠️ Warns if the repository has had no commits for over a year (stale knowledge)
- ⚠️ Warns if the license is not MIT or Apache 2.0
- ⚠️ Warns and switches to public-API analysis if no samples, tests, or README code blocks exist

---

## 📁 Repository Structure

```
commandline-crew/
├── .github/
│   ├── agents/
│   │   ├── dotnet-bot.agent.md
│   │   ├── quality-pal.agent.md
│   │   ├── deep-thought.agent.md
│   │   ├── knowledgebase-wizard.agent.md
│   │   └── kb-manager.agent.md
│   └── instructions/
│       └── dotnet.instructions.md     ← C# coding standards
├── .copilot/
│   └── mcp-config.json                ← MCP server definitions
├── .opencode/
│   ├── agents/                        ← OpenCode agent adapters
│   ├── plugins/                       ← OpenCode observability plugin
│   └── opencode.json                  ← OpenCode MCP definitions
├── docs/
│   └── knowledge-bases.md             ← Knowledge base registry
├── hooks/
│   ├── db.py                          ← SQLite schema + helpers
│   ├── session_start.py               ← sessionStart hook
│   ├── session_end.py                 ← sessionEnd hook
│   ├── user_prompt.py                 ← userPromptSubmitted hook
│   ├── pre_tool_use.py                ← preToolUse hook
│   ├── post_tool_use.py               ← postToolUse hook
│   ├── error_occurred.py              ← errorOccurred hook
│   └── report.py                      ← reporting CLI
├── samples/
│   └── copilot-sdk/
│       ├── release-note-generator.cs  ← Copilot SDK sample (single-file)
│       └── skill-md-generator.cs      ← Copilot SDK sample (single-file)
├── skills/
│   ├── ask-folder/
│   │   ├── SKILL.md                   ← concise skill entry point
│   │   └── references/                ← detailed on-demand guidance
│   └── workflow-goal/
│       ├── SKILL.md                   ← bounded goal + dynamic workflow
│       ├── references/                ← state, fan-out, and launcher details
│       ├── Invoke-WorkflowGoal.ps1     ← parallel prompt-mode launcher
│       ├── config.json                ← worker defaults and permissions
│       └── THIRD-PARTY-NOTICES.md     ← upstream MIT attribution
├── tests/
│   └── workflow-goal/
│       └── Invoke-WorkflowGoal.Tests.ps1
├── resources/                         ← gitignored; put your PDFs/docs here
├── hooks.json                         ← hooks config for Copilot CLI
├── install.ps1
├── install.zsh
├── install-hooks.ps1
├── install-hooks.zsh
├── install-skills.ps1
├── install-skills.zsh
├── uninstall.ps1
├── uninstall.zsh
├── uninstall-hooks.ps1
├── uninstall-hooks.zsh
├── uninstall-skills.ps1
└── uninstall-skills.zsh
```
