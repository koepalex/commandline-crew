#:package GitHub.Copilot.SDK@*
#:property PublishAot=false

using GitHub.Copilot.SDK;
using System.Diagnostics;

// ============================================================================
// Console colour helpers
// ============================================================================

static void WriteColored(string text, ConsoleColor color, bool newLine = true)
{
    Console.ForegroundColor = color;
    if (newLine) Console.WriteLine(text);
    else         Console.Write(text);
    Console.ResetColor();
}

static void WriteInfo(string text)    => WriteColored(text, ConsoleColor.White);
static void WriteUser(string text)    => WriteColored($"\n👤 {text}\n", ConsoleColor.Green);
static void WriteAI(string text)      => WriteColored($"\n🤖 {text}\n", ConsoleColor.Cyan);
static void WriteThinking(string text)=> WriteColored($"  💭 {text}", ConsoleColor.DarkGray);
static void WriteWarning(string text) => WriteColored($"⚠️  {text}", ConsoleColor.Yellow);
static void WriteError(string text)   => WriteColored($"❌ {text}", ConsoleColor.Red);

// ============================================================================
// Argument helpers
// ============================================================================

static string? ParseArg(string[] args, string flag)
{
    var idx = Array.IndexOf(args, flag);
    return idx != -1 && idx + 1 < args.Length ? args[idx + 1] : null;
}

// ============================================================================
// Git helpers
// ============================================================================

static string? RunGit(string workDir, string gitArgs)
{
    try
    {
        using var proc = new Process
        {
            StartInfo = new ProcessStartInfo("git", gitArgs)
            {
                WorkingDirectory       = workDir,
                RedirectStandardOutput = true,
                RedirectStandardError  = true,
                UseShellExecute        = false,
                CreateNoWindow         = true
            }
        };
        proc.Start();
        string output = proc.StandardOutput.ReadToEnd().Trim();
        proc.WaitForExit();
        return proc.ExitCode == 0 ? output : null;
    }
    catch { return null; }
}

static string? CloneRepo(string url, string tempDir)
{
    WriteInfo($"  Cloning {url} ...");
    using var proc = new Process
    {
        StartInfo = new ProcessStartInfo("git", $"clone --depth=1 {url} \"{tempDir}\"")
        {
            RedirectStandardOutput = true,
            RedirectStandardError  = true,
            UseShellExecute        = false,
            CreateNoWindow         = true
        }
    };
    proc.Start();
    proc.WaitForExit();
    return proc.ExitCode == 0 ? tempDir : null;
}

// ============================================================================
// Repo analysis helpers
// ============================================================================

static bool IsUrl(string value) =>
    value.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
    value.StartsWith("https://", StringComparison.OrdinalIgnoreCase) ||
    value.StartsWith("git@",     StringComparison.OrdinalIgnoreCase);

static bool HasUsageExamples(string repoPath)
{
    // Check samples/ or test(s)/ directory
    bool hasSamplesDir = Directory.Exists(Path.Combine(repoPath, "samples")) ||
                         Directory.Exists(Path.Combine(repoPath, "sample"));
    bool hasTestsDir   = Directory.Exists(Path.Combine(repoPath, "tests")) ||
                         Directory.Exists(Path.Combine(repoPath, "test"));

    // Check README for fenced code blocks
    var readmePath = Path.Combine(repoPath, "README.md");
    bool readmeHasCode = false;
    if (File.Exists(readmePath))
    {
        var content = File.ReadAllText(readmePath);
        readmeHasCode = content.Contains("```");
    }

    return hasSamplesDir || hasTestsDir || readmeHasCode;
}

// ============================================================================
// Main
// ============================================================================

Console.WriteLine("🔬 SKILL.md Generator\n");

var source = ParseArg(args, "--source");
var target = ParseArg(args, "--target");

// --- Resolve repo path (clone if URL) ----------------------------------------

string? tempCloneDir = null;
string? repoPath = null;

if (!string.IsNullOrEmpty(source))
{
    if (IsUrl(source))
    {
        tempCloneDir = Path.Combine(Path.GetTempPath(), $"skill-md-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tempCloneDir);
        repoPath = CloneRepo(source, tempCloneDir);
        if (repoPath == null)
        {
            WriteError($"Failed to clone repository: {source}");
            Environment.Exit(1);
        }
        WriteInfo($"  ✅ Cloned to {repoPath}\n");
    }
    else if (Directory.Exists(source))
    {
        repoPath = Path.GetFullPath(source);
    }
    else
    {
        WriteError($"Source path does not exist: {source}");
        Environment.Exit(1);
    }
}

// --- Pre-flight checks (only when we already have a local path) ---------------

if (repoPath != null)
{
    // Staleness check
    var lastCommit = RunGit(repoPath, "log -1 --format=%ci");
    if (!string.IsNullOrEmpty(lastCommit) &&
        DateTime.TryParse(lastCommit.Split(' ')[0], out var commitDate) &&
        (DateTime.UtcNow - commitDate).TotalDays > 365)
    {
        WriteWarning($"Repository is stale — last commit was {commitDate:yyyy-MM-dd} (over a year ago).");
    }

    // License check
    var licenseFile = Directory.GetFiles(repoPath, "LICENSE*", SearchOption.TopDirectoryOnly)
                               .FirstOrDefault() ??
                      Directory.GetFiles(repoPath, "COPYING*", SearchOption.TopDirectoryOnly)
                               .FirstOrDefault();
    if (licenseFile == null)
    {
        WriteWarning("No LICENSE file found. Unable to verify license.");
    }
    else
    {
        var licenseText = File.ReadAllText(licenseFile);
        bool isMIT     = licenseText.Contains("MIT", StringComparison.OrdinalIgnoreCase);
        bool isApache  = licenseText.Contains("Apache", StringComparison.OrdinalIgnoreCase);
        if (!isMIT && !isApache)
            WriteWarning("License does not appear to be MIT or Apache 2.0. Review before use.");
    }

    // Fallback warning
    if (!HasUsageExamples(repoPath))
        WriteWarning("No samples, tests, or README code examples found — will fall back to public API analysis.");
}

// --- Derive target path -------------------------------------------------------

string resolvedTarget = string.IsNullOrEmpty(target) ? Directory.GetCurrentDirectory() : target;

// --- Build the opening prompt -------------------------------------------------

var providedParts = new List<string>();
if (repoPath != null)           providedParts.Add($"repository path: {repoPath}");
if (!string.IsNullOrEmpty(target)) providedParts.Add($"target folder: {resolvedTarget}");

var providedSummary = providedParts.Count > 0
    ? $"The user provided: {string.Join(", ", providedParts)}."
    : "The user has not provided any arguments yet.";

// ============================================================================
// Copilot session
// ============================================================================

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
You are a library documentation analyst. Your job is to analyse a source code repository and
produce a concise SKILL.md that helps AI assistants and developers super-charge their usage of
the library.
</role>

<workflow>
Step 1 — Gather inputs
  Collect the following if not already provided (ask conversationally, one at a time):
  • repository path  — absolute path to a local git repository
  • target folder    — absolute path where SKILL.md should be written

Step 2 — Detect package name
  • Read the first H1 heading from README.md.
  • If absent, use the repository folder name.
  • Sanitize to a safe directory name (alphanumerics, hyphens, dots only).
  • Output path will be: <target folder>/<package name>/SKILL.md

Step 3 — Analyse the repository
  Use shell commands (cat, Get-Content, Get-ChildItem / find / ls) to explore the repository.

  Priority order for usage examples:
    1. README.md code blocks (fenced ```)
    2. All files under samples/ or sample/
    3. All files under tests/ or test/ or __tests__/
    4. FALLBACK (only if none of the above exist):
       Scan src/ or lib/ for public classes, public methods, and public interfaces.
       Print a visible warning line: "⚠️  No samples/tests found — analysing public API surface."

  While analysing:
  • PREFER async APIs over sync siblings.
  • Combine definitions from multiple files; DO NOT just copy-paste minimal snippets.
  • Extract one-line comments from XML doc comments (<summary>) where available.
  • Identify and describe:
      - Logging / tracing: what is built-in, how to enable it, relevant options.
      - Error handling: the dominant pattern (exceptions, Result<T>, error callbacks…).
      - Architecture: notable design patterns (Builder, Factory, DI, event-driven…).

Step 4 — Generate SKILL.md
  Write a single concise markdown file. Structure:
  ```
  # <Package Name> — API Skill Reference

  ## Overview
  One-paragraph description (from README or inferred).

  ## Quick Start
  Minimal working example showing initialisation + primary use case.

  ## Core APIs  (grouped by functional area)
  ### <Area 1>
  <!-- one-line comment -->
  <api signature or usage snippet>
  ...

  ## Logging & Tracing
  How to enable and configure (code snippet).

  ## Error Handling
  Dominant pattern with a short example.

  ## Architecture Notes
  Key design patterns observed (2–5 bullet points).

  ## ⚠️  Caveats
  Any warnings discovered (staleness, license, missing docs).
  ```
  Keep the total file under ~250 lines. Prefer concise snippets over lengthy prose.

Step 5 — Write the file
  • Create the output directory if it does not exist:
      mkdir -p <target>/<package> (or equivalent for the OS)
  • Write the SKILL.md file using a shell command.
  • Print the final path of the written file.

Step 6 — Invite follow-up
  Tell the user the file has been written and invite questions or refinements
  (e.g. "Add more examples", "Focus only on async APIs", "Translate to a different style").
</workflow>

<rules>
- Keep questions short and conversational.
- Never expose raw stack traces — summarise errors plainly.
- Do NOT invent APIs. Only document what you observe in the source.
- If a section has nothing to report, omit it rather than writing "N/A".
</rules>
"""
    }
});

// ============================================================================
// Event wiring
// ============================================================================

Spinner? spinner = new Spinner("  Processing ");

session.On(evt =>
{
    switch (evt)
    {
        case AssistantMessageEvent msg:
            spinner?.Dispose();
            spinner = null;
            WriteAI(msg.Data.Content);
            break;

        case ToolExecutionStartEvent tool:
            spinner?.Dispose();
            spinner = null;
            WriteThinking($"Running: {tool.Data.ToolName}");
            spinner = new Spinner("  ");
            break;

        default:
            // Unknown event types — log in dark grey for transparency
            WriteThinking($"[event] {evt.GetType().Name}");
            break;
    }
});

WriteInfo("🚀 Starting analysis session...\n");

// ============================================================================
// Kick off the conversation
// ============================================================================

await session.SendAsync(new MessageOptions
{
    Prompt = $"""
{providedSummary}
Please start by confirming the repository path and target folder (ask if missing),
then analyse the repository and generate the SKILL.md file.
"""
});

spinner?.Dispose();
spinner = null;

// ============================================================================
// Interactive follow-up loop
// ============================================================================

Console.WriteLine();
WriteInfo("💡 Ask follow-up questions or type \"exit\" to quit.\n");

while (true)
{
    Console.ForegroundColor = ConsoleColor.Green;
    Console.Write("You: ");
    Console.ResetColor();

    var input = Console.ReadLine()?.Trim();
    if (string.IsNullOrEmpty(input)) continue;
    if (input.Equals("exit",  StringComparison.OrdinalIgnoreCase) ||
        input.Equals("quit",  StringComparison.OrdinalIgnoreCase))
    {
        WriteInfo("👋 Goodbye!");
        break;
    }

    WriteUser(input);
    spinner = new Spinner("  Thinking ");
    await session.SendAsync(new MessageOptions { Prompt = input });
    spinner?.Dispose();
    spinner = null;
}

// ============================================================================
// Cleanup temp clone
// ============================================================================

if (tempCloneDir != null && Directory.Exists(tempCloneDir))
{
    try
    {
        // Git objects are read-only on Windows — reset attributes before deleting
        foreach (var file in Directory.EnumerateFiles(tempCloneDir, "*", SearchOption.AllDirectories))
            File.SetAttributes(file, FileAttributes.Normal);
        Directory.Delete(tempCloneDir, recursive: true);
    }
    catch
    {
        WriteWarning($"Could not clean up temp clone at {tempCloneDir}");
    }
}

// ============================================================================
// Spinner — type declaration must follow all top-level statements (CS8803)
// ============================================================================

sealed class Spinner : IDisposable
{
    static readonly char[] Frames = ['/', '-', '\\', '|'];
    readonly CancellationTokenSource _cts = new();
    readonly Task _task;

    public Spinner() : this("  ") { }

    public Spinner(string prefix)
    {
        _task = Task.Run(async () =>
        {
            int i = 0;
            while (!_cts.Token.IsCancellationRequested)
            {
                Console.ForegroundColor = ConsoleColor.DarkGray;
                Console.Write($"\r{prefix}{Frames[i++ % Frames.Length]} ");
                Console.ResetColor();
                try { await Task.Delay(120, _cts.Token); }
                catch (OperationCanceledException) { break; }
            }
            Console.Write("\r  \r"); // erase spinner line
        });
    }

    public void Dispose()
    {
        _cts.Cancel();
        try { _task.Wait(); } catch { /* ignore */ }
        _cts.Dispose();
    }
}
