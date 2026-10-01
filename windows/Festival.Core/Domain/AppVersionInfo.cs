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
}
