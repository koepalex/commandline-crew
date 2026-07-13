namespace OkfWiki.Tool;

/// <summary>Describes one bundle validation error or warning.</summary>
public sealed record Diagnostic(
    string Severity,
    string Path,
    string Code,
    string Message);
