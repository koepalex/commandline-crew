using System.Globalization;

namespace OkfWiki.Tool;

/// <summary>Applies and validates Open Knowledge Format v0.1 bundles.</summary>
public sealed class OkfWikiEngine(TimeProvider? timeProvider = null)
{
    private readonly TimeProvider _timeProvider = timeProvider ?? TimeProvider.System;

    /// <summary>Creates or updates one concept and its generated navigation and history files.</summary>
    /// <param name="bundlePath">The bundle root directory.</param>
    /// <param name="manifest">The requested deterministic operation.</param>
    /// <param name="dryRun">Whether to report changes without writing files.</param>
    /// <returns>The planned or completed change summary.</returns>
    public ApplyResult Apply(
        string bundlePath,
        OperationManifest manifest,
        bool dryRun = false)
    {
        ArgumentNullException.ThrowIfNull(manifest);

        string bundleRoot = PathPolicy.NormalizeBundlePath(bundlePath);
        string action = NormalizeAction(manifest.Action);
        string targetPath = ResolveTargetPath(bundleRoot, action, manifest);
        bool exists = File.Exists(targetPath);

        if (action == "create" && exists)
        {
            throw new OkfWikiException(
                $"Concept '{PathPolicy.GetBundleRelativePath(bundleRoot, targetPath)}' already exists.");
        }

        if (action == "update" && !exists)
        {
            throw new OkfWikiException("The requested concept update target does not exist.");
        }

        FrontmatterDocument document = exists
            ? FrontmatterDocument.Parse(
                Utf8File.ReadAllText(targetPath),
                PathPolicy.GetBundleRelativePath(bundleRoot, targetPath))
            : FrontmatterDocument.Create();
        string originalFingerprint = document.GetSemanticFingerprint();

        ApplyManifest(document, manifest, isCreate: !exists);
        string? type = document.GetScalar("type");
        if (string.IsNullOrWhiteSpace(type))
        {
            throw new OkfWikiException("Every concept must have a non-empty type field.");
        }

        bool meaningfulChange = !exists ||
            !string.Equals(
                originalFingerprint,
                document.GetSemanticFingerprint(),
                StringComparison.Ordinal);
        string conceptId = PathPolicy.GetBundleRelativePath(bundleRoot, targetPath)[..^3];
        if (!meaningfulChange)
        {
            return new ApplyResult("unchanged", dryRun, conceptId, [], []);
        }

        document.SetScalar("timestamp", ResolveTimestamp(manifest.Timestamp));
        Dictionary<string, FileChange> changes = new(
            OperatingSystem.IsWindows()
                ? StringComparer.OrdinalIgnoreCase
                : StringComparer.Ordinal);
        AddChange(
            changes,
            bundleRoot,
            targetPath,
            "concept",
            exists ? "updated" : "created",
            document.Render());

        foreach (FileChange change in IndexGenerator.Generate(
            bundleRoot,
            targetPath,
            changes))
        {
            AddIfChanged(changes, change);
        }

        string? documentTitle = document.GetScalar("title");
        string title = string.IsNullOrWhiteSpace(documentTitle)
            ? Path.GetFileNameWithoutExtension(targetPath)
            : documentTitle;
        if (!string.IsNullOrWhiteSpace(manifest.LogMessage) &&
            ContainsNewLine(manifest.LogMessage))
        {
            throw new OkfWikiException("logMessage must be a single line.");
        }

        string logMessage = string.IsNullOrWhiteSpace(manifest.LogMessage)
            ? $"{(exists ? "Updated" : "Created")} [{title}](/" +
                $"{PathPolicy.GetBundleRelativePath(bundleRoot, targetPath)})."
            : manifest.LogMessage.Trim();
        foreach (FileChange change in LogGenerator.Generate(
            bundleRoot,
            targetPath,
            exists ? "Update" : "Creation",
            logMessage,
            _timeProvider.GetUtcNow()))
        {
            AddIfChanged(changes, change);
        }

        IReadOnlyList<string> warnings = dryRun
            ? []
            : FileTransaction.Commit(bundleRoot, changes.Values);

        IReadOnlyList<ChangeSummary> summaries = changes.Values
            .OrderBy(change => change.RelativePath, StringComparer.Ordinal)
            .Select(change => new ChangeSummary(
                change.RelativePath,
                change.Kind,
                change.Action))
            .ToArray();
        return new ApplyResult(
            dryRun ? "preview" : "applied",
            dryRun,
            conceptId,
            summaries,
            warnings);
    }

    /// <summary>Validates an OKF bundle and returns structured diagnostics.</summary>
    /// <param name="bundlePath">The bundle root directory.</param>
    /// <returns>The validation result.</returns>
    public ValidationResult Validate(string bundlePath)
    {
        string bundleRoot = PathPolicy.NormalizeBundlePath(bundlePath);
        return MarkdownBundleValidator.Validate(bundleRoot);
    }

    private static string NormalizeAction(string action)
    {
        if (string.IsNullOrWhiteSpace(action))
        {
            throw new OkfWikiException("action is required.");
        }

        string normalized = action.Trim().ToLowerInvariant();
        return normalized is "create" or "update"
            ? normalized
            : throw new OkfWikiException("action must be 'create' or 'update'.");
    }

    private static string ResolveTargetPath(
        string bundleRoot,
        string action,
        OperationManifest manifest)
    {
        if (!string.IsNullOrWhiteSpace(manifest.ConceptPath))
        {
            return PathPolicy.ResolveConceptPath(bundleRoot, manifest.ConceptPath);
        }

        if (action == "create")
        {
            throw new OkfWikiException("conceptPath is required for create.");
        }

        if (string.IsNullOrWhiteSpace(manifest.MatchResource))
        {
            throw new OkfWikiException(
                "Update requires conceptPath or matchResource.");
        }

        if (!Directory.Exists(bundleRoot))
        {
            throw new OkfWikiException("The bundle does not exist.");
        }

        List<string> matches = [];
        foreach (string path in Directory.EnumerateFiles(
            bundleRoot,
            "*.md",
            SearchOption.AllDirectories))
        {
            if (IsReserved(path))
            {
                continue;
            }

            PathPolicy.EnsureNoLinks(bundleRoot, path);
            FrontmatterDocument document = FrontmatterDocument.Parse(
                Utf8File.ReadAllText(path),
                PathPolicy.GetBundleRelativePath(bundleRoot, path));
            if (string.Equals(
                document.GetScalar("resource"),
                manifest.MatchResource,
                StringComparison.Ordinal))
            {
                matches.Add(path);
            }
        }

        return matches.Count switch
        {
            1 => matches[0],
            0 => throw new OkfWikiException(
                $"No concept has resource '{manifest.MatchResource}'."),
            _ => throw new OkfWikiException(
                $"Resource '{manifest.MatchResource}' matches multiple concepts.")
        };
    }

    private static void ApplyManifest(
        FrontmatterDocument document,
        OperationManifest manifest,
        bool isCreate)
    {
        if (manifest.RemoveFields is not null)
        {
            foreach (string field in manifest.RemoveFields)
            {
                if (string.IsNullOrWhiteSpace(field))
                {
                    throw new OkfWikiException("removeFields cannot contain empty names.");
                }

                document.Remove(field);
            }
        }

        SetOptionalScalar(document, "type", manifest.Type);
        SetOptionalScalar(document, "title", manifest.Title);
        SetOptionalScalar(document, "description", manifest.Description);
        SetOptionalScalar(document, "resource", manifest.Resource);
        if (manifest.Tags is not null)
        {
            if (manifest.Tags.Any(string.IsNullOrWhiteSpace))
            {
                throw new OkfWikiException("tags cannot contain empty values.");
            }

            if (manifest.Tags.Any(ContainsNewLine))
            {
                throw new OkfWikiException("tags must be single-line values.");
            }

            document.SetSequence(
                "tags",
                manifest.Tags.Select(tag => tag.Trim()).Distinct(StringComparer.Ordinal));
        }

        document.MergeExtensions(manifest.Metadata);
        if (manifest.Body is not null)
        {
            document.Body = manifest.Body;
        }
        else if (isCreate)
        {
            document.Body = string.Empty;
        }
    }

    private static void SetOptionalScalar(
        FrontmatterDocument document,
        string key,
        string? value)
    {
        if (value is not null)
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                throw new OkfWikiException(
                    $"{key} cannot be empty; use removeFields to remove optional fields.");
            }

            if (ContainsNewLine(value))
            {
                throw new OkfWikiException($"{key} must be a single-line value.");
            }

            document.SetScalar(key, value.Trim());
        }
    }

    private static bool ContainsNewLine(string value)
    {
        return value.Contains('\r', StringComparison.Ordinal) ||
            value.Contains('\n', StringComparison.Ordinal);
    }

    private string ResolveTimestamp(string? timestamp)
    {
        DateTimeOffset value;
        if (timestamp is null)
        {
            value = _timeProvider.GetUtcNow();
        }
        else if (!HasExplicitOffset(timestamp) ||
            !DateTimeOffset.TryParse(
                timestamp,
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind,
                out value))
        {
            throw new OkfWikiException(
                "timestamp must be a valid ISO 8601 datetime with Z or an explicit offset.");
        }

        return value.ToUniversalTime().ToString(
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            CultureInfo.InvariantCulture);
    }

    private static bool HasExplicitOffset(string timestamp)
    {
        string value = timestamp.Trim();
        if (value.EndsWith('Z') || value.EndsWith('z'))
        {
            return true;
        }

        if (value.Length < 6)
        {
            return false;
        }

        int offsetStart = value.Length - 6;
        return value[offsetStart] is '+' or '-' &&
            value[offsetStart + 3] == ':' &&
            char.IsDigit(value[offsetStart + 1]) &&
            char.IsDigit(value[offsetStart + 2]) &&
            char.IsDigit(value[offsetStart + 4]) &&
            char.IsDigit(value[offsetStart + 5]);
    }

    private static void AddChange(
        IDictionary<string, FileChange> changes,
        string bundleRoot,
        string fullPath,
        string kind,
        string action,
        string content)
    {
        changes[fullPath] = new FileChange(
            fullPath,
            PathPolicy.GetBundleRelativePath(bundleRoot, fullPath),
            kind,
            action,
            content);
    }

    private static void AddIfChanged(
        IDictionary<string, FileChange> changes,
        FileChange change)
    {
        string? existing = changes.TryGetValue(change.FullPath, out FileChange? overlay)
            ? overlay.Content
            : File.Exists(change.FullPath)
                ? Utf8File.ReadAllText(change.FullPath)
                : null;
        if (!string.Equals(
            Normalize(existing),
            Normalize(change.Content),
            StringComparison.Ordinal))
        {
            changes[change.FullPath] = change;
        }
    }

    private static string Normalize(string? value)
    {
        return (value ?? string.Empty)
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n');
    }

    private static bool IsReserved(string path)
    {
        string fileName = Path.GetFileName(path);
        return fileName.Equals("index.md", StringComparison.OrdinalIgnoreCase) ||
            fileName.Equals("log.md", StringComparison.OrdinalIgnoreCase);
    }

}
