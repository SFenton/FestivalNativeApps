namespace Festival.Core.Data;

#region Blob stores
/// <summary>One small persisted byte blob (first-run seen-state, notification seen IDs).</summary>
public interface IBlobStore
{
    /// <summary>Reads the blob.</summary>
    /// <returns>Bytes, or <see langword="null"/> when absent, unreadable or oversized.</returns>
    byte[]? Read();

    /// <summary>Replaces the blob; <see langword="null"/> deletes it.</summary>
    /// <param name="bytes">New contents.</param>
    void Write(byte[]? bytes);
}

/// <summary>Process-only blob for tests and previews.</summary>
public sealed class MemoryBlobStore : IBlobStore
{
    /// <summary>Current contents.</summary>
    public byte[]? Bytes { get; set; }

    /// <summary>Number of writes.</summary>
    public int WriteCount { get; private set; }

    /// <inheritdoc />
    public byte[]? Read() => Bytes;

    /// <inheritdoc />
    public void Write(byte[]? bytes)
    {
        Bytes = bytes;
        WriteCount++;
    }
}

/// <summary>A file under <c>%LOCALAPPDATA%\FestivalScoreTracker</c>, written atomically (temp file + replace).</summary>
/// <param name="path">File path.</param>
/// <param name="maxBytes">Largest accepted file; bigger files read as absent.</param>
public sealed class FileBlobStore(string path, int maxBytes = 256 * 1024) : IBlobStore
{
    /// <summary>Per-user app data folder shared with <see cref="JsonFileSettingsStore"/>.</summary>
    public static string AppDataFolder { get; } = Path.GetDirectoryName(JsonFileSettingsStore.DefaultPath)!;

    /// <summary>File path.</summary>
    public string FilePath { get; } = path;

    /// <inheritdoc />
    public byte[]? Read()
    {
        try
        {
            var info = new FileInfo(FilePath);
            if (!info.Exists || info.Length > maxBytes) return null;
            return File.ReadAllBytes(FilePath);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return null;
        }
    }

    /// <inheritdoc />
    public void Write(byte[]? bytes)
    {
        try
        {
            if (bytes is null)
            {
                File.Delete(FilePath);
                return;
            }
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            var temp = FilePath + ".tmp";
            File.WriteAllBytes(temp, bytes);
            File.Move(temp, FilePath, overwrite: true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            // Seen-state is best effort: a failed write only means a slide or notification may show again.
        }
    }
}
#endregion
