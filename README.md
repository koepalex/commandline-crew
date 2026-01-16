# commandline-crew

Your AI-Enhanced Dev Team in the terminal

---

## 🚀 Quick Start

The Commandline Crew provides specialized AI agents to help with your development workflow. The `@knowledgebase-wizard` agent can search your documentation and answer questions about libraries, frameworks, and internal knowledge bases.

### Using the Knowledgebase Wizard

\\\ash
# Ask about how to use something
copilot --agent knowledgebase-wizard -p "How do I use async/await?"

# Query your custom knowledge base
copilot --agent knowledgebase-wizard -p "query: your question, knowledge_base: my-pdfs"
\\\

---

## 📚 Knowledge Base Setup

Extend the @knowledgebase-wizard agent with your own PDFs, markdown, and text files.

### TL;DR - 3 Steps

#### Step 1: Create PDF Folder
\\\ash
mkdir ./resources/pdfs
# Add your PDFs to this folder
\\\

#### Step 2: Edit `.copilot/knowledge-bases.yaml`
\\\yaml
knowledge_bases:
  - name: my-pdfs
    description: "My PDF documentation"
    folders:
      - path: ./resources/pdfs
        type: pdf
\\\

#### Step 3: Query the Agent
\\\ash
copilot --agent knowledgebase-wizard -p "query: your question, knowledge_base: my-pdfs"
\\\

---

## 📖 Configuration Syntax

\\\yaml
knowledge_bases:
  - name: <unique-id>              # kebab-case identifier
    description: "<what it is>"    # Human-readable
    folders:
      - path: ./path/to/folder     # Relative to repo root
        type: pdf                  # pdf, markdown, or text
\\\

---

## 🎯 Common Examples

### Just PDFs
\\\yaml
knowledge_bases:
  - name: pdfs
    description: "Documentation PDFs"
    folders:
      - path: ./resources/pdfs
        type: pdf
\\\

### Multiple Folders in One KB
\\\yaml
knowledge_bases:
  - name: architecture
    description: "All architecture docs"
    folders:
      - path: ./docs/architecture
        type: pdf
      - path: ./docs/patterns
        type: pdf
\\\

### Multiple Knowledge Bases
\\\yaml
knowledge_bases:
  - name: backend
    description: "Backend docs"
    folders:
      - path: ./docs/backend
        type: pdf

  - name: frontend
    description: "Frontend docs"
    folders:
      - path: ./docs/frontend
        type: pdf
\\\

### Mixed Content (PDFs + Markdown + Text)
\\\yaml
knowledge_bases:
  - name: complete
    description: "Complete documentation"
    folders:
      - path: ./docs/guides
        type: markdown
      - path: ./resources/pdfs
        type: pdf
      - path: ./policies
        type: text
\\\

---

## 💡 Usage Commands

\\\ash
# Query specific knowledge base
copilot --agent knowledgebase-wizard -p "query: how do we structure APIs, knowledge_base: backend"

# With version
copilot --agent knowledgebase-wizard -p "query: patterns, knowledge_base: architecture, version: 2.0"

# Query all KBs (no knowledge_base parameter)
copilot --agent knowledgebase-wizard -p "What's the best practice for this?"
\\\

---

## ✅ Key Rules

### Paths must be:
- Relative to repo root: `./resources/pdfs`
- With forward slashes: `./` (not `.\`)

### YAML must have:
- Colons after all field names: `name:`
- Consistent indentation (spaces)
- Dashes before list items: `- path:`

### Knowledge Base name:
- Unique
- Lowercase with hyphens (kebab-case): `my-pdfs`, `backend-standards`
- Used in queries exactly as written

---

## 📁 Recommended File Structure

\\\
your-repo/
├── .copilot/
│   ├── README.md
│   ├── KNOWLEDGE_BASE_SETUP.md      ← Detailed guide
│   ├── knowledge-bases.yaml         ← Configuration
│   └── knowledge-bases.yaml.backup  ← Backup
├── resources/
│   └── pdfs/                        ← Put PDFs here
│       ├── guide.pdf
│       └── reference.pdf
└── [other files...]
\\\

---

## 🔧 Troubleshooting

| Problem | Solution |
|---------|----------|
| KB not found | Check name matches exactly, verify YAML syntax |
| No results | Verify path is correct, PDFs exist, try different search terms |
| YAML error | Check colons, indentation, dashes |
| PDFs not found | Path must be `./relative/path`, not absolute |

---

## 📖 Complete Minimal Example

1. **Create folder**: `mkdir ./docs/pdfs`
2. **Add PDF**: Copy `guide.pdf` to `./docs/pdfs/`
3. **Edit `.copilot/knowledge-bases.yaml`**:
   \\\yaml
   knowledge_bases:
     - name: docs
       description: "Documentation"
       folders:
         - path: ./docs/pdfs
           type: pdf
   \\\
4. **Test**: `copilot --agent knowledgebase-wizard -p "query: your question, knowledge_base: docs"`

Done! 🎉

---

## 📚 More Information

- **Detailed Setup Guide**: `.copilot/KNOWLEDGE_BASE_SETUP.md`
- **Agent System Overview**: `.copilot/README.md`
- **Configuration Reference**: `.copilot/knowledge-bases.yaml`

---

## 🤖 Available Agents

### @knowledgebase-wizard
Specialized knowledge discovery agent for answering questions about libraries, frameworks, and external dependencies by searching official documentation, analyzing source code, and consulting extensible local knowledge bases.

**Features:**
- Answer "How do I use [library]?" questions
- Search local PDFs, markdown, and text files
- Query official documentation
- Find implementation examples
- Enforce tool restrictions (read-only, no file modification)
- Support 4 request types: conceptual, implementation, context, comprehensive

**Query:**
\\\ash
copilot --agent knowledgebase-wizard -p "your question"
\\\

### @orchestrator
Coordinates multi-agent workflows by decomposing tasks, delegating to specialized agents, and combining results.

**Status:** Framework ready for extension with new agents

---

## 🚀 Agents Documentation

- **Agent Registry**: `.github/agents/`
- **Knowledgebase Wizard**: `.github/agents/knowledgebase-wizard.md`
- **Orchestrator**: `.github/agents/orchestrator.md`

---
