using System.Reflection;

namespace Festival.Core.Domain;

/// <summary>
/// The app version shown to users (Settings, What's New title, User-Agent). Store builds stamp the release
/// version <c>YYMM.DD.NN</c> into <c>InformationalVersion</c> (tools/windows/package_msix.ps1 <c>-DisplayVersion</c>),
/// because the numeric assembly/MSIX versions drop leading zeros and encode the day and counter together.
/// </summary>
public static class AppVersionInfo
{
    #region Display

    /// <summary>Returns the user-facing version for <paramref name="assembly"/>.</summary>
    /// <param name="assembly">The app assembly.</param>
    /// <returns>The stamped release version, otherwise the three-part assembly version, otherwise empty.</returns>
    public static string Display(Assembly assembly) => Display(
        assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion,
        assembly.GetName().Version);

    /// <summary>Chooses the user-facing version from the informational and numeric assembly versions.</summary>
    /// <param name="informationalVersion">The <c>InformationalVersion</c>; any <c>+metadata</c> suffix is dropped.</param>
    /// <param name="assemblyVersion">The numeric assembly version, used when no informational version is set.</param>
    /// <returns>The version text, or an empty string when neither is known.</returns>
    public static string Display(string? informationalVersion, Version? assemblyVersion)
    {
        var info = (informationalVersion ?? "").Split('+')[0].Trim();
        return info.Length > 0 ? info : assemblyVersion?.ToString(3) ?? "";
    }

    #endregion

    #region Settings

    /// <summary>Assembly metadata key holding the build's git commit (windows/Directory.Build.targets).</summary>
    public const string GitShaKey = "FSTGitSHA";

    /// <summary>Number of SHA characters shown (git's conventional short SHA).</summary>
    public const int ShortShaLength = 7;

    /// <summary>Separator between the version and the short commit.</summary>
    public const string CommitSeparator = " · ";

    /// <summary>Returns the Settings → App Version text for <paramref name="assembly"/>: <c>2610.01.02 · 42edc57</c>.</summary>
    /// <param name="assembly">The app assembly.</param>
    /// <returns>The <see cref="Display(Assembly)"/> version plus the stamped short commit, when known.</returns>
    public static string SettingsText(Assembly assembly) => SettingsText(
        Display(assembly),
        assembly.GetCustomAttributes<AssemblyMetadataAttribute>().FirstOrDefault(a => a.Key == GitShaKey)?.Value);

    /// <summary>Appends the short commit to the display version (iPhone parity, issue #3), so every build is identifiable.</summary>
    /// <param name="display">The user-facing version from <see cref="Display(string?, Version?)"/>.</param>
    /// <param name="gitSha">The stamped commit, if any.</param>
    /// <returns><c>"&lt;version&gt; · &lt;sha7&gt;"</c>, or the version alone when the commit is unknown.</returns>
    public static string SettingsText(string display, string? gitSha)
    {
        var sha = ShortCommit(gitSha);
        if (sha is null) return display;
        return display.Length > 0 ? display + CommitSeparator + sha : sha;
    }

    /// <summary>Returns the first seven characters of a stamped commit SHA.</summary>
    /// <param name="raw">The stamped value, if any.</param>
    /// <returns>The lower-case short SHA, or null when absent, shorter than seven characters or not hexadecimal.</returns>
    public static string? ShortCommit(string? raw)
    {
        var value = (raw ?? "").Trim();
        if (value.Length < ShortShaLength || !value.All(Uri.IsHexDigit)) return null;
        return value[..ShortShaLength].ToLowerInvariant();
    }

    #endregion
}
