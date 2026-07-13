namespace OkfWiki.Tool;

/// <summary>Represents invalid OKF input or an unsafe bundle operation.</summary>
public class OkfWikiException(string message, Exception? innerException = null)
    : Exception(message, innerException);
