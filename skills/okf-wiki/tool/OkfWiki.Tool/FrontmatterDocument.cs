using System.Diagnostics.CodeAnalysis;
using System.Text;
using System.Text.Json;
using YamlDotNet.Core;
using YamlDotNet.RepresentationModel;

namespace OkfWiki.Tool;

internal sealed class FrontmatterDocument
{
    private static readonly string[] KnownFieldOrder =
    [
        "type",
        "title",
        "description",
        "resource",
        "tags",
        "timestamp"
    ];

    private FrontmatterDocument(YamlMappingNode metadata, string body)
    {
        Metadata = metadata;
        Body = NormalizeBody(body);
    }

    public YamlMappingNode Metadata { get; }

    public string Body { get; set; }

    public static FrontmatterDocument Create()
    {
        return new FrontmatterDocument([], string.Empty);
    }

    public static FrontmatterDocument Parse(string content, string path)
    {
        string normalized = NormalizeNewLines(content);
        string[] lines = normalized.Split('\n');
        if (lines.Length < 3 || lines[0] != "---")
        {
            throw new OkfWikiException(
                $"'{path}' must start with a YAML frontmatter delimiter.");
        }

        int closingIndex = Array.FindIndex(lines, 1, line => line == "---");
        if (closingIndex < 0)
        {
            throw new OkfWikiException(
                $"'{path}' does not contain a closing YAML frontmatter delimiter.");
        }

        string yaml = string.Join('\n', lines[1..closingIndex]);
        string body = string.Join('\n', lines[(closingIndex + 1)..]);

        try
        {
            YamlStream stream = new();
            stream.Load(new StringReader(yaml));
            if (stream.Documents.Count != 1 ||
                stream.Documents[0].RootNode is not YamlMappingNode mapping)
            {
                throw new OkfWikiException(
                    $"'{path}' frontmatter must be a single YAML mapping.");
            }

            return new FrontmatterDocument(mapping, body);
        }
        catch (YamlException exception)
        {
            throw new OkfWikiException(
                $"'{path}' contains invalid YAML frontmatter: {exception.Message}",
                exception);
        }
        catch (InvalidOperationException exception)
        {
            throw new OkfWikiException(
                $"'{path}' contains invalid YAML frontmatter: {exception.Message}",
                exception);
        }
    }

    public string? GetScalar(string key)
    {
        return TryGetNode(key, out YamlNode? node) && node is YamlScalarNode scalar
            ? scalar.Value
            : null;
    }

    public void SetScalar(string key, string value)
    {
        SetNode(key, new YamlScalarNode(value));
    }

    public void SetSequence(string key, IEnumerable<string> values)
    {
        SetNode(
            key,
            new YamlSequenceNode(values.Select(value => new YamlScalarNode(value))));
    }

    public void Remove(string key)
    {
        YamlNode? existingKey = Metadata.Children.Keys.FirstOrDefault(
            node => node is YamlScalarNode scalar &&
                string.Equals(scalar.Value, key, StringComparison.Ordinal));
        if (existingKey is not null)
        {
            Metadata.Children.Remove(existingKey);
        }
    }

    public void MergeExtensions(JsonElement metadata)
    {
        if (metadata.ValueKind is JsonValueKind.Undefined or JsonValueKind.Null)
        {
            return;
        }

        if (metadata.ValueKind != JsonValueKind.Object)
        {
            throw new OkfWikiException("metadata must be a JSON object.");
        }

        foreach (JsonProperty property in metadata.EnumerateObject())
        {
            if (KnownFieldOrder.Contains(property.Name, StringComparer.Ordinal))
            {
                throw new OkfWikiException(
                    $"metadata cannot redefine the known OKF field '{property.Name}'.");
            }

            SetNode(property.Name, FromJson(property.Value));
        }
    }

    public string GetSemanticFingerprint()
    {
        YamlMappingNode clone = CloneMapping(Metadata);
        RemoveNode(clone, "timestamp");
        return SerializeYaml(OrderMetadata(clone)) + "\n---BODY---\n" + NormalizeBody(Body);
    }

    public string Render()
    {
        string yaml = SerializeYaml(OrderMetadata(Metadata)).TrimEnd();
        string body = NormalizeBody(Body);
        StringBuilder builder = new();
        builder.AppendLine("---");
        builder.AppendLine(yaml);
        builder.AppendLine("---");
        if (body.Length > 0)
        {
            builder.AppendLine();
            builder.Append(body);
            if (!body.EndsWith('\n'))
            {
                builder.AppendLine();
            }
        }

        return NormalizeNewLines(builder.ToString());
    }

    private static YamlMappingNode CloneMapping(YamlMappingNode mapping)
    {
        string yaml = SerializeYaml(mapping);
        YamlStream stream = new();
        stream.Load(new StringReader(yaml));
        return (YamlMappingNode)stream.Documents[0].RootNode;
    }

    private static YamlMappingNode OrderMetadata(YamlMappingNode source)
    {
        YamlMappingNode ordered = [];
        foreach (string field in KnownFieldOrder)
        {
            if (TryGetNode(source, field, out YamlNode? value))
            {
                ordered.Add(field, value);
            }
        }

        foreach ((YamlNode key, YamlNode value) in source.Children)
        {
            if (key is not YamlScalarNode scalar ||
                !KnownFieldOrder.Contains(scalar.Value, StringComparer.Ordinal))
            {
                ordered.Add(key, value);
            }
        }

        return ordered;
    }

    private static string SerializeYaml(YamlMappingNode mapping)
    {
        YamlStream stream = new(new YamlDocument(mapping));
        StringWriter writer = new();
        stream.Save(writer, assignAnchors: false);
        string yaml = NormalizeNewLines(writer.ToString());
        if (yaml.StartsWith("---\n", StringComparison.Ordinal))
        {
            yaml = yaml[4..];
        }

        if (yaml.EndsWith("...\n", StringComparison.Ordinal))
        {
            yaml = yaml[..^4];
        }

        return yaml.TrimEnd('\n');
    }

    private bool TryGetNode(
        string key,
        [NotNullWhen(true)] out YamlNode? value)
    {
        return TryGetNode(Metadata, key, out value);
    }

    private static bool TryGetNode(
        YamlMappingNode metadata,
        string key,
        [NotNullWhen(true)] out YamlNode? value)
    {
        foreach ((YamlNode childKey, YamlNode childValue) in metadata.Children)
        {
            if (childKey is YamlScalarNode scalar &&
                string.Equals(scalar.Value, key, StringComparison.Ordinal))
            {
                value = childValue;
                return true;
            }
        }

        value = null;
        return false;
    }

    private void SetNode(string key, YamlNode value)
    {
        YamlNode? existingKey = Metadata.Children.Keys.FirstOrDefault(
            node => node is YamlScalarNode scalar &&
                string.Equals(scalar.Value, key, StringComparison.Ordinal));
        if (existingKey is null)
        {
            Metadata.Add(key, value);
        }
        else
        {
            Metadata.Children[existingKey] = value;
        }
    }

    private static void RemoveNode(YamlMappingNode mapping, string key)
    {
        YamlNode? existingKey = mapping.Children.Keys.FirstOrDefault(
            node => node is YamlScalarNode scalar &&
                string.Equals(scalar.Value, key, StringComparison.Ordinal));
        if (existingKey is not null)
        {
            mapping.Children.Remove(existingKey);
        }
    }

    private static YamlNode FromJson(JsonElement value)
    {
        return value.ValueKind switch
        {
            JsonValueKind.Object => new YamlMappingNode(
                value.EnumerateObject().Select(
                    property => new KeyValuePair<YamlNode, YamlNode>(
                        new YamlScalarNode(property.Name),
                        FromJson(property.Value)))),
            JsonValueKind.Array => new YamlSequenceNode(
                value.EnumerateArray().Select(FromJson)),
            JsonValueKind.String => new YamlScalarNode(value.GetString()),
            JsonValueKind.Number => new YamlScalarNode(value.GetRawText()),
            JsonValueKind.True => new YamlScalarNode("true"),
            JsonValueKind.False => new YamlScalarNode("false"),
            JsonValueKind.Null => new YamlScalarNode(null),
            _ => throw new OkfWikiException(
                $"Unsupported metadata JSON value kind '{value.ValueKind}'.")
        };
    }

    private static string NormalizeBody(string body)
    {
        return NormalizeNewLines(body).Trim('\n');
    }

    private static string NormalizeNewLines(string value)
    {
        return value.Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n');
    }
}
