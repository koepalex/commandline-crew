using System.Text.RegularExpressions;

namespace OkfWiki.Tool;

internal static partial class MarkdownBundleValidator
{
    public static ValidationResult Validate(string bundleRoot)
    {
        List<Diagnostic> diagnostics = [];
        if (!Directory.Exists(bundleRoot))
        {
            diagnostics.Add(new Diagnostic(
                "error",
                ".",
                "bundle.missing",
                "The bundle directory does not exist."));
            return new ValidationResult(false, 0, diagnostics);
        }

        try
        {
            PathPolicy.EnsureNoLinks(bundleRoot, bundleRoot);
        }
        catch (OkfWikiException exception)
        {
            diagnostics.Add(new Diagnostic(
                "error",
                ".",
                "bundle.path.unsafe",
                exception.Message));
            return new ValidationResult(false, 0, diagnostics);
        }

        int conceptCount = 0;
        Dictionary<string, List<string>> resources = new(StringComparer.Ordinal);
        foreach (string path in Directory.EnumerateFiles(
            bundleRoot,
            "*.md",
            SearchOption.AllDirectories))
        {
            string relativePath = PathPolicy.GetBundleRelativePath(bundleRoot, path);
            string content;
            try
            {
                PathPolicy.EnsureNoLinks(bundleRoot, path);
                content = Utf8File.ReadAllText(path);
            }
            catch (InvalidUtf8Exception exception)
            {
                diagnostics.Add(new Diagnostic(
                    "error",
                    relativePath,
                    "file.encoding.invalid",
                    exception.Message));
                continue;
            }
            catch (OkfWikiException exception)
            {
                diagnostics.Add(new Diagnostic(
                    "error",
                    relativePath,
                    "file.path.unsafe",
                    exception.Message));
                continue;
            }

            string fileName = Path.GetFileName(path);
            if (fileName.Equals("index.md", StringComparison.OrdinalIgnoreCase))
            {
                ValidateIndex(bundleRoot, path, relativePath, content, diagnostics);
                continue;
            }

            if (fileName.Equals("log.md", StringComparison.OrdinalIgnoreCase))
            {
                ValidateLog(relativePath, content, diagnostics);
                continue;
            }

            conceptCount++;
            try
            {
                FrontmatterDocument document = FrontmatterDocument.Parse(
                    content,
                    relativePath);
                if (string.IsNullOrWhiteSpace(document.GetScalar("type")))
                {
                    diagnostics.Add(new Diagnostic(
                        "error",
                        relativePath,
                        "concept.type.required",
                        "Concept frontmatter must contain a non-empty type field."));
                }

                string? resource = document.GetScalar("resource");
                if (!string.IsNullOrWhiteSpace(resource))
                {
                    if (!resources.TryGetValue(resource, out List<string>? paths))
                    {
                        paths = [];
                        resources.Add(resource, paths);
                    }

                    paths.Add(relativePath);
                }
            }
            catch (OkfWikiException exception)
            {
                diagnostics.Add(new Diagnostic(
                    "error",
                    relativePath,
                    "concept.frontmatter.invalid",
                    exception.Message));
            }
        }

        foreach ((string resource, List<string> paths) in resources.Where(
            pair => pair.Value.Count > 1))
        {
            foreach (string path in paths)
            {
                diagnostics.Add(new Diagnostic(
                    "warning",
                    path,
                    "concept.resource.duplicate",
                    $"Resource '{resource}' is also used by: " +
                    string.Join(", ", paths.Where(other => other != path))));
            }
        }

        return new ValidationResult(
            diagnostics.All(diagnostic => diagnostic.Severity != "error"),
            conceptCount,
            diagnostics);
    }

    private static void ValidateIndex(
        string bundleRoot,
        string path,
        string relativePath,
        string content,
        ICollection<Diagnostic> diagnostics)
    {
        string normalizedContent = Normalize(content);
        string body = normalizedContent;
        if (normalizedContent.StartsWith("---\n", StringComparison.Ordinal))
        {
            if (!string.Equals(path, Path.Combine(bundleRoot, "index.md"), PathComparison()))
            {
                diagnostics.Add(new Diagnostic(
                    "error",
                    relativePath,
                    "index.frontmatter.forbidden",
                    "Only the bundle-root index.md may contain frontmatter."));
                return;
            }

            try
            {
                FrontmatterDocument document = FrontmatterDocument.Parse(
                    normalizedContent,
                    relativePath);
                string[] keys = document.Metadata.Children.Keys
                    .OfType<YamlDotNet.RepresentationModel.YamlScalarNode>()
                    .Select(key => key.Value ?? string.Empty)
                    .ToArray();
                if (keys.Any(key => key != "okf_version"))
                {
                    diagnostics.Add(new Diagnostic(
                        "error",
                        relativePath,
                        "index.frontmatter.fields",
                        "Root index frontmatter may contain only okf_version."));
                }

                body = document.Body;
            }
            catch (OkfWikiException exception)
            {
                diagnostics.Add(new Diagnostic(
                    "error",
                    relativePath,
                    "index.frontmatter.invalid",
                    exception.Message));
                return;
            }
        }

        bool hasHeading = false;
        foreach (string line in Normalize(body).Split('\n'))
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            if (IndexHeadingRegex().IsMatch(line))
            {
                hasHeading = true;
            }
            else if (!IndexEntryRegex().IsMatch(line))
            {
                diagnostics.Add(new Diagnostic(
                    "error",
                    relativePath,
                    "index.structure.invalid",
                    $"Unsupported index line: {line}"));
            }
        }

        if (!hasHeading)
        {
            diagnostics.Add(new Diagnostic(
                "error",
                relativePath,
                "index.heading.required",
                "Index files must contain at least one level-one section heading."));
        }
    }

    private static void ValidateLog(
        string relativePath,
        string content,
        ICollection<Diagnostic> diagnostics)
    {
        string[] lines = Normalize(content).Split('\n');
        int firstContent = Array.FindIndex(lines, line => !string.IsNullOrWhiteSpace(line));
        if (firstContent < 0 || !LogTitleRegex().IsMatch(lines[firstContent]))
        {
            diagnostics.Add(new Diagnostic(
                "error",
                relativePath,
                "log.title.required",
                "Log files must start with a level-one title."));
            return;
        }

        bool hasDate = false;
        bool withinDate = false;
        for (int index = firstContent + 1; index < lines.Length; index++)
        {
            string line = lines[index];
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            if (TryParseLogDateHeading(line))
            {
                hasDate = true;
                withinDate = true;
            }
            else if (line.StartsWith("## ", StringComparison.Ordinal))
            {
                withinDate = false;
                diagnostics.Add(new Diagnostic(
                    "error",
                    relativePath,
                    "log.date.invalid",
                    $"Log date heading is not a valid calendar date: {line}"));
            }
            else if (!withinDate || !line.StartsWith("* ", StringComparison.Ordinal))
            {
                diagnostics.Add(new Diagnostic(
                    "error",
                    relativePath,
                    "log.structure.invalid",
                    $"Unsupported log line: {line}"));
            }
        }

        if (!hasDate)
        {
            diagnostics.Add(new Diagnostic(
                "error",
                relativePath,
                "log.date.required",
                "Log files must contain at least one YYYY-MM-DD date heading."));
        }
    }

    private static string Normalize(string value)
    {
        return value.Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n');
    }

    private static StringComparison PathComparison()
    {
        return OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;
    }

    private static bool TryParseLogDateHeading(string line)
    {
        return line.StartsWith("## ", StringComparison.Ordinal) &&
            DateOnly.TryParseExact(
                line.AsSpan(3),
                "yyyy-MM-dd",
                System.Globalization.CultureInfo.InvariantCulture,
                System.Globalization.DateTimeStyles.None,
                out _);
    }

    [GeneratedRegex("^# [^#].+$", RegexOptions.CultureInvariant)]
    private static partial Regex IndexHeadingRegex();

    [GeneratedRegex(
        "^\\* \\[(?:\\\\.|[^\\]])+\\]\\([^\\)]+\\)(?: - .+)?$",
        RegexOptions.CultureInvariant)]
    private static partial Regex IndexEntryRegex();

    [GeneratedRegex("^# .+$", RegexOptions.CultureInvariant)]
    private static partial Regex LogTitleRegex();

}
