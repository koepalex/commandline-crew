# Agent Development Guide

Guidelines for creating and documenting new agents in the Commandline Crew system.

## 📁 File Structure and Naming Conventions

### Agent Documentation Locations

When creating a new agent, you MUST create documentation files in TWO locations with DIFFERENT purposes:

```
.github/agents/
├── <agent-name>.agent.md          ← Formal agent specification (for developers)
└── ...

.copilot/
├── <agent-name>.md                ← User-facing guide (for end users)
└── README.md                       ← Updated with agent references
```

### File Naming Rules

| Location | File Pattern | Purpose | Audience |
|----------|--------------|---------|----------|
| `.github/agents/` | `<agent-name>.agent.md` | Formal agent specification, capabilities, contracts | Developers, architects |
| `.copilot/` | `<agent-name>.md` | Complete user guide with examples and workflows | End users, teams |
| `.copilot/` | `README.md` | Master index, quick links to all agents | Everyone |

### Naming Convention

- Use **kebab-case** for agent names: `deep-thought`, `quality-pal`, `knowledgebase-wizard`
- Use the SAME name in both locations
- Example for agent `@my-awesome-agent`:
  - `.github/agents/my-awesome-agent.agent.md`
  - `.copilot/my-awesome-agent.md`

## ✅ Checklist for Adding a New Agent

When adding a new agent to the system, follow these steps IN ORDER:

### 1. Create Formal Agent Specification
- **Location**: `.github/agents/<agent-name>.agent.md`
- **Contents**:
  - Agent name and purpose
  - Overview of capabilities
  - Quick start examples
  - When to use / when NOT to use
  - Detailed capabilities breakdown
  - Usage examples with expected outputs
  - Diagram examples (if applicable)
  - Integration with other agents
  - Prompting tips
  - FAQ
  - Related documentation links

### 2. Create User-Facing Guide
- **Location**: `.copilot/<agent-name>.md`
- **Contents**: Same as formal specification (user-focused perspective)
- **Purpose**: Comprehensive guide for teams implementing the agent

### 3. Update Main README
- **Location**: `.copilot/README.md`
- **Updates Required** (search for these sections and update):

  a. **Agent Documentation section** (around line 15-30)
     ```markdown
     - **`<agent-name>.md`** - Complete guide to the @<agent-name> agent
       - Key capability 1
       - Key capability 2
       - Key capability 3
     ```

  b. **Current Agents table** (around line 60)
     ```markdown
     | @<agent-name> | Short description of specialty | Ready for Integration |
     ```

  c. **Learning Resources > For Users** (around line 180)
     ```markdown
     - Check `<agent-name>.md` for [what this agent does]
     ```

  d. **FAQ section** (around line 200)
     ```markdown
     **Q: When should I use @<agent-name>?**
     A: Use @<agent-name> for [specific use cases]. It's ideal for [key scenarios].
     ```

  e. **Workflow Examples section** (around line 220)
     ```markdown
     ### <Agent-Name> Workflows

     #### Use Case 1
     ```bash
     copilot-cli @<agent-name> "Example query 1"
     ```

     #### Use Case 2
     ```bash
     copilot-cli @<agent-name> "Example query 2"
     ```
     ```

  f. **Last Updated and Status** (at end of file)
     ```markdown
     **Last Updated:** [DATE]
     **Status:** Framework ready with @agent1, @agent2, and @<agent-name> agents integrated
     ```

### 4. Update agents.md (if it exists)
- **Location**: `.copilot/agents.md` or `.github/agents/agents.md`
- Add entry to agent registry with:
  - Agent name
  - Purpose
  - Capabilities
  - Status
  - Links to documentation

## 📝 Content Templates

### For `.github/agents/<agent-name>.agent.md`

Start with this structure:

```markdown
# @<agent-name> - [Short Description]

[1-2 sentence overview]

## 🎯 Overview

[What this agent does and when to use it]

## 🚀 Quick Start

[Basic usage examples]

## 🔍 When to Use @<agent-name>

### ✅ Perfect For:
- [Use case 1]
- [Use case 2]

### ❌ Not For:
- [What this agent doesn't do]

## 📋 Capabilities

[Detailed breakdown of what the agent can do]

## 📝 Usage Examples

[5-6 realistic examples with expected outputs]

## 🔄 Integration with Other Agents

[How this agent works with others]

## ❓ FAQ

[Common questions about the agent]

---

**Created:** [Date]
**Agent Type:** [Type]
**Status:** Ready for Integration
```

### For `.copilot/<agent-name>.md`

Use the SAME content as `.github/agents/<agent-name>.agent.md` but with user-focused language and additional context.

## 🔗 Cross-References

When updating files, ensure:

1. **README.md links to `./<agent-name>.md`**
   ```markdown
   - Check `<agent-name>.md` for [description]
   ```

2. **`.github/agents/<agent-name>.agent.md` references other agents**
   ```markdown
   - **@other-agent**: [Why they work together]
   ```

3. **Agent docs reference README.md**
   ```markdown
   - **README.md** - Agent system overview (`.copilot/README.md`)
   ```

## 🎯 Quality Checklist

Before considering an agent "complete", verify:

- [ ] `.github/agents/<agent-name>.agent.md` exists and is complete
- [ ] `.copilot/<agent-name>.md` exists and is complete
- [ ] Agent added to **Current Agents table** in `.copilot/README.md`
- [ ] Agent documentation section updated in `.copilot/README.md`
- [ ] Workflow examples added to `.copilot/README.md`
- [ ] FAQ entry added to `.copilot/README.md`
- [ ] Last Updated date in `.copilot/README.md` is current
- [ ] Status line mentions all integrated agents
- [ ] All cross-references are accurate
- [ ] Examples use consistent formatting and absolute paths where appropriate
- [ ] No broken links or missing references

## 📚 Existing Agent Examples

Refer to these agents as templates:

- **@knowledgebase-wizard** - Documentation search specialist
  - `.github/agents/knowledgebase-wizard.agent.md`
  - `.copilot/knowledgebase-wizard.md`

- **@quality-pal** - Code quality specialist
  - `.github/agents/quality-pal.agent.md`
  - `.copilot/quality-pal.md`

- **@deep-thought** - Strategic advisor specialist
  - `.github/agents/deep-thought.agent.md`
  - `.copilot/deep-thought.md`

## ⚠️ Common Mistakes to Avoid

### ❌ Mistake 1: Only Creating One File
- **Wrong**: Creating only `.copilot/<agent-name>.md`
- **Correct**: Create BOTH `.github/agents/<agent-name>.agent.md` AND `.copilot/<agent-name>.md`

### ❌ Mistake 2: Wrong Naming Convention
- **Wrong**: `AgentName.md`, `agent_name.md`, `agent-namemd`
- **Correct**: `agent-name.md` (kebab-case) and `agent-name.agent.md` (in `.github/agents/`)

### ❌ Mistake 3: Forgetting to Update README.md
- **Wrong**: Creating agent docs but not linking them in `.copilot/README.md`
- **Correct**: Update all 6 sections of README.md (Agent Docs, Table, Learning Resources, FAQ, Workflows, Status)

### ❌ Mistake 4: Incomplete Examples
- **Wrong**: Examples without expected output
- **Correct**: Each example shows the command AND what the user should expect

### ❌ Mistake 5: Inconsistent Formatting
- **Wrong**: Sometimes `.github/agents/`, sometimes `./agents/`, sometimes relative paths
- **Correct**: Always use consistent paths and formats (absolute paths in examples)

## 🔄 Future Agent Additions

When you (or anyone) adds a new agent in the future:

1. **FIRST**: Read this guide to understand file structure
2. **THEN**: Create `.github/agents/<agent-name>.agent.md` (formal spec)
3. **THEN**: Create `.copilot/<agent-name>.md` (user guide)
4. **FINALLY**: Update `.copilot/README.md` in all required sections

This ensures consistency and proper documentation across the entire agent system.

---

**Version:** 1.0  
**Created:** January 19, 2026  
**Last Updated:** January 19, 2026
