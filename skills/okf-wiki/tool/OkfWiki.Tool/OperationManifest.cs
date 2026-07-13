using System.Text.Json;

namespace OkfWiki.Tool;

/// <summary>Describes one deterministic OKF concept creation or update.</summary>
public sealed record OperationManifest
{
    /// <summary>Gets the operation action: <c>create</c> or <c>update</c>.</summary>
    public required string Action { get; init; }

    /// <summary>Gets the bundle-relative concept path, with or without the .md suffix.</summary>
    public string? ConceptPath { get; init; }

    /// <summary>Gets the unique resource URI used to locate a concept when no path is supplied.</summary>
    public string? MatchResource { get; init; }

    /// <summary>Gets the required OKF concept type.</summary>
    public string? Type { get; init; }

    /// <summary>Gets the optional display title.</summary>
    public string? Title { get; init; }

    /// <summary>Gets the optional one-line description.</summary>
    public string? Description { get; init; }

    /// <summary>Gets the optional canonical resource URI.</summary>
    public string? Resource { get; init; }

    /// <summary>Gets optional cross-cutting tags.</summary>
    public IReadOnlyList<string>? Tags { get; init; }

    /// <summary>Gets the optional ISO 8601 timestamp override.</summary>
    public string? Timestamp { get; init; }

    /// <summary>Gets producer-defined top-level YAML metadata.</summary>
    public JsonElement Metadata { get; init; }

    /// <summary>Gets optional metadata fields to remove during an update.</summary>
    public IReadOnlyList<string>? RemoveFields { get; init; }

    /// <summary>Gets the markdown body. Updates preserve the current body when omitted.</summary>
    public string? Body { get; init; }

    /// <summary>Gets the prose used in generated log entries.</summary>
    public string? LogMessage { get; init; }
}
