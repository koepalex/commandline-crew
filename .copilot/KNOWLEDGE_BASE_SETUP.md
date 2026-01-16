# Knowledge Base Configuration for @knowledgebase-wizard Agent

This file defines custom knowledge bases that extend the knowledgebase-wizard agent.
Each knowledge base is a collection of folders containing markdown, PDF, and text files.

The agent will search these local knowledge bases when responding to queries,
supplementing searches from official documentation and web sources.

## Quick Start

### Step 1: Organize Your PDFs
Create a folder in your repository to store PDFs:
```
your-repo/
├── resources/
│   └── pdfs/
│       ├── guide1.pdf
│       ├── reference.pdf
│       └── best-practices.pdf
```

### Step 2: Register in knowledge-bases.yaml
Add to `knowledge_bases:` section:
```yaml
- name: my-knowledge
  description: "My PDF documentation and references"
  folders:
    - path: ./resources/pdfs
      type: pdf
```

### Step 3: Query the Knowledge Base
```bash
copilot --agent knowledgebase-wizard -p "query: your question, knowledge_base: my-knowledge"
```

---

## Configuration Examples

### Example 1: PDF Documentation Only
```yaml
knowledge_bases:
  - name: company-standards
    description: "Company standards and best practices"
    folders:
      - path: ./resources/standards
        type: pdf
```

### Example 2: Mixed Content (PDFs + Markdown)
```yaml
knowledge_bases:
  - name: complete-docs
    description: "Complete documentation with guides and references"
    folders:
      - path: ./docs/guides
        type: markdown
      - path: ./resources/pdf-references
        type: pdf
      - path: ./resources/templates
        type: text
```

### Example 3: Multiple PDF Folders
```yaml
knowledge_bases:
  - name: architecture-docs
    description: "Architecture, design patterns, and guidelines"
    folders:
      - path: ./docs/architecture
        type: pdf
      - path: ./docs/patterns
        type: pdf
      - path: ./docs/guidelines
        type: pdf
```

### Example 4: Real-World Multi-Domain Setup
```yaml
knowledge_bases:
  - name: backend-patterns
    description: "Backend design patterns and API guidelines"
    folders:
      - path: ./docs/backend
        type: markdown
      - path: ./resources/api-docs
        type: pdf

  - name: frontend-guide
    description: "Frontend frameworks and UI patterns"
    folders:
      - path: ./docs/frontend
        type: markdown
      - path: ./resources/ui-patterns
        type: pdf

  - name: security-compliance
    description: "Security best practices and compliance documents"
    folders:
      - path: ./docs/security
        type: markdown
      - path: ./resources/compliance-pdfs
        type: pdf
      - path: ./policies
        type: text
```

---

## Configuration Reference

```yaml
knowledge_bases:
  - name: <unique-identifier>
    description: "<human-readable description>"
    folders:
      - path: <relative-path-from-repo-root>
        type: <markdown|pdf|text>
      - path: <another-path>
        type: <markdown|pdf|text>
```

### Fields:

**name** (required)
  - Unique identifier for the knowledge base (kebab-case)
  - Example: my-knowledge, backend-docs, security-standards
  - Used in queries: knowledge_base: my-knowledge

**description** (required)
  - Human-readable description of what this KB covers
  - Shown when listing available knowledge bases
  - Example: "Company standards and best practices"

**folders** (required)
  - List of folders to index and search
  - Each folder entry must have path and type

**path** (required)
  - Relative path from repository root
  - Use forward slashes: ./resources/pdfs or ./docs/guides
  - Will be converted automatically on Windows

**type** (required)
  - File type to search in this folder
  - Options: markdown, pdf, text
  - Agent searches recursively in each folder

---

## File Type Guide

### markdown
  Extensions: .md, .mdx, .markdown
  Use for: Technical documentation, guides, READMEs
  Example: ./docs/guides

### pdf
  Extensions: .pdf
  Use for: Formal documentation, policies, whitepapers
  Example: ./resources/pdf-docs

### text
  Extensions: .txt, .doc, .log, and others
  Use for: Plain text files, logs, templates
  Example: ./resources/text-docs

---

## Usage Examples

### Query a specific knowledge base:
```bash
copilot --agent knowledgebase-wizard -p "query: How do we structure APIs, knowledge_base: backend-patterns"
```

### Search multiple KBs (run separately):
```bash
copilot --agent knowledgebase-wizard -p "query: security guidelines, knowledge_base: security-compliance"
copilot --agent knowledgebase-wizard -p "query: UI components, knowledge_base: frontend-guide"
```

### Without specifying KB (searches all):
```bash
copilot --agent knowledgebase-wizard -p "How do I implement this pattern?"
```

---

## Important Notes

- Paths are **relative to the repository root**
- Use **forward slashes** (even on Windows): ./resources/pdfs
- Agent searches **recursively** in specified folders
- Files are **indexed and searched** alongside web sources
- **Query results** show source file name and location
- **PDF parsing** is built-in to the agent
- Each knowledge base can have **multiple folders**

---

## Troubleshooting

### PDFs not being found?
1. Check path is relative to repo root: `./resources/pdfs` not `resources/pdfs`
2. Verify folder exists and contains PDFs
3. Use forward slashes: `./` not `.\`
4. Ensure `type: pdf` is specified
5. Verify the YAML syntax is correct

### No results from knowledge base?
1. Query might not match PDF content well
2. Try different search terms
3. Verify PDFs are readable (not corrupted)
4. Check knowledge_base name matches configuration exactly

### Multiple knowledge bases?
1. Create separate entries in knowledge_bases list
2. Each needs unique `name` field
3. Query specific KB with `knowledge_base: name` parameter
4. Or run multiple separate commands

### YAML Syntax Issues?
Common mistakes to avoid:
- Missing colon after field names: `name: my-kb` (correct) vs `name my-kb` (wrong)
- Inconsistent indentation (use spaces, not tabs)
- Missing dash before list items: `- path:` (correct) vs `path:` (wrong)
- Quotes only needed for special characters

---

## Active Knowledge Bases

Configure your knowledge bases below:
