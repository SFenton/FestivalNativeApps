namespace Festival.Core.Domain;

#region Settings detail
/// <summary>
/// A Settings entry that opens its options in the trailing pane of the wide list/detail layout (issue #371). In one
/// column every entry stays inline, as before.
/// </summary>
public enum SettingsDetail
{
    /// <summary>Nothing selected: the trailing pane shows the Settings placeholder.</summary>
    None,
    /// <summary>App Settings › Song Row Visual Order (drag list; only while Visual Order is on).</summary>
    SongRowOrder,
    /// <summary>App Settings › CHOpt Path Default View (Image/Text).</summary>
    PathDefaultView,
    /// <summary>App Settings › CHOpt Text Path Column Order (drag list).</summary>
    PathColumnOrder,
    /// <summary>App Settings › Maximum Score Leeway (slider; only while Filter Invalid Scores is on).</summary>
    Leeway,
    /// <summary>Item Shop section.</summary>
    ItemShop,
    /// <summary>Show Instruments section.</summary>
    Instruments,
    /// <summary>Show Instrument Metadata section.</summary>
    Metadata,
    /// <summary>Accessibility section.</summary>
    Accessibility,
    /// <summary>Festival Score Tracker Version section.</summary>
    Version,
    /// <summary>Service Info section.</summary>
    ServiceInfo,
    /// <summary>First Run Guides section.</summary>
    FirstRun,
    /// <summary>Licenses page.</summary>
    Licenses,
    /// <summary>Privacy Policy text.</summary>
    PrivacyPolicy,
}

/// <summary>A detail entry's list row and trailing-pane header.</summary>
/// <param name="Detail">Entry.</param>
/// <param name="Title">Row title and pane heading (the one-column section or setting title).</param>
/// <param name="Description">Row and pane description; <see langword="null"/> when the page supplies a live one (metadata) or the row shows only its value (leeway).</param>
/// <param name="AutomationId">List row automation ID.</param>
public sealed record SettingsDetailItem(SettingsDetail Detail, string Title, string? Description, string AutomationId);

/// <summary>
/// Settings list/detail rules (issue #371, owner-approved): from <see cref="SplitWidth"/> the page shows the settings list
/// beside a trailing pane. Plain toggles stay in the list; multi-option settings, drag lists, the leeway slider and the
/// owner-named sections are chevron rows whose options open in the pane. With nothing selected the pane shows a centred
/// placeholder. Narrower pages keep the one-column page unchanged.
/// </summary>
public static class SettingsDetails
{
    /// <summary>Page width from which Settings splits (the shared Windows list/detail width: Songs, All Rivals, Rankings).</summary>
    public const double SplitWidth = 1100;

    /// <summary>List column width in the split layout (All Rivals' list width).</summary>
    public const double ListWidth = 520;

    /// <summary>Placeholder heading.</summary>
    public const string PlaceholderTitle = "Settings";

    /// <summary>Placeholder message (owner copy, #371).</summary>
    public const string PlaceholderMessage = "Select a setting to see more options here";

    /// <summary>Every detail entry in page order.</summary>
    public static IReadOnlyList<SettingsDetailItem> Items { get; } =
    [
        new(SettingsDetail.SongRowOrder, "Song Row Visual Order",
            "When filtering to a single instrument in the song list, extra metadata is displayed. Choose the order it appears in on the bottom row.",
            "fst.settings.detail-row.song-row-order"),
        new(SettingsDetail.PathDefaultView, "CHOpt Path Default View",
            "Choose whether CHOpt paths open as an image or text table by default.", "fst.settings.detail-row.path-default-view"),
        new(SettingsDetail.PathColumnOrder, "CHOpt Text Path Column Order",
            "Choose the order columns appear in the CHOpt text path view.", "fst.settings.detail-row.path-column-order"),
        new(SettingsDetail.Leeway, "Maximum Score Leeway",
            "How far above the CHOpt maximum a score may be and still count as valid.", "fst.settings.detail-row.leeway"),
        new(SettingsDetail.ItemShop, "Item Shop", "Control how Item Shop availability is displayed.", "fst.settings.detail-row.item-shop"),
        new(SettingsDetail.Instruments, "Show Instruments", "Choose which instruments to display throughout the app.",
            "fst.settings.detail-row.show-instruments"),
        new(SettingsDetail.Metadata, "Show Instrument Metadata", null, "fst.settings.detail-row.show-metadata"),
        new(SettingsDetail.Accessibility, "Accessibility",
            "Off follows Windows; On adds an app override. Narrator and text size are managed in Windows Settings.",
            "fst.settings.detail-row.accessibility"),
        new(SettingsDetail.Version, "Festival Score Tracker Version", "Festival Score Tracker information to help with debugging.",
            "fst.settings.detail-row.version"),
        new(SettingsDetail.ServiceInfo, "Service Info",
            "Live leaderboard update status, exact phase progress when available, and publication timing.",
            "fst.settings.detail-row.service-info"),
        new(SettingsDetail.FirstRun, "First Run Guides", "Re-visit the first run experience for each page.", "fst.settings.detail-row.first-run"),
        new(SettingsDetail.Licenses, "Licenses", "Open source package license details.", "fst.settings.detail-row.licenses"),
        new(SettingsDetail.PrivacyPolicy, "Privacy Policy", "How Festival Score Tracker handles your information.",
            "fst.settings.detail-row.privacy-policy"),
    ];

    /// <summary>Whether the page is wide enough for the list/detail layout.</summary>
    /// <param name="pageWidth">Settings page width in epx.</param>
    /// <returns><see langword="true"/> at <see cref="SplitWidth"/> and wider.</returns>
    public static bool UsesSplit(double pageWidth) => pageWidth >= SplitWidth;

    /// <summary>An entry's row and header.</summary>
    /// <param name="detail">Entry other than <see cref="SettingsDetail.None"/>.</param>
    /// <returns>Item.</returns>
    public static SettingsDetailItem Item(SettingsDetail detail) =>
        Items.FirstOrDefault(i => i.Detail == detail) ?? throw new ArgumentOutOfRangeException(nameof(detail), detail, null);

    /// <summary>
    /// Whether an entry's row is listed: Song Row Visual Order only while Visual Order is on and Maximum Score Leeway
    /// only while Filter Invalid Scores is on (one column shows them under those switches only then, as on the web).
    /// </summary>
    /// <param name="detail">Entry.</param>
    /// <param name="settings">Current settings.</param>
    /// <returns><see langword="true"/> when the row shows.</returns>
    public static bool IsAvailable(SettingsDetail detail, AppSettings settings) => detail switch
    {
        SettingsDetail.None => false,
        SettingsDetail.SongRowOrder => settings.EnableVisualOrder,
        SettingsDetail.Leeway => settings.FilterInvalidScores,
        _ => Enum.IsDefined(detail),
    };

    /// <summary>The selection after a settings change: an entry whose row disappeared returns the pane to the placeholder.</summary>
    /// <param name="selected">Current selection.</param>
    /// <param name="settings">New settings.</param>
    /// <returns>The selection, or <see cref="SettingsDetail.None"/>.</returns>
    public static SettingsDetail Reconcile(SettingsDetail selected, AppSettings settings) =>
        IsAvailable(selected, settings) ? selected : SettingsDetail.None;

    /// <summary>
    /// The Quick Links section a section entry's row stands for in the split layout, where Quick Links scroll the list to
    /// the row (the section itself is in the pane only while selected); <see langword="null"/> for App Settings entries.
    /// </summary>
    /// <param name="detail">Entry.</param>
    /// <returns>Quick Links section ID, or <see langword="null"/>.</returns>
    public static string? QuickLinkId(SettingsDetail detail) => detail switch
    {
        SettingsDetail.ItemShop => "item-shop",
        SettingsDetail.Instruments => "show-instruments",
        SettingsDetail.Metadata => "show-metadata",
        SettingsDetail.Accessibility => "accessibility",
        SettingsDetail.Version => "version",
        SettingsDetail.ServiceInfo => "service-info",
        SettingsDetail.FirstRun => "first-run",
        SettingsDetail.Licenses => "licenses",
        SettingsDetail.PrivacyPolicy => "privacy-policy",
        _ => null,
    };

    /// <summary>The value a row shows beside its chevron (CHOpt Path Default View and Leeway), else empty.</summary>
    /// <param name="detail">Entry.</param>
    /// <param name="settings">Current settings.</param>
    /// <returns>Value text.</returns>
    public static string Value(SettingsDetail detail, AppSettings settings) => detail switch
    {
        SettingsDetail.PathDefaultView => settings.PathDefaultView == PathDisplayMode.Text ? "Text" : "Image",
        SettingsDetail.Leeway => ScoreLeeway.Format(settings.Leeway),
        _ => "",
    };
}
#endregion
