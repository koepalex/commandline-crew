#:package GitHub.Copilot.SDK@*
#:property PublishAot=false

using GitHub.Copilot.SDK;

// ============================================================================
// Argument helpers
// ============================================================================

static string? ParseArg(string[] args, string flag)
{
    var idx = Array.IndexOf(args, flag);
    return idx != -1 && idx + 1 < args.Length ? args[idx + 1] : null;
}

// ============================================================================
// Main Application
// ============================================================================

Console.WriteLine("📋 Release Note Generator\n");

var repo   = ParseArg(args, "--repo");
var since  = ParseArg(args, "--since");
var branch = ParseArg(args, "--branch");

// Build the opening message. Copilot will ask for anything that is missing.
var providedParts = new List<string>();
if (!string.IsNullOrEmpty(repo))   providedParts.Add($"repository path: {repo}");
if (!string.IsNullOrEmpty(since))  providedParts.Add($"since date: {since}");
if (!string.IsNullOrEmpty(branch)) providedParts.Add($"branch: {branch}");

var providedSummary = providedParts.Count > 0
    ? $"The user provided: {string.Join(", ", providedParts)}."
    : "The user has not provided any arguments yet.";

// Create the Copilot client
await using var client = new CopilotClient(new CopilotClientOptions { LogLevel = "error" });
await client.StartAsync();

var session = await client.CreateSessionAsync(new SessionConfig
{
    Model = "gpt-5",
    OnPermissionRequest = PermissionHandler.ApproveAll,
    SystemMessage = new SystemMessageConfig
    {
        Content = """
<role>
You are a release notes author assistant running in a terminal.
</role>

<workflow>
Step 1 — Gather inputs
  Collect the following from the user (ask conversationally if missing):
  • repository path  — an absolute or relative path to a local git repository
  • since date       — a date like 2025-10-15 or 15.10.2025 (git understands both)
  • branch           — defaults to "main" if not specified

Step 2 — Fetch commits
  Once you have all inputs, run the following shell command:
    git -C <repo> log --no-merges --pretty=format:"%h %s" --after="<since>" <branch>
  If git returns an error or no output, tell the user clearly and stop.

Step 3 - Filtering
  Filter all nuget updates or version bumps

Step 4 — Generate release notes
  Classify every commit into one of these four categories (omit empty ones):
    💥 Breaking Changes
    ✨ New Features
    🔧 Improvements
    🐛 Bug Fixes
  Output the result as a clean markdown document.
  Do NOT invent commits. Use only what git log returned.
  Omit the commit hashes
</workflow>

<rules>
- Keep questions short and friendly.
- Never expose raw error stack traces to the user — summarize them plainly.
- After generating release notes, invite the user to ask follow-up questions
  (e.g. "Show only breaking changes", "Summarize as one paragraph", "Filter by author").
</rules>
"""
    }
});

// Wire up event display
session.On(evt =>
{
    switch (evt)
    {
        case AssistantMessageEvent msg:
            Console.WriteLine($"\n🤖 {msg.Data.Content}\n");
            break;
        case ToolExecutionStartEvent tool:
            Console.WriteLine($"  ⚙️  {tool.Data.ToolName}");
            break;
    }
});

Console.WriteLine("🚀 Starting session...\n");

// Kick off the conversation
await session.SendAsync(new MessageOptions
{
    Prompt = $"""
{providedSummary}
Please start by confirming what you have and asking for anything that is missing,
then proceed to fetch the commits and generate the release notes.
"""
});

// Interactive follow-up loop
Console.WriteLine("\n💡 Ask follow-up questions or type \"exit\" to quit.\n");

while (true)
{
    Console.Write("You: ");
    var input = Console.ReadLine()?.Trim();

    if (string.IsNullOrEmpty(input)) continue;
    if (input.Equals("exit", StringComparison.OrdinalIgnoreCase) ||
        input.Equals("quit", StringComparison.OrdinalIgnoreCase))
    {
        Console.WriteLine("👋 Goodbye!");
        break;
    }

    await session.SendAsync(new MessageOptions { Prompt = input });
}
