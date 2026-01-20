# commandline-crew

Your AI-Enhanced Dev Team in the terminal

---

## ⚡ Global Agent Setup (All Repositories)

To use these agents in **any repository** on your machine, follow these 3 simple steps:

### Step 1: Clone This Repository Globally
```bash
# Choose your location (e.g., ~/coding or C:\dev)
git clone https://github.com/YOUR-ORG/commandline-crew.git ~/coding/commandline-crew

# Remember the full path - you'll need it next
```

### Step 2: Set Environment Variable

#### Windows PowerShell
Add to your PowerShell profile (`$PROFILE`):
```powershell
$env:COPILOT_CUSTOM_INSTRUCTIONS_DIRS = "C:\Users\USERNAME\coding\commandline-crew\.github\agents"
```

Or set it globally (one-time):
```powershell
[Environment]::SetEnvironmentVariable(
  "COPILOT_CUSTOM_INSTRUCTIONS_DIRS",
  "C:\Users\USERNAME\coding\commandline-crew\.github\agents",
  "User"
)
```

#### macOS/Linux
Add to your shell profile (`.bash_profile`, `.zshrc`, etc.):
```bash
export COPILOT_CUSTOM_INSTRUCTIONS_DIRS="$HOME/coding/commandline-crew/.github/agents"
```

### Step 3: Restart and Use

```bash
# Restart your terminal
# Then use agents in ANY repository:
cd ~/my-other-project
copilot --agent dotnet-bot -p "Design a service with dependency injection"
```

### Verify Setup
```bash
# Check if environment variable is set
echo $COPILOT_CUSTOM_INSTRUCTIONS_DIRS  # macOS/Linux
echo $env:COPILOT_CUSTOM_INSTRUCTIONS_DIRS  # PowerShell

# Inside any repository, use the agent
copilot --agent dotnet-bot -p "What can you help with?"
```

---

## 🚀 Quick Start (Repository-Local Usage)

The Commandline Crew provides specialized AI agents to help with your development workflow. The `@knowledgebase-wizard` agent can search your documentation and answer questions about libraries, frameworks, and best practices.

### Using the Knowledgebase Wizard

```bash
# Ask about how to use something
copilot --agent knowledgebase-wizard -p "How do I use async/await?"

# Ask about a specific topic
copilot --agent knowledgebase-wizard -p "What does clean session false mean in MQTT v5?"

# Search local files (current workaround)
copilot --agent knowledgebase-wizard -p "Search ./resources/pdfs for information about MQTT"
```

---

## 📚 Knowledge Base Setup

### 🎯 Quick Setup - 3 Steps

#### Step 1: Create a folder for your documentation
```bash
mkdir ./resources/mqtt
# Copy your text files here
```

#### Step 2: Add to knowledge base registry

Edit `.copilot/knowledge-bases.md` and add a row to the table:

```markdown
| mqtt| MQTT V3.1.1 and MQTT V5 specifications | `./resources/mqtt` | markdown |
```

If you have PDF, Office, or other files, it is recommended to convert them to Markdown, e.g. by using [markitdown](https://github.com/microsoft/markitdown).

```pwsh
markitdown .\mqtt-v5.0-os.pdf -o mqtt-v5.0-os.md  
```

#### Step 3: Query the agent
```bash
copilot --agent knowledgebase-wizard -p "Search mqtt for: What does clean session = false mean for MQTT V5"
```

Done! The agent will search your knowledge base. ✅

---

## 📖 Configuration Reference

The knowledge base registry is a simple markdown table in `.copilot/knowledge-bases.md`:

| Column | Purpose | Example |
|--------|---------|---------|
| **Name** | Unique KB identifier | `my-files-for-topic-a` |
| **Description** | Human-readable purpose | `My hobby documentation` |
| **Paths** | Folders to search (comma-separated) | `` `./resources/topics` `` |
| **Types** | File types in those folders | `markdown`, `text` |

### How to Add a Knowledge Base

1. **Create folder**: `mkdir ./your/path`
2. **Add files**: Copy markdown, or text files
3. **Edit `.copilot/knowledge-bases.md`**: Add a row to the table
4. **Query**: `copilot --agent knowledgebase-wizard -p "Search [name] for: query"`

### Paths Format

✅ **Correct:**
- `./resources/topic` - Relative, with forward slashes
- `./docs/backend`, `./docs/frontend` - Multiple paths, comma-separated in markdown

❌ **Incorrect:**
- `C:\absolute\path` - Absolute Windows paths
- `.\resources\topic` - Backslashes
- `resources/topic` - Missing `./` prefix

---

## 💡 Usage Examples

### Search a specific knowledge base
```bash
copilot --agent knowledgebase-wizard -p "Search my-topic for: MQTT v5 clean session"
```

### Search multiple knowledge bases
```bash
copilot --agent knowledgebase-wizard -p "Search backend and frontend for: authentication patterns"
```

### Combined local and web search
```bash
copilot --agent knowledgebase-wizard -p "Search docs for: async/await patterns. Also search web for best practices"
```

### General knowledge question (searches all KBs)
```bash
copilot --agent knowledgebase-wizard -p "How do I use async/await?"
```

---

## 📁 Recommended File Structure

```
your-repo/
├── .copilot/
│   ├── README.md                      ← Agent system overview
│   ├── KNOWLEDGE_BASE_ROADMAP.md      ← Feature status & roadmap
│   ├── KNOWLEDGE_BASE_SETUP.md        ← Detailed setup guide
│   └── knowledge-bases.yaml           ← Configuration
├── .github/
│   └── agents/
│       ├── knowledgebase-wizard.md    ← Agent definition
│       └── orchestrator.md            ← Orchestrator agent
├── resources/
│   └── pdfs/                          ← Put your PDFs here
│       ├── guide.pdf
│       └── reference.pdf
└── docs/
    ├── guides/
    ├── backend/
    └── frontend/
```

---

## 🔧 Troubleshooting

| Issue | Solution |
|-------|----------|
| Knowledge base parameter ignored | This is expected - KB feature not yet implemented. Use path-based search instead. |
| Files not found in search | Verify the path is correct and relative to repo root. Use forward slashes: `./resources/pdfs` |
| YAML configuration errors | Check `.copilot/knowledge-bases.yaml` syntax - all colons and indentation must be correct |
| Agent gives web results only | Configure a path directly in your query for local file search |

---

## 📖 More Information

### Documentation Files
- **Knowledge Base Registry**: `.copilot/knowledge-bases.md` - Add your KBs here (simple markdown table)
- **Detailed Setup Guide**: `.copilot/KNOWLEDGE_BASE_SETUP.md` - 5-minute comprehensive guide
- **Agent Overview**: `.copilot/README.md` - Agent system overview

### Agent Files
- **Knowledgebase Wizard**: `.github/agents/knowledgebase-wizard.md` - Agent definition and capabilities
- **Orchestrator**: `.github/agents/orchestrator.md` - Multi-agent coordination framework

---

## 🤖 Available Agents

### @knowledgebase-wizard
Specialized agent for knowledge discovery by searching documentation, code, and local knowledge bases.

**Capabilities:**
- Answer "How do I use X?" questions
- Search local project files
- Query web for documentation and tutorials
- Find implementation examples
- Read-only access (no file modification)
- Support for future local KB search

**Usage:**
```bash
copilot --agent knowledgebase-wizard -p "your question"
```

**Current tools:**
- ✅ Web search and fetching
- ✅ Local file search (grep, glob, view)
- ❌ File creation/modification (intentionally restricted)
- ❌ Command execution (intentionally restricted)

### @orchestrator
Coordinates multi-agent workflows by decomposing tasks and delegating to specialized agents.

**Status:** Framework ready for integration with additional agents

### @quality-pal
Comprehensive code quality and assurance specialist for reviewing code and enforcing quality standards.

**Capabilities:**
- Run linters and check `.editorconfig` compliance
- Analyze code for anti-patterns and outdated practices
- Identify opportunities for modern language/framework features
- Execute builds and test suites
- Classify findings by severity (High/Medium/Low)
- Generate detailed markdown quality reports
- Act as quality gate for code from other agents

**Usage:**
```bash
copilot --agent quality-pal -p "Review this code for quality: @src/api/user-service.ts"
copilot --agent quality-pal -p "Run full quality assurance on the codebase"
```

**Current tools:**
- ✅ File search and analysis (grep, glob, view)
- ✅ Build and test execution (powershell, task)
- ❌ File modification (intentionally restricted)
- ❌ Commit/merge operations (intentionally restricted)

### @dotnet-bot
Specialized C# programming expert optimized for modern .NET development with latest language features and best practices.

**Capabilities:**
- Write idiomatic C# code using C# 14, 13, 12 features
- Design APIs following SOLID and GRASP principles
- Implement dependency injection patterns correctly
- Write async/await code following best practices
- Create comprehensive xUnit tests for API contracts
- Recommend latest NuGet packages (MIT licensed)
- Optimize performance and minimize allocations
- Generate XML documentation comments

**Specializations:**
- API-first design (interface → tests → implementation)
- .NET 10+ with latest framework features
- ASP.NET Core guidance and patterns
- Clean code and meaningful comments
- Async/await correctness (ConfigureAwait, CancellationToken)
- Structured logging and error handling

**Usage:**
```bash
copilot --agent dotnet-bot -p "Design a repository pattern for users with dependency injection"
copilot --agent dotnet-bot -p "Implement an async service method that validates and persists data"
copilot --agent dotnet-bot -p "Create xUnit tests for this C# interface: @src/Services/IUserService.cs"
```

**Current tools:**
- ✅ Code search and analysis (grep, glob, view)
- ✅ Build and test execution (powershell, task)
- ✅ Web search for latest NuGet packages
- ✅ Documentation fetching for reference
- ✅ Code generation in responses
- ❌ Automatic file modification (generates code, you decide to save)
- ❌ Commit/merge operations

---

## 🚀 Agents Documentation

- **Agent Registry**: `.github/agents/` - All agent definitions
- **Knowledgebase Wizard**: `.github/agents/knowledgebase-wizard.agent.md` - Knowledge discovery specialist
- **Quality Pal**: `.github/agents/quality-pal.agent.md` - Code quality & assurance specialist
- **DotNet Bot**: `.github/agents/dotnet-bot.agent.md` - C# programming expert for .NET 10+
- **Orchestrator**: `.github/agents/orchestrator.agent.md` - Workflow coordination agent

---

## 📝 Example Queries

### Search local knowledge bases
```bash
copilot --agent knowledgebase-wizard -p "Search my-pdfs for: MQTT v5 clean session"
```

### General how-to questions
```bash
copilot --agent knowledgebase-wizard -p "How do I use async/await?"
```

### Code quality review
```bash
copilot --agent quality-pal -p "Review src/services/user-service.ts for quality"
```

### Full quality assurance
```bash
copilot --agent quality-pal -p "Run full quality assurance on the codebase"
```

### Check build and tests
```bash
copilot --agent quality-pal -p "Run linters, build, and test suite to ensure quality"
```

### C# API design
```bash
copilot --agent dotnet-bot -p "Design a clean C# API for a repository pattern with dependency injection"
```

### C# implementation with tests
```bash
copilot --agent dotnet-bot -p "Implement an async service that validates user data and returns errors using Result pattern"
```

### C# code review
```bash
copilot --agent dotnet-bot -p "Review this C# code for SOLID compliance and async/await best practices: @src/Services/UserService.cs"
```

### Best practices
```bash
copilot --agent knowledgebase-wizard -p "What are best practices for error handling?"
```

### Find examples
```bash
copilot --agent knowledgebase-wizard -p "Show examples of React hooks"
```

### Search multiple KBs
```bash
copilot --agent knowledgebase-wizard -p "Search backend and frontend for: authentication"
```

---

## 🔄 Keeping Agents Updated

Since your agents are in a cloned repository, you can easily keep them up-to-date:

```bash
# Navigate to your cloned commandline-crew
cd ~/coding/commandline-crew

# Pull latest agent definitions
git pull origin main

# New agents and updates automatically available in all repositories!
```

---

## 🆘 Troubleshooting Global Agent Setup

| Issue | Solution |
|-------|----------|
| `Agent not found` | Verify `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` is set: `echo $COPILOT_CUSTOM_INSTRUCTIONS_DIRS` |
| Path not working | Use **full absolute path**, not `~` or relative paths. Example: `C:\Users\USERNAME\...` not `~/...` |
| Still not working | Restart terminal/IDE after setting environment variable |
| Multiple agent dirs | Separate paths with `;` (Windows) or `:` (macOS/Linux): `path1;path2` or `path1:path2` |

---

## ⏱️ Next Steps

1. **Set up global agents** - Follow the "Global Agent Setup" section above
2. **Organize documentation** - Create folders and populate with PDFs/markdown
3. **Configure knowledge bases** - Edit `.copilot/knowledge-bases.yaml`
4. **Test with workarounds** - Use path-based queries to search local files
5. **Upgrade when ready** - When Copilot CLI releases KB support, your configuration will work automatically

---
