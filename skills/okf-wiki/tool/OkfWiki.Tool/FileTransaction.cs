namespace OkfWiki.Tool;

internal static class FileTransaction
{
    public static IReadOnlyList<string> Commit(
        string bundleRoot,
        IEnumerable<FileChange> changes)
    {
        List<StagedChange> stagedChanges = [];
        HashSet<string> createdDirectories = new(PathComparer());
        List<string> warnings = [];
        bool committed = false;

        try
        {
            foreach (FileChange change in changes)
            {
                PathPolicy.EnsureNoLinks(bundleRoot, change.FullPath);
                string directory = Path.GetDirectoryName(change.FullPath) ??
                    throw new OkfWikiException(
                        $"Cannot resolve the directory for '{change.FullPath}'.");
                TrackMissingDirectories(directory, createdDirectories);
                Directory.CreateDirectory(directory);

                string stagedPath = Path.Combine(
                    directory,
                    $".{Path.GetFileName(change.FullPath)}.{Guid.NewGuid():N}.stage");
                string backupPath = Path.Combine(
                    directory,
                    $".{Path.GetFileName(change.FullPath)}.{Guid.NewGuid():N}.backup");
                StagedChange stagedChange = new(
                    change.FullPath,
                    stagedPath,
                    backupPath);
                stagedChanges.Add(stagedChange);
                Utf8File.WriteAllText(stagedPath, change.Content);
            }

            foreach (StagedChange change in stagedChanges)
            {
                PathPolicy.EnsureNoLinks(bundleRoot, change.TargetPath);
                if (Directory.Exists(change.TargetPath))
                {
                    throw new IOException(
                        $"Cannot replace '{change.TargetPath}' because it is a directory.");
                }

                if (File.Exists(change.TargetPath))
                {
                    File.Move(change.TargetPath, change.BackupPath);
                    change.HasBackup = true;
                }

                File.Move(change.StagedPath, change.TargetPath);
                change.IsCommitted = true;
            }

            committed = true;
            foreach (StagedChange change in stagedChanges.Where(
                change => change.HasBackup))
            {
                try
                {
                    File.Delete(change.BackupPath);
                    change.HasBackup = false;
                }
                catch (IOException exception)
                {
                    warnings.Add(
                        $"Applied changes, but could not remove backup " +
                        $"'{change.BackupPath}': {exception.Message}");
                }
                catch (UnauthorizedAccessException exception)
                {
                    warnings.Add(
                        $"Applied changes, but could not remove backup " +
                        $"'{change.BackupPath}': {exception.Message}");
                }
            }
        }
        catch (IOException)
        {
            if (!committed)
            {
                Rollback(stagedChanges);
            }

            throw;
        }
        catch (UnauthorizedAccessException)
        {
            if (!committed)
            {
                Rollback(stagedChanges);
            }

            throw;
        }
        catch (OkfWikiException)
        {
            if (!committed)
            {
                Rollback(stagedChanges);
            }

            throw;
        }
        finally
        {
            CleanupStagedFiles(stagedChanges);
            if (!committed)
            {
                CleanupCreatedDirectories(createdDirectories);
            }
        }

        return warnings;
    }

    private static void Rollback(IReadOnlyList<StagedChange> changes)
    {
        List<Exception> failures = [];
        foreach (StagedChange change in changes.Reverse())
        {
            try
            {
                if (change.IsCommitted && File.Exists(change.TargetPath))
                {
                    File.Delete(change.TargetPath);
                    change.IsCommitted = false;
                }

                if (change.HasBackup && File.Exists(change.BackupPath))
                {
                    File.Move(change.BackupPath, change.TargetPath);
                    change.HasBackup = false;
                }
            }
            catch (IOException exception)
            {
                failures.Add(exception);
            }
            catch (UnauthorizedAccessException exception)
            {
                failures.Add(exception);
            }
        }

        if (failures.Count > 0)
        {
            throw new OkfWikiException(
                "The OKF apply failed and one or more files could not be rolled back.",
                new AggregateException(failures));
        }
    }

    private static void CleanupStagedFiles(IEnumerable<StagedChange> changes)
    {
        foreach (StagedChange change in changes)
        {
            if (File.Exists(change.StagedPath))
            {
                File.Delete(change.StagedPath);
            }
        }
    }

    private static void TrackMissingDirectories(
        string directory,
        ISet<string> createdDirectories)
    {
        string? current = directory;
        while (current is not null && !Directory.Exists(current))
        {
            createdDirectories.Add(current);
            current = Path.GetDirectoryName(current);
        }
    }

    private static void CleanupCreatedDirectories(IEnumerable<string> directories)
    {
        foreach (string directory in directories.OrderByDescending(
            path => path.Length))
        {
            if (Directory.Exists(directory) &&
                !Directory.EnumerateFileSystemEntries(directory).Any())
            {
                Directory.Delete(directory);
            }
        }
    }

    private static StringComparer PathComparer()
    {
        return OperatingSystem.IsWindows()
            ? StringComparer.OrdinalIgnoreCase
            : StringComparer.Ordinal;
    }

    private sealed class StagedChange(
        string targetPath,
        string stagedPath,
        string backupPath)
    {
        public string TargetPath { get; } = targetPath;

        public string StagedPath { get; } = stagedPath;

        public string BackupPath { get; } = backupPath;

        public bool HasBackup { get; set; }

        public bool IsCommitted { get; set; }
    }
}
