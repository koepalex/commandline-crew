namespace OkfWiki.Tool;

internal sealed class InvalidUtf8Exception(
    string message,
    Exception? innerException = null)
    : OkfWikiException(message, innerException);
