using System.Text.Json;

namespace Festival.Core.Data;

#region What's New seen store
/// <summary>
/// The last dismissed What's New (web <c>localStorage['fst:changelog']</c> <c>{ version, hash }</c>). A missing,
/// oversized or malformed blob reads as "never dismissed", so the dialog shows again, as on the web.
/// </summary>
/// <param name="blob">Backing blob (<c>whats-new.json</c> in the app, memory in tests).</param>
public sealed class ChangelogSeenStore(IBlobStore blob)
{
    /// <summary>Largest accepted blob.</summary>
    public const int MaxBytes = 1024;

    /// <summary>Default file.</summary>
    public static string DefaultPath => AppStateFiles.WhatsNew.DefaultPath;

    /// <summary>Stored dismissal hash, or <see langword="null"/> when absent or invalid.</summary>
    /// <returns>Hash.</returns>
    public string? SeenHash()
    {
        if (blob.Read() is not { Length: > 0 and <= MaxBytes } bytes) return null;
        try
        {
            using var document = JsonDocument.Parse(bytes);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("hash", out var hash) || hash.ValueKind != JsonValueKind.String ||
                !root.TryGetProperty("version", out var version) || version.ValueKind != JsonValueKind.String) return null;
            var text = hash.GetString()!;
            return text.Length is > 0 and <= 32 && version.GetString()!.Length <= 64 ? text : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    /// <summary>Records a dismissal.</summary>
    /// <param name="version">App version shown in the title.</param>
    /// <param name="hash">Changelog hash that was shown.</param>
    public void MarkSeen(string version, string hash)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            writer.WriteString("version", version.Length > 64 ? version[..64] : version);
            writer.WriteString("hash", hash);
            writer.WriteEndObject();
        }
        blob.Write(stream.ToArray());
    }

    /// <summary>Forgets the dismissal (<c>--whats-new fresh</c>).</summary>
    public void Reset() => blob.Write(null);
}
#endregion
