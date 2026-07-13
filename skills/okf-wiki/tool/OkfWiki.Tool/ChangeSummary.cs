namespace OkfWiki.Tool;

/// <summary>Describes one file created or updated by an OKF operation.</summary>
public sealed record ChangeSummary(string Path, string Kind, string Action);
