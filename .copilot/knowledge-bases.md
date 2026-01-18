# Knowledge Bases Registry

This file defines custom knowledge bases that extend the @knowledgebase-wizard agent.

The agent reads this file to understand what knowledge bases are available and their locations.

---

## Registered Knowledge Bases

| Name | Description | Paths | Types |
|------|-------------|-------|-------|
| mqtt | MQTT V3.1.1 and MQTT V5 specifications | `./resources/mqtt` | pdf |
| docs | Project documentation | `./docs` | markdown |
| backend | Backend API documentation | `./docs/backend` | markdown, pdf |
| frontend | Frontend framework docs | `./docs/frontend` | markdown, pdf |
| policies | Security and compliance | `./policies`, `./resources/compliance-pdfs` | text, pdf |

---

## How to Add a Knowledge Base

1. **Create the folder** (relative to repo root):
   ```bash
   mkdir ./path/to/your/docs
   ```

2. **Add files** to the folder:
   - `.pdf` files for PDFs
   - `.md`, `.mdx`, `.markdown` files for markdown
   - `.txt`, `.doc` files for text

3. **Add a row to the table above**:
   ```markdown
   | my-docs | Description of KB | `./path/to/your/docs` | file-types |
   ```

4. **Query the agent**:
   ```bash
   copilot --agent knowledgebase-wizard -p "Search my-docs for: your question"
   ```

---

## Usage Examples

### Query a specific knowledge base
```bash
copilot --agent knowledgebase-wizard -p "Search my-pdfs for: MQTT v5 clean session"
```

### Query multiple knowledge bases
```bash
copilot --agent knowledgebase-wizard -p "Search my-pdfs and docs for: async patterns"
```

### Query all knowledge bases
```bash
copilot --agent knowledgebase-wizard -p "What are the best practices for error handling?"
```

---

## File Type Reference

| Type | Extensions | Example |
|------|-----------|---------|
| **pdf** | `.pdf` | technical_spec.pdf |
| **markdown** | `.md`, `.mdx`, `.markdown` | guide.md, tutorial.mdx |
| **text** | `.txt`, `.doc`, `.log` | notes.txt, policy.doc |

---

## Configuration Notes

### Paths must be:
- ✅ Relative to repo root: `./resources/pdfs`
- ✅ With forward slashes: `./docs/backend` (not `.\docs\backend`)
- ✅ Starting with `./` to indicate repo-relative

### Paths will NOT work:
- ❌ Absolute paths: `C:\Users\...`
- ❌ Without `./` prefix: `resources/pdfs`
- ❌ With backslashes: `.\docs\backend`

---

## Examples

### Example 1: Single PDF folder
Add this row to the table:
```markdown
| norms | Team norms and standards | `./resources/norms` | pdf |
```

Then create and populate the folder:
```bash
mkdir ./resources/norms
cp your-standards.pdf ./resources/norms/
```

Query:
```bash
copilot --agent knowledgebase-wizard -p "Search norms for: code style guidelines"
```

### Example 2: Multiple folders in one KB
Add this row:
```markdown
| architecture | Architecture docs and patterns | `./docs/architecture`, `./resources/design-patterns` | pdf, markdown |
```

Create folders:
```bash
mkdir ./docs/architecture
mkdir ./resources/design-patterns
```

### Example 3: Mixed content types
Add this row:
```markdown
| standards | All standards and compliance | `./docs/standards`, `./resources/pdfs`, `./policies` | markdown, pdf, text |
```

---

## Searching Knowledge Bases

The agent will:

1. **Parse this registry** to find available KBs
2. **Extract the paths** for each KB
3. **Search local files** in those paths
4. **Return results** with source files and locations
5. **Supplement with web search** if local results are incomplete

---

## Quick Setup Checklist

- [ ] Create folder(s) for your documentation
- [ ] Add files to the folder(s)
- [ ] Add a row to the Knowledge Bases table above
- [ ] Test with a query: `copilot --agent knowledgebase-wizard -p "Search [kb-name] for: ..."`
- [ ] Verify results include local files

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| KB not found | Check the exact name in the table, use `Search [name] for:` syntax |
| No results | Verify files exist in the path, try simpler search terms |
| Path errors | Check paths use `./` prefix and forward slashes |
| YAML errors | This is now markdown, not YAML - just edit the table! |

---

## Future Enhancements

- Automatic file indexing and ranking
- Semantic search across all KBs
- Full-text search with relevance scoring
- KB-specific search syntax (e.g., `@my-pdfs: query`)
- Real-time file watching and re-indexing
