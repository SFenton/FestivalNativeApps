namespace Festival.Core.Domain;

#region Section shortcuts
/// <summary>Keyboard access for one navigation-pane section.</summary>
/// <param name="Section">Section.</param>
/// <param name="Digit">Ctrl+digit accelerator (1–9), or <see langword="null"/> for Settings (Ctrl+comma).</param>
/// <param name="AccessKey">Alt key-tip letter.</param>
/// <param name="ToolTip">Tooltip naming the accelerator, e.g. "Songs (Ctrl+1)".</param>
public readonly record struct SectionShortcut(AppSection Section, int? Digit, string AccessKey, string ToolTip);

/// <summary>
/// Windows keyboard shortcuts for the navigation pane: Ctrl+1…7 follow the visible pane order (at most seven sections) (like browser tabs), Ctrl+comma
/// opens Settings (the common Windows settings accelerator), and every section has a stable Alt access key.
/// </summary>
public static class KeyboardShortcuts
{
    /// <summary>Virtual-key code of the comma key (<c>VK_OEM_COMMA</c>).</summary>
    public const int CommaKey = 0xBC;

    /// <summary>Stable access key per section (unique; Settings uses E because S is Songs).</summary>
    /// <param name="section">Section.</param>
    /// <returns>Upper-case letter.</returns>
    public static string AccessKey(AppSection section) => section switch
    {
        AppSection.Songs => "S",
        AppSection.Suggestions => "U",
        AppSection.Leaderboards => "L",
        AppSection.Rivals => "R",
        AppSection.Statistics => "T",
        AppSection.Shop => "I",
        _ => "E",
    };

    /// <summary>Shortcuts for the visible sections, in pane order.</summary>
    /// <param name="visible">Visible sections (<see cref="AppSections.Visible"/>).</param>
    /// <returns>One shortcut per section.</returns>
    public static IReadOnlyList<SectionShortcut> For(IEnumerable<AppSection> visible)
    {
        var shortcuts = new List<SectionShortcut>();
        var digit = 0;
        foreach (var section in visible)
        {
            int? key = section == AppSection.Settings ? null : ++digit;
            var accelerator = key is { } d ? $"Ctrl+{d}" : "Ctrl+,";
            shortcuts.Add(new SectionShortcut(section, key, AccessKey(section), $"{section.Label()} ({accelerator})"));
        }
        return shortcuts;
    }
}
#endregion
