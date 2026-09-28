using System.Text.Json;

namespace Festival.Core.Data;

#region Store abstraction
/// <summary>Loads and saves <see cref="AppSettings"/>.</summary>
public interface ISettingsStore
{
    /// <summary>Loads settings, falling back to defaults for missing or corrupt data.</summary>
    /// <returns>Sanitized settings.</returns>
    AppSettings Load();

    /// <summary>Persists settings.</summary>
    /// <param name="settings">Settings to write.</param>
    void Save(AppSettings settings);

    /// <summary>Whether the last <see cref="Load"/> discarded corrupt data.</summary>
    bool RecoveredFromCorruption { get; }
}

/// <summary>Non-persistent store for tests and previews.</summary>
public sealed class InMemorySettingsStore(AppSettings? initial = null) : ISettingsStore
{
    /// <summary>Last saved value.</summary>
    public AppSettings Current { get; private set; } = initial ?? new AppSettings();

    /// <summary>Number of saves.</summary>
    public int SaveCount { get; private set; }

    /// <inheritdoc />
    public bool RecoveredFromCorruption => false;

    /// <inheritdoc />
    public AppSettings Load() => Current.Sanitized();

    /// <inheritdoc />
    public void Save(AppSettings settings)
    {
        Current = settings;
        SaveCount++;
    }
}
#endregion

#region JSON file store
/// <summary>
/// JSON settings under <c>%LOCALAPPDATA%\FestivalScoreTracker\settings.json</c>, written atomically
/// (temp file + replace) so a crash never leaves half a file.
/// </summary>
/// <param name="path">Settings file path.</param>
public sealed class JsonFileSettingsStore(string path) : ISettingsStore
{
    /// <summary>Default per-user settings path.</summary>
    public static string DefaultPath { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FestivalScoreTracker", "settings.json");

    /// <summary>File path.</summary>
    public string FilePath { get; } = path;

    /// <inheritdoc />
    public bool RecoveredFromCorruption { get; private set; }

    /// <inheritdoc />
    public AppSettings Load()
    {
        RecoveredFromCorruption = false;
        if (!File.Exists(FilePath)) return new AppSettings();
        try
        {
            var bytes = File.ReadAllBytes(FilePath);
            if (bytes.Length > 256_000) throw new JsonException("Settings file too large.");
            return (JsonSerializer.Deserialize(bytes, FestivalJsonContext.Default.AppSettings) ?? new AppSettings()).Sanitized();
        }
        catch (Exception error) when (error is JsonException or IOException or NotSupportedException or UnauthorizedAccessException)
        {
            RecoveredFromCorruption = true;
            return new AppSettings();
        }
    }

    /// <inheritdoc />
    public void Save(AppSettings settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temp = FilePath + ".tmp";
        File.WriteAllBytes(temp, JsonSerializer.SerializeToUtf8Bytes(settings.Sanitized(), FestivalJsonContext.Default.AppSettings));
        File.Move(temp, FilePath, overwrite: true);
    }
}
#endregion
