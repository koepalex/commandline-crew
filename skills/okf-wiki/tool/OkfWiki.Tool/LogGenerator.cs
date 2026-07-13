using System.Globalization;

namespace OkfWiki.Tool;

internal static class LogGenerator
{
    public static IReadOnlyList<FileChange> Generate(
        string bundleRoot,
        string targetPath,
        string label,
        string message,
        DateTimeOffset timestamp)
    {
        string localDirectory = Path.GetDirectoryName(targetPath)!;
        HashSet<string> paths = new(PathComparer())
        {
            Path.Combine(bundleRoot, "log.md"),
            Path.Combine(localDirectory, "log.md")
        };
        string date = timestamp.ToUniversalTime().ToString(
            "yyyy-MM-dd",
            CultureInfo.InvariantCulture);
        string entry = $"* **{label}**: {message}";

        return paths.Select(path =>
        {
            bool exists = File.Exists(path);
            PathPolicy.EnsureNoLinks(bundleRoot, path);
            string content = exists
                ? Utf8File.ReadAllText(path)
                : "# Directory Update Log\n";
            return new FileChange(
                path,
                PathPolicy.GetBundleRelativePath(bundleRoot, path),
                "log",
                exists ? "updated" : "created",
                InsertEntry(content, date, entry));
        }).ToArray();
    }

    private static string InsertEntry(string content, string date, string entry)
    {
        string normalized = content.Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .TrimEnd();
        string[] lines = normalized.Split('\n');
        int titleIndex = Array.FindIndex(lines, line => !string.IsNullOrWhiteSpace(line));
        if (titleIndex < 0 ||
            !lines[titleIndex].StartsWith("# ", StringComparison.Ordinal) ||
            lines[titleIndex].StartsWith("## ", StringComparison.Ordinal))
        {
            throw new OkfWikiException(
                "Existing log.md must start with a level-one title.");
        }

        SortedDictionary<DateOnly, List<string>> sections = new(
            Comparer<DateOnly>.Create((left, right) => right.CompareTo(left)));
        DateOnly? currentDate = null;
        for (int index = titleIndex + 1; index < lines.Length; index++)
        {
            string line = lines[index];
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }

            if (TryParseDateHeading(line, out DateOnly parsedDate))
            {
                currentDate = parsedDate;
                if (!sections.ContainsKey(parsedDate))
                {
                    sections.Add(parsedDate, []);
                }
            }
            else if (currentDate is not null &&
                line.StartsWith("* ", StringComparison.Ordinal))
            {
                sections[currentDate.Value].Add(line);
            }
            else
            {
                throw new OkfWikiException(
                    $"Existing log.md contains an unsupported line: {line}");
            }
        }

        DateOnly entryDate = DateOnly.ParseExact(
            date,
            "yyyy-MM-dd",
            CultureInfo.InvariantCulture);
        if (!sections.TryGetValue(entryDate, out List<string>? entries))
        {
            entries = [];
            sections.Add(entryDate, entries);
        }

        entries.Insert(0, entry);
        List<string> output = [lines[titleIndex], string.Empty];
        foreach ((DateOnly sectionDate, List<string> sectionEntries) in sections)
        {
            output.Add($"## {sectionDate:yyyy-MM-dd}");
            output.AddRange(sectionEntries);
            output.Add(string.Empty);
        }

        return string.Join('\n', output).TrimEnd() + "\n";
    }

    private static bool TryParseDateHeading(string line, out DateOnly date)
    {
        if (!line.StartsWith("## ", StringComparison.Ordinal))
        {
            date = default;
            return false;
        }

        return DateOnly.TryParseExact(
            line.AsSpan(3),
            "yyyy-MM-dd",
            CultureInfo.InvariantCulture,
            DateTimeStyles.None,
            out date);
    }

    private static StringComparer PathComparer()
    {
        return OperatingSystem.IsWindows()
            ? StringComparer.OrdinalIgnoreCase
            : StringComparer.Ordinal;
    }
}
