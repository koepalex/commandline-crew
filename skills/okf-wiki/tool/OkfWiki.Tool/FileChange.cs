namespace OkfWiki.Tool;

internal sealed record FileChange(
    string FullPath,
    string RelativePath,
    string Kind,
    string Action,
    string Content);
