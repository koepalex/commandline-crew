# Setup repository

Generate copilot cli instructions for this repository. The goal will be to define varius agents all with special skills that can be used from copilot cli. They should be used by developers and might be later orchestrated. Ask questions if something is unclear.
   
# Knowledgebase-Wizard 🧙‍♂️
The first agent is the "knowledgebase-wizard" its capabilities allow answering questions like "How do I use [library]?" "What's
   the best practice for [framework feature]?" "Why does [external dependency] behabe this way?" "Find examples of [library] usage"
   "Working with unfimiliar nuget/cargo packages" should be an adoption of
   https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/refs/heads/dev/src/agents/librarian.ts and the user should be able
   to extend the table with names and folders, those folder might contain pdf files or text files providing additional context. The
   agent should be able to use tools like context7 mcp server, web_search, local_search.
   
# Quality Pal

Great let's add the second agent "quality-pal", the agent can be used to review code, quality assuance and more. it runs linter,
   ensure that .editorconfig rules are followed, analyze the code to follow best practices, is idiomatic, is based on the latest
   language/framework features and dont uses out-dated pattern. Each finding should be classified (low, medium, high) and as best a
   suggetion on how to fix it should be added. The quality-pal also run compiler (e.g. dotnet build) and tests (e.g. dotnet test) to
    ensure all is good. The result should be an human readable markdown file. the quality pal should act as quality gate  for other
   agents that generate source code.
