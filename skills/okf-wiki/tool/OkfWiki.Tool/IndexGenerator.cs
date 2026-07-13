using System.Globalization;
using System.Text;

namespace OkfWiki.Tool;

internal static class IndexGenerator
{
    public static IReadOnlyList<FileChange> Generate(
        string bundleRoot,
        string targetPath,
        IReadOnlyDictionary<string, FileChange> overlay)
    {
        List<FileChange> changes = [];
        foreach (string directory in GetAffectedDirectories(bundleRoot, targetPath))
        {
            string indexPath = Path.Combine(directory, "index.md");
            bool exists = File.Exists(indexPath);
            string content = BuildIndex(bundleRoot, directory, targetPath, overlay);
            changes.Add(new FileChange(
                indexPath,
                PathPolicy.GetBundleRelativePath(bundleRoot, indexPath),
                "index",
                exists ? "updated" : "created",
                content));
        }

        return changes;
    }

    private static string BuildIndex(
        string bundleRoot,
        string directory,
        string targetPath,
        IReadOnlyDictionary<string, FileChange> overlay)
    {
        List<string> conceptPaths = Directory.Exists(directory)
            ? Directory.EnumerateFiles(directory, "*.md", SearchOption.TopDirectoryOnly)
                .Where(path => !IsReserved(path))
                .ToList()
            : [];
        if (string.Equals(
            Path.GetDirectoryName(targetPath),
            directory,
            PathComparison()) &&
            !conceptPaths.Contains(targetPath, PathComparer()))
        {
            conceptPaths.Add(targetPath);
        }

        List<string> subdirectories = Directory.Exists(directory)
            ? Directory.EnumerateDirectories(directory).ToList()
            : [];
        string targetDirectory = Path.GetDirectoryName(targetPath)!;
        if (!string.Equals(directory, targetDirectory, PathComparison()))
        {
            string relativeTarget = Path.GetRelativePath(directory, targetDirectory);
            string firstSegment = relativeTarget.Split(
                [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar],
                StringSplitOptions.RemoveEmptyEntries)[0];
            string targetChild = Path.Combine(directory, firstSegment);
            if (!subdirectories.Contains(targetChild, PathComparer()))
            {
                subdirectories.Add(targetChild);
            }
        }

        StringBuilder body = new();
        if (conceptPaths.Count > 0)
        {
            body.AppendLine("# Concepts");
            body.AppendLine();
            foreach (string conceptPath in conceptPaths.OrderBy(
                path => Path.GetFileName(path),
                StringComparer.OrdinalIgnoreCase))
            {
                PathPolicy.EnsureNoLinks(bundleRoot, conceptPath);
                string content = overlay.TryGetValue(conceptPath, out FileChange? change)
                    ? change.Content
                    : Utf8File.ReadAllText(conceptPath);
                FrontmatterDocument document = FrontmatterDocument.Parse(
                    content,
                    PathPolicy.GetBundleRelativePath(bundleRoot, conceptPath));
                string? documentTitle = document.GetScalar("title");
                string title = EscapeLabel(ToIndexText(
                    string.IsNullOrWhiteSpace(documentTitle)
                        ? ToTitle(Path.GetFileNameWithoutExtension(conceptPath))
                        : documentTitle));
                string? description = document.GetScalar("description");
                body.Append("* [")
                    .Append(title)
                    .Append("](")
                    .Append(Uri.EscapeDataString(Path.GetFileName(conceptPath)))
                    .Append(')');
                if (!string.IsNullOrWhiteSpace(description))
                {
                    body.Append(" - ").Append(ToIndexText(description));
                }

                body.AppendLine();
            }

            body.AppendLine();
        }

        if (subdirectories.Count > 0)
        {
            body.AppendLine("# Subdirectories");
            body.AppendLine();
            foreach (string subdirectory in subdirectories
                .Where(path => ContainsKnowledge(path, targetPath))
                .OrderBy(path => Path.GetFileName(path), StringComparer.OrdinalIgnoreCase))
            {
                string name = Path.GetFileName(subdirectory);
                body.Append("* [")
                    .Append(EscapeLabel(ToTitle(name)))
                    .Append("](")
                    .Append(Uri.EscapeDataString(name))
                    .Append("/) - Knowledge concepts under ")
                    .Append(ToIndexText(name))
                    .AppendLine(".");
            }
        }

        string renderedBody = body.ToString()
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .TrimEnd() + "\n";
        if (!string.Equals(directory, bundleRoot, PathComparison()))
        {
            return renderedBody;
        }

        string version = ResolveRootVersion(bundleRoot);
        return $"---\nokf_version: \"{version}\"\n---\n\n" + renderedBody;
    }

    private static IReadOnlyList<string> GetAffectedDirectories(
        string bundleRoot,
        string targetPath)
    {
        List<string> directories = [];
        string? current = Path.GetDirectoryName(targetPath);
        while (current is not null)
        {
            directories.Add(current);
            if (string.Equals(current, bundleRoot, PathComparison()))
            {
                break;
            }

            current = Path.GetDirectoryName(current);
        }

        if (directories.Count == 0 ||
            !string.Equals(directories[^1], bundleRoot, PathComparison()))
        {
            throw new OkfWikiException("Concept path is not contained by the bundle root.");
        }

        return directories;
    }

    private static bool ContainsKnowledge(string directory, string targetPath)
    {
        if (targetPath.StartsWith(
            directory + Path.DirectorySeparatorChar,
            PathComparison()))
        {
            return true;
        }

        return Directory.Exists(directory) &&
            Directory.EnumerateFiles(directory, "*.md", SearchOption.AllDirectories)
                .Any();
    }

    private static string ResolveRootVersion(string bundleRoot)
    {
        string indexPath = Path.Combine(bundleRoot, "index.md");
        if (!File.Exists(indexPath))
        {
            return "0.1";
        }

        PathPolicy.EnsureNoLinks(bundleRoot, indexPath);
        string content = Utf8File.ReadAllText(indexPath);
        if (!content.Replace("\r\n", "\n", StringComparison.Ordinal)
            .StartsWith("---\n", StringComparison.Ordinal))
        {
            return "0.1";
        }

        FrontmatterDocument document = FrontmatterDocument.Parse(content, "index.md");
        return document.GetScalar("okf_version") ?? "0.1";
    }

    private static string ToTitle(string value)
    {
        string words = value.Replace('-', ' ').Replace('_', ' ');
        return CultureInfo.InvariantCulture.TextInfo.ToTitleCase(words);
    }

    private static string ToIndexText(string value)
    {
        return string.Join(
            ' ',
            value.Split(
                ['\r', '\n'],
                StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
    }

    private static string EscapeLabel(string value)
    {
        return value.Replace("\\", "\\\\", StringComparison.Ordinal)
            .Replace("[", "\\[", StringComparison.Ordinal)
            .Replace("]", "\\]", StringComparison.Ordinal);
    }

    private static bool IsReserved(string path)
    {
        string name = Path.GetFileName(path);
        return name.Equals("index.md", StringComparison.OrdinalIgnoreCase) ||
            name.Equals("log.md", StringComparison.OrdinalIgnoreCase);
    }

    private static StringComparison PathComparison()
    {
        return OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;
    }

    private static StringComparer PathComparer()
    {
        return OperatingSystem.IsWindows()
            ? StringComparer.OrdinalIgnoreCase
            : StringComparer.Ordinal;
    }
}
