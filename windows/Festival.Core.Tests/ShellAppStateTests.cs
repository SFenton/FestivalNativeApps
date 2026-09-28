using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

#region App data folder
public sealed class AppDataPathsTests
{
    private const string Local = @"C:\Users\u\AppData\Local";

    [Fact]
    public void Release_IgnoresEnvironmentAndBuildLocation()
    {
        var folder = AppDataPaths.Resolve(false, _ => @"D:\override", @"C:\lanes\win-shell\bin", Local);
        Assert.Equal(Path.Combine(Local, "FestivalScoreTracker"), folder);
        Assert.Equal(folder, AppDataPaths.ReleaseFolder(Local));
    }

    [Fact]
    public void Debug_ExplicitVariableWins()
    {
        string? Env(string name) => name == AppDataPaths.DataDirVariable ? @"D:\fst\lane-a" : null;
        Assert.Equal(@"D:\fst\lane-a", AppDataPaths.Resolve(true, Env, @"C:\x", Local));
        Assert.Equal(Path.GetFullPath("relative-dir"), AppDataPaths.Resolve(true, n => n == AppDataPaths.DataDirVariable ? "relative-dir" : null, @"C:\x", Local));
    }

    [Fact]
    public void Debug_DerivesFolderPerWorktree()
    {
        var root = Path.Combine(Path.GetTempPath(), "fst-paths-" + Guid.NewGuid().ToString("N"));
        try
        {
            var laneA = Path.Combine(root, "lanes", "win-shell");
            var laneB = Path.Combine(root, "other", "win-shell");
            var binA = Path.Combine(laneA, "windows", "bin", "Debug");
            var binB = Path.Combine(laneB, "windows", "bin", "Debug");
            Directory.CreateDirectory(Path.Combine(laneA, ".git"));
            Directory.CreateDirectory(binA);
            Directory.CreateDirectory(binB);
            File.WriteAllText(Path.Combine(laneB, ".git"), "gitdir: elsewhere");

            var a = AppDataPaths.Resolve(true, _ => null, binA, Local);
            var b = AppDataPaths.Resolve(true, _ => "", binB, Local);
            Assert.StartsWith(Path.Combine(Local, "FestivalScoreTracker.Debug", "win-shell-"), a);
            Assert.StartsWith(Path.Combine(Local, "FestivalScoreTracker.Debug", "win-shell-"), b);
            Assert.NotEqual(a, b);
            // Stable for every folder in the same worktree, and case-insensitive like the file system.
            Assert.Equal(a, AppDataPaths.Resolve(true, _ => null, laneA + Path.DirectorySeparatorChar, Local));
            Assert.Equal(AppDataPaths.DebugKey(binA), AppDataPaths.DebugKey(binA.ToUpperInvariant()), ignoreCase: true);
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void DebugKey_OutsideWorktreeSanitizesAndBoundsTheName()
    {
        var root = Path.Combine(Path.GetTempPath(), "fst-nogit-" + Guid.NewGuid().ToString("N"));
        var odd = Path.Combine(root, "my app (copy)");
        var longName = Path.Combine(root, new string('x', 60));
        try
        {
            Directory.CreateDirectory(odd);
            Directory.CreateDirectory(longName);
            var key = AppDataPaths.DebugKey(odd);
            Assert.Matches("^my_app__copy_-[0-9a-f]{8}$", key);
            Assert.Matches("^x{40}-[0-9a-f]{8}$", AppDataPaths.DebugKey(longName));
            Assert.Matches("^app-[0-9a-f]{8}$", AppDataPaths.DebugKey(Path.GetPathRoot(root)!));
        }
        finally
        {
            Directory.Delete(root, true);
        }
    }

    [Fact]
    public void DefaultPaths_FollowTheConfiguredFolder()
    {
        // Configure is process-wide; restore the default so parallel tests keep seeing it.
        var original = AppDataPaths.Folder;
        Assert.Equal(original, FileBlobStore.AppDataFolder);
        Assert.Equal(Path.Combine(original, "settings.json"), JsonFileSettingsStore.DefaultPath);
        Assert.Equal(Path.Combine(original, "suggestions-filter.json"), JsonFileSuggestionFilterStore.DefaultPath);
        Assert.Equal(Path.Combine(original, "first-run.json"), FirstRunSeenStore.DefaultPath);
        Assert.Equal(Path.Combine(original, "notifications-seen.json"), NotificationSeenStore.DefaultPath);
        Assert.Equal(Path.Combine(original, "diagnostics.log"), AppStateFiles.Diagnostics.DefaultPath);
        AppDataPaths.Configure(original);
        Assert.Equal(Path.GetFullPath(original), AppDataPaths.Folder);
    }
}
#endregion

#region App state files
public sealed class AppStateFilesTests
{
    [Fact]
    public void Registry_ListsEveryFileOnce_AndResetOwnsOnlyFeatureState()
    {
        Assert.Equal(AppStateFiles.All.Count, AppStateFiles.All.Select(f => f.FileName).Distinct().Count());
        Assert.Equal(["suggestions-filter.json"], AppStateFiles.DeletedByReset.Select(f => f.FileName));
        Assert.Equal(AppSection.Suggestions, AppStateFiles.SuggestionsFilter.Owner);
        Assert.All([AppStateFiles.Settings, AppStateFiles.FirstRun, AppStateFiles.NotificationsSeen, AppStateFiles.Diagnostics],
            f => Assert.Equal(AppStateReset.Keep, f.Reset));
    }

    [Fact]
    public void DeleteForReset_RemovesOwnedFilesAndTempCopies_KeepsTheRest()
    {
        var folder = Path.Combine(Path.GetTempPath(), "fst-state-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            foreach (var file in AppStateFiles.All) File.WriteAllText(Path.Combine(folder, file.FileName), "x");
            File.WriteAllText(Path.Combine(folder, "suggestions-filter.json.tmp"), "x");

            Assert.Equal([AppStateFiles.SuggestionsFilter], AppStateFiles.DeleteForReset(folder));
            Assert.False(File.Exists(Path.Combine(folder, "suggestions-filter.json")));
            Assert.False(File.Exists(Path.Combine(folder, "suggestions-filter.json.tmp")));
            Assert.True(File.Exists(Path.Combine(folder, "settings.json")));
            Assert.True(File.Exists(Path.Combine(folder, "first-run.json")));

            Assert.Empty(AppStateFiles.DeleteForReset(folder));
            Assert.Empty(AppStateFiles.DeleteForReset(Path.Combine(folder, "missing")));
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void DeleteForReset_LockedFileIsBestEffort()
    {
        var folder = Path.Combine(Path.GetTempPath(), "fst-locked-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, "suggestions-filter.json");
        try
        {
            File.WriteAllText(path, "x");
            using (new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None))
            {
                Assert.Empty(AppStateFiles.DeleteForReset(folder));
            }
            Assert.True(File.Exists(path));
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }

    [Fact]
    public void SettingsReset_DeletesSuggestionsFilter_AndNotifiesOwners()
    {
        var folder = Path.Combine(Path.GetTempPath(), "fst-reset-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            var filterPath = Path.Combine(folder, "suggestions-filter.json");
            File.WriteAllText(filterPath, "{}");
            var store = new InMemorySettingsStore(new AppSettings { HideShop = true });
            var session = new FestivalSession(new FakeService().Client(), store) { AppStateFolder = folder };
            IReadOnlyList<AppStateFile>? notified = null;
            session.FeatureStateReset += (_, files) => notified = files;

            new SettingsViewModel(session, "1.0").ResetAppSettingsCommand.Execute(null);

            Assert.False(store.Current.HideShop);
            Assert.False(File.Exists(filterPath));
            Assert.Equal([AppSection.Suggestions], notified!.Select(f => f.Owner));

            // No folder (tests, previews): nothing is deleted, owners are still told.
            File.WriteAllText(filterPath, "{}");
            var detached = new FestivalSession(new FakeService().Client(), new InMemorySettingsStore());
            var raised = 0;
            detached.FeatureStateReset += (_, _) => raised++;
            detached.ResetFeatureState();
            Assert.Equal(1, raised);
            Assert.True(File.Exists(filterPath));
        }
        finally
        {
            Directory.Delete(folder, true);
        }
    }
}
#endregion
