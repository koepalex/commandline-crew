using System.Text.Json;

namespace OkfWiki.Tool;

internal static class CliApplication
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    public static async Task<int> RunAsync(
        string[] args,
        TextWriter output,
        TextWriter error)
    {
        try
        {
            CliArguments arguments = CliArguments.Parse(args);
            OkfWikiEngine engine = new();

            if (string.Equals(arguments.Command, "apply", StringComparison.OrdinalIgnoreCase))
            {
                string manifestJson = await File.ReadAllTextAsync(arguments.ManifestPath!);
                OperationManifest? manifest = JsonSerializer.Deserialize<OperationManifest>(
                    manifestJson,
                    JsonOptions);
                if (manifest is null)
                {
                    throw new OkfWikiException("The operation manifest is empty.");
                }

                ApplyResult result = engine.Apply(
                    arguments.BundlePath,
                    manifest,
                    arguments.DryRun);
                await output.WriteLineAsync(JsonSerializer.Serialize(result, JsonOptions));
                return 0;
            }

            ValidationResult validation = engine.Validate(arguments.BundlePath);
            await output.WriteLineAsync(JsonSerializer.Serialize(validation, JsonOptions));
            return validation.IsValid ? 0 : 2;
        }
        catch (OkfWikiException exception)
        {
            await error.WriteLineAsync(JsonSerializer.Serialize(
                new { error = exception.Message },
                JsonOptions));
            return 2;
        }
        catch (JsonException exception)
        {
            await error.WriteLineAsync(JsonSerializer.Serialize(
                new { error = $"Invalid JSON: {exception.Message}" },
                JsonOptions));
            return 2;
        }
        catch (IOException exception)
        {
            await error.WriteLineAsync(JsonSerializer.Serialize(
                new { error = exception.Message },
                JsonOptions));
            return 3;
        }
        catch (UnauthorizedAccessException exception)
        {
            await error.WriteLineAsync(JsonSerializer.Serialize(
                new { error = exception.Message },
                JsonOptions));
            return 3;
        }
    }
}
