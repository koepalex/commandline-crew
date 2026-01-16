# Copilot CLI - Commandline Crew Agent System

Welcome to the agent system documentation for Commandline Crew. This directory contains everything needed to use and extend the AI-powered agent team.

## 📁 Files in This Directory

### Core Documentation
- **`agents.md`** - Master registry and framework for all agents
  - Agent specifications and contracts
  - Invocation patterns (single agents, orchestration)
  - Agent development guidelines
  - Quick reference table

### Agent Documentation
- **`knowledgebase-wizard.md`** - Complete guide to the @knowledgebase-wizard agent
  - Quick start examples
  - Setting up custom knowledge bases
  - Understanding request types
  - Advanced usage patterns
  - Troubleshooting
  - Domain-specific examples

### Configuration
- **`knowledge-bases.yaml`** - Knowledge base registry for @knowledgebase-wizard
  - Define custom documentation folders
  - Support for markdown, PDF, and text files
  - Per-knowledge-base descriptions
  - Users can extend with team-specific bases

## 🚀 Quick Start

### Invoke a Single Agent
```bash
copilot-cli @knowledgebase-wizard "How do I use React hooks?"
```

### Orchestrate Multiple Agents (Future)
```bash
copilot-cli @orchestrator "workflow: implement-feature, feature: oauth2"
```

## 📋 Current Agents

| Agent | Specialty | Status |
|-------|-----------|--------|
| @orchestrator | Multi-agent workflow coordination | Framework Ready |
| @knowledgebase-wizard | Documentation research, library expertise | Ready for Integration |

## 🔧 Setting Up Knowledge Bases

1. Create documentation folders in your project:
   ```
   ./docs/patterns/
   ./docs/best-practices/
   ./resources/
   ```

2. Register them in `knowledge-bases.yaml`:
   ```yaml
   knowledge_bases:
     - name: project-patterns
       description: "Project-specific patterns"
       folders:
         - path: ./docs/patterns
           type: markdown
   ```

3. Use in queries:
   ```bash
   copilot-cli @knowledgebase-wizard "query: how do we authenticate, knowledge_base: project-patterns"
   ```

## 🎯 Adding New Agents

When adding a new agent:

1. **Add to `agents.md`** under the Agent Registry section using the template
2. **Create dedicated docs** like `<agent-name>.md` with:
   - Quick start examples
   - Configuration details
   - Advanced patterns
   - Troubleshooting

3. **Update the quick reference table** at the bottom of `agents.md`

4. **Define workflows** that use your agent in the Workflow Examples section

## 🔗 Workflow-Based Orchestration

The @orchestrator agent coordinates workflows by:
1. Parsing high-level workflow requests
2. Decomposing into agent-sized tasks
3. Delegating to specialized agents
4. Chaining results between agents
5. Synthesizing final output

Example workflow (to be implemented):
```
@orchestrator workflow: implement-feature
  ├─> @knowledgebase-wizard: Research requirements
  ├─> @architect: Design solution
  ├─> @frontend-dev: Implement UI
  ├─> @backend-dev: Implement API
  ├─> @test-generator: Generate tests
  └─> Synthesize results
```

## 📤 Output in CLI Mode

All agent results are written to stdout for:
- Direct display in terminal
- Piping to other commands
- Capturing to files
- Integration with scripts

Example:
```bash
copilot-cli @knowledgebase-wizard "How do I use async/await?" | tee result.txt
```

## 🛠️ Agent Development Guidelines

From `agents.md`:

- **Single Responsibility**: One primary expertise area per agent
- **Clear Contracts**: Explicit input/output formats
- **Composability**: Works as building block in workflows
- **Idempotency**: Consistent results for same inputs
- **Error Handling**: Clear error communication
- **Stdout Output**: Results in stdout for piping

### Naming Convention
- Kebab-case: `@code-reviewer`, `@test-generator`
- Prefix related agents: `@frontend-*`, `@backend-*`
- Specific names; avoid generic terms

### Output Format for Orchestration
```json
{
  "status": "success|error",
  "result": { "key": "value" },
  "context": {
    "agent": "@agent-name",
    "timestamp": "2026-01-16T13:00:00Z"
  },
  "errors": []
}
```

## 📚 Tools Available to Agents

Agents can use these tools:
- **context7 MCP server** - Query official documentation
- **web_search** - Find latest information online
- **local_search** - Search registered knowledge base folders
- **github tools** - Search code, issues, PRs
- **webfetch** - Retrieve specific documentation pages

## 📖 Learning Resources

### For Users
- Start with `knowledgebase-wizard.md` for documentation research examples
- Check agent-specific docs (`./<agent-name>.md`) for detailed guides
- See Quick Start section above for common commands

### For Agent Developers
- Read `agents.md` for framework details and guidelines
- Review `knowledgebase-wizard.md` as an example of a well-documented agent
- Follow the template when adding new agents

## ❓ FAQ

**Q: How do I use the orchestrator?**
A: The orchestrator is optional. You can invoke agents directly with `@agent-name` or use workflows with `@orchestrator "workflow: name"`.

**Q: Can agents call other agents?**
A: Yes! The orchestrator coordinates this, and agent results are fed into subsequent agents.

**Q: How do I add custom knowledge?**
A: Edit `knowledge-bases.yaml` to register your documentation folders, then use `knowledge_base: name` in queries.

**Q: What if an agent fails?**
A: Agents write clear error messages to stdout. The orchestrator can be configured for fail-fast or continue strategies.

**Q: How are agents versioned?**
A: Currently agents are updated in-place. Future: support `@agent-name:v1` syntax for version pinning.

## 🔄 Workflow Examples

To be documented as agents are added to the system.

## 📝 Contributing New Agents

1. Design the agent with clear specialization
2. Write comprehensive documentation in `agents.md`
3. Create `<agent-name>.md` with usage guide
4. Add to quick reference table
5. Define sample workflows using the agent

---

**Last Updated:** January 16, 2026
**Status:** Framework ready with @knowledgebase-wizard agent integrated
