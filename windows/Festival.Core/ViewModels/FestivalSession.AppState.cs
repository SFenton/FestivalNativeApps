namespace Festival.Core.ViewModels;

#region Feature state reset
/// <summary>Settings Reset for feature-owned state files (<see cref="AppStateFiles"/>).</summary>
public sealed partial class FestivalSession
{
    /// <summary>
    /// Folder holding feature state files; <see langword="null"/> (tests, previews) deletes nothing and only raises
    /// <see cref="FeatureStateReset"/>.
    /// </summary>
    public string? AppStateFolder { get; init; }

    /// <summary>Raised after <see cref="ResetFeatureState"/> with the registered files Reset owns.</summary>
    public event EventHandler<IReadOnlyList<AppStateFile>>? FeatureStateReset;

    /// <summary>Deletes Reset-owned feature files and tells the shell to drop pages that cached them.</summary>
    public void ResetFeatureState()
    {
        if (AppStateFolder is { } folder) AppStateFiles.DeleteForReset(folder);
        FeatureStateReset?.Invoke(this, AppStateFiles.DeletedByReset);
    }
}
#endregion
