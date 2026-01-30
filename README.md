# commandline-crew

Your AI-Enhanced Dev Team in the terminal

---

## 📦 Installation

To use the commandline-crew agents globally (outside this repository), run the install script:

### Install

```powershell
# Clone the repository
git clone https://github.com/your-org/commandline-crew.git
cd commandline-crew

# Run the installer
.\install.ps1

# Or force overwrite existing agents
.\install.ps1 -Force
```

This copies all agent files to `C:\Users\<USER>\.copilot\agents\` where the Copilot CLI can find them globally.

The MCP servers defined in `.copilot/mcp-config.json` are merged into your user-level config at `~/.copilot/mcp-config.json`, preserving any custom MCP servers you already have configured.

### Uninstall

```powershell
# Remove all commandline-crew agents
.\uninstall.ps1

# Or remove without prompting
.\uninstall.ps1 -Force
```

### What Gets Installed

| Source | Destination | Behavior |
|--------|-------------|----------|
| `.github/agents/*.agent.md` | `~/.copilot/agents/*.agent.md` | Copies agents (prompts to overwrite if exists) |
| `.copilot/mcp-config.json` | `~/.copilot/mcp-config.json` | Merges MCP servers (preserves your custom servers) |

After installation, agents are available in any directory:

```bash
copilot --agent knowledgebase-wizard -p "How do I use async/await?"
copilot --agent quality-pal -p "Review this code for quality"
copilot --agent deep-thought -p "Design a microservices architecture"
```

---

## 🚀 Quick Start

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

---

## 🚀 Agents Documentation

- **Agent Registry**: `.github/agents/` - All agent definitions
- **Knowledgebase Wizard**: `.github/agents/knowledgebase-wizard.agent.md` - Knowledge discovery specialist
- **Quality Pal**: `.github/agents/quality-pal.agent.md` - Code quality & assurance specialist
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

## ⏱️ Next Steps

1. **Organize documentation** - Create folders and populate with PDFs/markdown
2. **Configure knowledge bases** - Edit `.copilot/knowledge-bases.yaml`
3. **Test with workarounds** - Use path-based queries to search local files
4. **Upgrade when ready** - When Copilot CLI releases KB support, your configuration will work automatically

---
