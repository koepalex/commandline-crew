using System.Text;

namespace OkfWiki.Tool;

internal static class Utf8File
{
    private static readonly UTF8Encoding StrictUtf8 = new(
        encoderShouldEmitUTF8Identifier: false,
        throwOnInvalidBytes: true);

    public static string ReadAllText(string path)
    {
        byte[] bytes = File.ReadAllBytes(path);
        if (HasByteOrderMark(bytes))
        {
            throw new InvalidUtf8Exception(
                $"'{path}' must be UTF-8 without a byte-order mark.");
        }

        try
        {
            return StrictUtf8.GetString(bytes);
        }
        catch (DecoderFallbackException exception)
        {
            throw new InvalidUtf8Exception(
                $"'{path}' contains invalid UTF-8 data.",
                exception);
        }
    }

    public static void WriteAllText(string path, string content)
    {
        File.WriteAllText(path, content, StrictUtf8);
    }

    private static bool HasByteOrderMark(ReadOnlySpan<byte> bytes)
    {
        return bytes.StartsWith(new byte[] { 0xEF, 0xBB, 0xBF }) ||
            bytes.StartsWith(new byte[] { 0xFF, 0xFE }) ||
            bytes.StartsWith(new byte[] { 0xFE, 0xFF }) ||
            bytes.StartsWith(new byte[] { 0xFF, 0xFE, 0x00, 0x00 }) ||
            bytes.StartsWith(new byte[] { 0x00, 0x00, 0xFE, 0xFF });
    }
}
