namespace OkfWiki.Tool;

/// <summary>Reports OKF bundle conformance diagnostics.</summary>
public sealed record ValidationResult(
    bool IsValid,
    int ConceptCount,
    IReadOnlyList<Diagnostic> Diagnostics);
