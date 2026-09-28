namespace Festival.Core.Data;

#region Store abstraction
/// <summary>Loads and saves the Suggestions filter, separately from <see cref="AppSettings"/>.</summary>
public interface ISuggestionFilterStore
{
    /// <summary>Loads the saved filter; missing or corrupt data yields defaults.</summary>
    /// <returns>Filter.</returns>
    SuggestionFilterSettings Load();

    /// <summary>Persists the filter (an untouched filter removes the saved copy).</summary>
    /// <param name="filter">Filter.</param>
    void Save(SuggestionFilterSettings filter);
}

/// <summary>Non-persistent store for tests and previews.</summary>
/// <param name="initial">Starting value.</param>
public sealed class InMemorySuggestionFilterStore(SuggestionFilterSettings? initial = null) : ISuggestionFilterStore
{
    /// <summary>Last saved value.</summary>
    public SuggestionFilterSettings Current { get; private set; } = initial ?? SuggestionFilterSettings.Default;

    /// <summary>Number of saves.</summary>
    public int SaveCount { get; private set; }

    /// <inheritdoc />
    public SuggestionFilterSettings Load() => Current;

    /// <inheritdoc />
    public void Save(SuggestionFilterSettings filter)
    {
        Current = filter;
        SaveCount++;
    }
}
#endregion

#region JSON file store
/// <summary>
/// The filter as <c>%LOCALAPPDATA%\FestivalScoreTracker\suggestions-filter.json</c>, written atomically; an
/// untouched filter deletes the file.
/// </summary>
/// <param name="path">File path.</param>
public sealed class JsonFileSuggestionFilterStore(string path) : ISuggestionFilterStore
{
    /// <summary>Default per-user path, beside the settings file.</summary>
    public static string DefaultPath { get; } = Path.Combine(
        Path.GetDirectoryName(JsonFileSettingsStore.DefaultPath)!, "suggestions-filter.json");

    /// <summary>File path.</summary>
    public string FilePath { get; } = path;

    /// <inheritdoc />
    public SuggestionFilterSettings Load()
    {
        try
        {
            if (!File.Exists(FilePath) || new FileInfo(FilePath).Length > SuggestionFilterSettings.MaxBytes)
                return SuggestionFilterSettings.Default;
            return SuggestionFilterSettings.Decode(File.ReadAllBytes(FilePath));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return SuggestionFilterSettings.Default;
        }
    }

    /// <inheritdoc />
    public void Save(SuggestionFilterSettings filter)
    {
        var bytes = filter.Encode();
        if (bytes.Length == 0)
        {
            File.Delete(FilePath);
            return;
        }
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var temp = FilePath + ".tmp";
        File.WriteAllBytes(temp, bytes);
        File.Move(temp, FilePath, overwrite: true);
    }
}
#endregion
