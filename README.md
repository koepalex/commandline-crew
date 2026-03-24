![commandline-crew logo](./docs/images/commandline-crew.png)

# commandline-crew

Your AI-powered dev team in the terminal — a curated collection of specialized [GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli) agents designed to work together on real engineering tasks.

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
- **Safe to install globally.** `install.ps1` merges MCP server config non-destructively and copies agents to `~/.copilot/agents/` — it won't blow away your existing setup.

---

## 📦 Installation

```powershell
# Clone the repo
git clone https://github.com/your-org/commandline-crew.git
cd commandline-crew

# Install globally (prompts before overwriting anything)
.\install.ps1

# Force overwrite existing agents/servers
.\install.ps1 -Force
```

What gets installed:

| Source | Destination | Behavior |
|--------|-------------|----------|
| `.github/agents/*.agent.md` | `~/.copilot/agents/` | Copied (prompts on conflict) |
| `.copilot/mcp-config.json` | `~/.copilot/mcp-config.json` | Merged (your custom servers preserved) |

To remove everything:

```powershell
.\uninstall.ps1          # Prompts before each deletion
.\uninstall.ps1 -Force   # Removes without prompting
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
# Install hooks into a target repo
.\install-hooks.ps1 -TargetRepo C:\projects\my-app

# Force overwrite if already installed
.\install-hooks.ps1 -TargetRepo C:\projects\my-app -Force
```

This copies `hooks/*.py` and writes two `hooks.json` files:
- `{repo}/hooks.json` — used by **Copilot CLI** (loaded from cwd)
- `{repo}/.github/hooks/hooks.json` — used by **Copilot coding agent**

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
# Remove hook scripts and config (keep the database)
.\uninstall-hooks.ps1 -TargetRepo C:\projects\my-app

# Remove everything including the database
.\uninstall-hooks.ps1 -TargetRepo C:\projects\my-app -Force -PurgeData
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
│       └── release-note-generator.cs  ← Copilot SDK sample (single-file)
├── resources/                         ← gitignored; put your PDFs/docs here
├── hooks.json                         ← hooks config for Copilot CLI
├── install.ps1
├── install-hooks.ps1
├── uninstall.ps1
└── uninstall-hooks.ps1
```

