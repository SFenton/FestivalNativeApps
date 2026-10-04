using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Licenses
/// <summary>Licenses page (<c>/settings/licenses</c>): this app's own third-party NuGet packages only (operator rule: no bundled-asset entries); no network.</summary>
public sealed partial class LicensesViewModel : ObservableObject
{
    /// <summary>Creates the page model.</summary>
    /// <param name="manifest">Parsed manifest (<see cref="LicenseManifest.Parse"/>).</param>
    public LicensesViewModel(LicenseManifest manifest)
    {
        Packages = manifest.Packages.OrderBy(p => p.Name, StringComparer.OrdinalIgnoreCase)
            .Select(p => new LicenseRowViewModel(p, manifest.Texts[p.TextId])).ToList();
    }

    /// <summary>Third-party packages, by name.</summary>
    public List<LicenseRowViewModel> Packages { get; }

    /// <summary>Whether no third-party package is listed (a missing or empty manifest).</summary>
    public bool HasNoPackages => Packages.Count == 0;

    /// <summary>Summary under the title.</summary>
    public string Summary => HasNoPackages
        ? "No third-party packages are listed for this build."
        : $"{Packages.Count} open source and Microsoft packages ship with Festival Score Tracker for Windows.";
}

/// <summary>One license row; activating it opens the full text.</summary>
/// <param name="package">Package.</param>
/// <param name="text">Full license text.</param>
public sealed class LicenseRowViewModel(LicensePackage package, string text)
{
    /// <summary>Package.</summary>
    public LicensePackage Package { get; } = package;

    /// <summary>Display name.</summary>
    public string Name => Package.Name;

    /// <summary>"NuGet · 1.2.3".</summary>
    public string Subtitle => $"{Package.Ecosystem} · {Package.Version}";

    /// <summary>License badge.</summary>
    public string License => Package.License;

    /// <summary>Full license text.</summary>
    public string Text { get; } = text;

    /// <summary>Validated HTTPS project URL, if any.</summary>
    public Uri? Url => Uri.TryCreate(Package.Url, UriKind.Absolute, out var url) && url.Scheme == Uri.UriSchemeHttps ? url : null;

    /// <summary>Whether a project link is shown.</summary>
    public bool HasUrl => Url is not null;

    /// <summary>Automation ID.</summary>
    public string AutomationId => "fst.licenses.row." + Package.Id.ToLowerInvariant();

    /// <summary>Narrator name.</summary>
    public string AccessibleName => $"{Name}, {Subtitle}, {License}";

    /// <summary>Detail dialog title: "Name · License".</summary>
    public string DetailTitle => $"{Name} · {License}";

    /// <summary>Detail dialog caption: "NuGet · 1.2.3 · License".</summary>
    public string DetailCaption => $"{Subtitle} · {License}";

    /// <summary>Visible project link text (host and path, no scheme or trailing slash), or empty without a link.</summary>
    public string LinkText => Url is { } url ? url.Host + url.AbsolutePath.TrimEnd('/') : "";

    /// <summary>Narrator name of the project link.</summary>
    public string LinkAccessibleName => $"Project page for {Name}";

    /// <summary>Narrator name of the license text scroller (a tab stop, so arrow and Page keys scroll it).</summary>
    public string TextAccessibleName => $"{Name} license text";
}
#endregion
