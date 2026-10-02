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

    #region Build commit

    /// <summary><c>AssemblyMetadata</c> key holding the build commit (stamped by <c>Festival.App.csproj</c>).</summary>
    public const string GitShaMetadataKey = "FstGitSha";

    /// <summary>Number of SHA characters shown (git's conventional short SHA).</summary>
    public const int ShortShaLength = 7;

    /// <summary>Separator between the version and the short commit.</summary>
    public const string CommitSeparator = " · ";

    /// <summary>Settings → App Version text for <paramref name="assembly"/>: the version plus its short build commit.</summary>
    /// <param name="assembly">The app assembly.</param>
    /// <returns><see cref="Display(Assembly)"/>, plus <c>" · &lt;sha7&gt;"</c> when a commit is stamped.</returns>
    public static string SettingsText(Assembly assembly) => WithCommit(
        Display(assembly),
        assembly.GetCustomAttributes<AssemblyMetadataAttribute>().FirstOrDefault(a => a.Key == GitShaMetadataKey)?.Value);

    /// <summary>Appends the short build commit to a version (iOS <c>AppBuildInfo.versionText</c> parity).</summary>
    /// <param name="version">The user-facing version; returned unchanged when empty.</param>
    /// <param name="gitSha">The stamped commit, if any.</param>
    /// <returns><c>"&lt;version&gt; · &lt;sha7&gt;"</c>, or <paramref name="version"/> when there is no commit.</returns>
    public static string WithCommit(string version, string? gitSha) =>
        version.Length > 0 && ShortCommit(gitSha) is { } sha ? version + CommitSeparator + sha : version;

    /// <summary>The first seven characters of a stamped commit SHA.</summary>
    /// <param name="raw">The stamped value, if any.</param>
    /// <returns>The lower-case short SHA, or <see langword="null"/> when the value is absent, empty, <c>dev</c>
    /// or not hexadecimal (e.g. an unexpanded MSBuild property).</returns>
    public static string? ShortCommit(string? raw)
    {
        var value = (raw ?? "").Trim();
        if (value.Length == 0 || value.Equals("dev", StringComparison.OrdinalIgnoreCase) || !value.All(char.IsAsciiHexDigit))
        {
            return null;
        }
        return value[..Math.Min(ShortShaLength, value.Length)].ToLowerInvariant();
    }

    #endregion
}
