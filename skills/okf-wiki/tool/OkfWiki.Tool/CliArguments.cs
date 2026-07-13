namespace OkfWiki.Tool;

internal sealed record CliArguments(
    string Command,
    string BundlePath,
    string? ManifestPath,
    bool DryRun)
{
    public static CliArguments Parse(string[] args)
    {
        if (args.Length == 0)
        {
            throw Usage();
        }

        string command = args[0].ToLowerInvariant();
        if (command is not ("apply" or "validate"))
        {
            throw Usage();
        }

        string? bundlePath = null;
        string? manifestPath = null;
        bool dryRun = false;

        for (int index = 1; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--bundle" when index + 1 < args.Length:
                    bundlePath = args[++index];
                    break;
                case "--manifest" when index + 1 < args.Length:
                    manifestPath = args[++index];
                    break;
                case "--dry-run":
                    dryRun = true;
                    break;
                case "--json":
                    break;
                default:
                    throw Usage();
            }
        }

        if (string.IsNullOrWhiteSpace(bundlePath))
        {
            throw new OkfWikiException("--bundle is required.");
        }

        if (command == "apply" && string.IsNullOrWhiteSpace(manifestPath))
        {
            throw new OkfWikiException("--manifest is required for apply.");
        }

        if (command == "validate" && dryRun)
        {
            throw new OkfWikiException("--dry-run is only valid with apply.");
        }

        return new CliArguments(command, bundlePath, manifestPath, dryRun);
    }

    private static OkfWikiException Usage()
    {
        return new OkfWikiException(
            "Usage: apply --bundle <path> --manifest <json> [--dry-run] | " +
            "validate --bundle <path> [--json]");
    }
}
