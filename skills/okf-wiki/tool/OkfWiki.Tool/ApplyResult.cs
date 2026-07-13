namespace OkfWiki.Tool;

/// <summary>Reports the planned or completed changes for an OKF apply operation.</summary>
public sealed record ApplyResult(
    string Status,
    bool DryRun,
    string ConceptId,
    IReadOnlyList<ChangeSummary> Changes,
    IReadOnlyList<string> Warnings);
