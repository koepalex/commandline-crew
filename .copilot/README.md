# Copilot CLI - Commandline Crew Agent System

Welcome to the agent system documentation for Commandline Crew. This directory contains everything needed to use and extend the AI-powered agent team.

## 📁 Files in This Directory

### Core Documentation
- **`AGENT_DEVELOPMENT_GUIDE.md`** - Guidelines for creating new agents
  - File structure and naming conventions
  - Step-by-step checklist for adding agents
  - Content templates
  - Quality checklist
  - Common mistakes to avoid

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

- **`quality-pal.md`** - Complete guide to the @quality-pal agent
  - Code quality review workflows
  - Git integration (staged, committed, not yet pushed)
  - Build and test execution
  - Linting and compliance checks
  - Quality gate patterns
  - Report generation

- **`deep-thought.md`** - Complete guide to the @deep-thought agent
  - Strategic technical advisory and architecture consultation
  - Deep system analysis and design patterns
  - Solution planning and architecture blueprints
  - Mermaid diagram generation
  - Technology recommendations
  - Design decision documentation

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
| @quality-pal | Code quality review, linting, test execution | Ready for Integration |
| @deep-thought | Strategic architecture & design consulting | Ready for Integration |

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

**⚠️ IMPORTANT: Read `.copilot/AGENT_DEVELOPMENT_GUIDE.md` FIRST before adding agents**

When adding a new agent, you MUST create files in TWO locations:

1. **`.github/agents/<agent-name>.agent.md`** - Formal agent specification
2. **`.copilot/<agent-name>.md`** - User-facing comprehensive guide

Then update `.copilot/README.md` in these 6 sections:
- Agent Documentation section (add link to new agent docs)
- Current Agents table (add agent row)
- Learning Resources > For Users (add reference)
- FAQ section (add Q&A about agent)
- Workflow Examples section (add usage patterns)
- Last Updated status line (add agent name)

See AGENT_DEVELOPMENT_GUIDE.md for complete guidance:
- File structure and naming conventions
- Step-by-step checklist
- Content templates
- Quality checklist
- Common mistakes to avoid

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
- **powershell/task execution** - Run commands, builds, tests (quality-pal)
- **grep/glob** - File search and analysis

## 📖 Learning Resources

### For Users
- Start with `knowledgebase-wizard.md` for documentation research examples
- Check `quality-pal.md` for code quality review patterns and Git integration
- Check `deep-thought.md` for architecture and strategic technical consulting
- Check agent-specific docs (`./<agent-name>.md`) for detailed guides
- See Quick Start section above for common commands

### For Agent Developers
- Read `agents.md` for framework details and guidelines
- Review `knowledgebase-wizard.md` and `quality-pal.md` as examples of well-documented agents
- Follow the template when adding new agents

## ❓ FAQ

**Q: How do I use the orchestrator?**
A: The orchestrator is optional. You can invoke agents directly with `@agent-name` or use workflows with `@orchestrator "workflow: name"`.

**Q: Can agents call other agents?**
A: Yes! The orchestrator coordinates this, and agent results are fed into subsequent agents.

**Q: What can @quality-pal do?**
A: The @quality-pal agent reviews code for quality, runs linters, builds, and tests. It can analyze specific folders or the entire repository, and it supports checking staged/committed but not yet pushed changes using Git integration.

**Q: When should I use @deep-thought?**
A: Use @deep-thought for strategic technical decisions, architecture design, system redesign proposals, complex problem-solving, and creating architecture diagrams. It's ideal for stakeholder alignment and high-level design documentation.

**Q: How do I add custom knowledge?**
A: Edit `knowledge-bases.yaml` to register your documentation folders, then use `knowledge_base: name` in queries.

**Q: What if an agent fails?**
A: Agents write clear error messages to stdout. The orchestrator can be configured for fail-fast or continue strategies.

**Q: How are agents versioned?**
A: Currently agents are updated in-place. Future: support `@agent-name:v1` syntax for version pinning.

## 🔄 Workflow Examples

To be documented as agents are added to the system.

### Quality-Pal Workflows

#### Check staged/committed changes not yet pushed
```bash
# Basic usage - check entire repository
copilot-cli @quality-pal "Check staged and committed but not yet pushed changes for quality issues"

# Specific folder - absolute path example
copilot-cli @quality-pal "Check S:\rc\_priv\commandline-crew\src for quality issues in staged and committed but not yet pushed changes"

# Extended quality check with build and tests
copilot-cli @quality-pal "Analyze S:\rc\_priv\commandline-crew\src directory for staged and committed changes, then run linters, build, and tests"
```

#### Code review patterns
```bash
# Review specific file for quality
copilot-cli @quality-pal "Review src/services/payment-service.ts for quality, performance, and security issues"

# Full repository quality audit
copilot-cli @quality-pal "Run comprehensive quality assurance: linters, build validation, test execution, and code pattern analysis"

# Check compliance with .editorconfig
copilot-cli @quality-pal "Verify staged changes comply with .editorconfig and identify formatting issues"
```

### Deep-Thought Workflows

#### System Architecture Review and Design
```bash
# Assess current architecture and propose improvements
copilot-cli @deep-thought "Review the architecture of S:\rc\_priv\commandline-crew and propose a strategic redesign plan with mermaid diagrams"

# Design new system component
copilot-cli @deep-thought "Design a microservices architecture for a real-time notification system. Include technology recommendations, system diagrams, and decision rationale"

# Solve complex technical problem
copilot-cli @deep-thought "We're experiencing scaling issues with our current monolithic architecture. Propose a solution that maintains backward compatibility while improving performance"
```

#### Strategic Technical Consulting
```bash
# Technology selection guidance
copilot-cli @deep-thought "We need to build a new data pipeline. What technologies should we use? Consider our team size, existing tech stack, and scalability requirements. Provide pros/cons analysis"

# Design decision documentation
copilot-cli @deep-thought "Analyze the trade-offs between REST, GraphQL, and gRPC for our API layer. Create architecture diagrams and provide implementation recommendations"

# Cross-cutting concerns architecture
copilot-cli @deep-thought "Design a comprehensive logging, monitoring, and tracing strategy for our distributed system. Include diagrams and implementation approach"
```

## 📝 Contributing New Agents

1. Design the agent with clear specialization
2. Write comprehensive documentation in `agents.md`
3. Create `<agent-name>.md` with usage guide
4. Add to quick reference table
5. Define sample workflows using the agent

---

**Last Updated:** January 19, 2026
**Status:** Framework ready with @knowledgebase-wizard, @quality-pal, and @deep-thought agents integrated
