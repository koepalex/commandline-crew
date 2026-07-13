namespace OkfWiki.Tool;

internal static class PathPolicy
{
    private static readonly StringComparison PathComparison =
        OperatingSystem.IsWindows()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal;

    public static string NormalizeBundlePath(string bundlePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(bundlePath);
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(bundlePath));
    }

    public static string ResolveConceptPath(string bundleRoot, string conceptPath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(conceptPath);

        if (Path.IsPathRooted(conceptPath))
        {
            throw new OkfWikiException("Concept paths must be relative to the bundle root.");
        }

        string normalized = conceptPath.Replace(
            Path.AltDirectorySeparatorChar,
            Path.DirectorySeparatorChar);
        if (!normalized.EndsWith(".md", StringComparison.OrdinalIgnoreCase))
        {
            normalized += ".md";
        }

        string fileName = Path.GetFileName(normalized);
        if (string.IsNullOrWhiteSpace(Path.GetFileNameWithoutExtension(fileName)))
        {
            throw new OkfWikiException(
                "Concept paths must end with a non-empty filename.");
        }

        if (fileName.Equals("index.md", StringComparison.OrdinalIgnoreCase) ||
            fileName.Equals("log.md", StringComparison.OrdinalIgnoreCase))
        {
            throw new OkfWikiException(
                $"'{fileName}' is reserved and cannot be used as a concept document.");
        }

        string resolved = Path.GetFullPath(Path.Combine(bundleRoot, normalized));
        string prefix = Path.EndsInDirectorySeparator(bundleRoot)
            ? bundleRoot
            : bundleRoot + Path.DirectorySeparatorChar;
        if (!resolved.StartsWith(prefix, PathComparison))
        {
            throw new OkfWikiException("Concept path escapes the bundle root.");
        }

        EnsureNoLinks(bundleRoot, resolved);
        return resolved;
    }

    public static void EnsureNoLinks(string bundleRoot, string targetPath)
    {
        EnsureNotLink(bundleRoot);

        string relativePath = Path.GetRelativePath(bundleRoot, targetPath);
        string current = bundleRoot;
        foreach (string segment in relativePath.Split(
            [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar],
            StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, segment);
            if (!TryGetAttributes(current, out FileAttributes attributes))
            {
                break;
            }

            if ((attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new OkfWikiException(
                    $"Path '{current}' uses a symbolic link or reparse point.");
            }
        }
    }

    public static string GetBundleRelativePath(string bundleRoot, string fullPath)
    {
        return Path.GetRelativePath(bundleRoot, fullPath)
            .Replace(Path.DirectorySeparatorChar, '/');
    }

    private static void EnsureNotLink(string path)
    {
        if (TryGetAttributes(path, out FileAttributes attributes) &&
            (attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new OkfWikiException(
                $"Bundle root '{path}' uses a symbolic link or reparse point.");
        }
    }

    private static bool TryGetAttributes(
        string path,
        out FileAttributes attributes)
    {
        try
        {
            attributes = File.GetAttributes(path);
            return true;
        }
        catch (FileNotFoundException)
        {
            attributes = default;
            return false;
        }
        catch (DirectoryNotFoundException)
        {
            attributes = default;
            return false;
        }
    }
}
