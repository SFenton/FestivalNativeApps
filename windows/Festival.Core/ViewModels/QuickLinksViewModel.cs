using CommunityToolkit.Mvvm.ComponentModel;

namespace Festival.Core.ViewModels;

#region Quick links
/// <summary>
/// A page's Quick Links: sections, the active one and jump requests. The App-side host measures section frames on
/// scroll (never per frame while idle) and performs the scroll; this model holds the rules.
/// </summary>
public sealed partial class QuickLinksViewModel : ObservableObject
{
    private readonly QuickLinkTracker tracker = new();
    private IReadOnlyDictionary<string, QuickLinkFrame> frames = new Dictionary<string, QuickLinkFrame>();
    private double viewportHeight;

    /// <summary>Creates the model.</summary>
    /// <param name="title">Menu/pane title, e.g. "Quick Links".</param>
    /// <param name="activationOffset">Activation line below the viewport top.</param>
    public QuickLinksViewModel(string title = "Quick Links", double activationOffset = QuickLinks.DefaultActivationOffset)
    {
        Title = title;
        ActivationOffset = activationOffset;
    }

    /// <summary>Raised when a jump needs the host to scroll to a section.</summary>
    public event EventHandler<string>? JumpRequested;

    /// <summary>Title (<c>nav</c> label).</summary>
    public string Title { get; }

    /// <summary>Activation offset.</summary>
    public double ActivationOffset { get; }

    /// <summary>Items in display order (concrete list for XAML).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(IsAvailable))]
    private List<QuickLinkItemViewModel> items = [];

    /// <summary>Active section ID.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(ActiveTitle), nameof(ActiveItem), nameof(EntryName))]
    private string? activeId;

    /// <summary>Whether the entry point shows (two or more sections).</summary>
    public bool IsAvailable => QuickLinks.IsAvailable(Items.Count);

    /// <summary>Active item, if any.</summary>
    public QuickLinkItemViewModel? ActiveItem => Items.FirstOrDefault(i => i.Section.Id == ActiveId);

    /// <summary>Active section title (entry point value).</summary>
    public string ActiveTitle => ActiveItem?.Section.Title ?? "";

    /// <summary>Accessible name for the menu button: title and current section.</summary>
    public string EntryName => ActiveItem is { } item ? $"{Title}, current section {item.Section.AccessibleTitle}" : Title;

    /// <summary>Tracker phase (tests and diagnostics).</summary>
    public QuickLinkPhase Phase => tracker.Phase;

    /// <summary>Replaces the sections (e.g. Debug-only or player-dependent ones change).</summary>
    /// <param name="sections">Sections in display order; duplicates keep their first occurrence.</param>
    public void SetSections(IEnumerable<QuickLinkSection> sections)
    {
        var ordered = QuickLinks.Ordered(sections, []);
        if (ordered.Select(s => s.Id).SequenceEqual(Items.Select(i => i.Section.Id)) &&
            ordered.SequenceEqual(Items.Select(i => i.Section))) return;
        Items = ordered.Select(s => new QuickLinkItemViewModel(s)).ToList();
        Refresh();
    }

    /// <summary>Host report after scrolling or layout: measured frames and viewport height.</summary>
    /// <param name="measured">Frames by section ID.</param>
    /// <param name="viewport">Viewport height.</param>
    /// <param name="isFinal">Whether the scroll came to rest (settles a jump).</param>
    public void ReportLayout(IReadOnlyDictionary<string, QuickLinkFrame> measured, double viewport, bool isFinal)
    {
        frames = measured;
        viewportHeight = viewport;
        var sections = Sections();
        if (isFinal && tracker.Phase == QuickLinkPhase.Scrolling) tracker.Settle(sections, frames, viewportHeight, ActivationOffset);
        else tracker.Update(sections, frames, viewportHeight, ActivationOffset);
        Apply();
    }

    /// <summary>Jumps to a section: marks it active and asks the host to scroll.</summary>
    /// <param name="id">Section ID.</param>
    public void Jump(string id)
    {
        if (Items.All(i => i.Section.Id != id)) return;
        tracker.BeginJump(id);
        Apply();
        JumpRequested?.Invoke(this, id);
    }

    /// <summary>Re-evaluates with the last known layout.</summary>
    private void Refresh()
    {
        tracker.Update(Sections(), frames, viewportHeight, ActivationOffset);
        Apply();
    }

    /// <summary>Publishes the tracker's active ID to items.</summary>
    private void Apply()
    {
        ActiveId = tracker.ActiveId;
        foreach (var item in Items) item.IsActive = item.Section.Id == ActiveId;
    }

    /// <summary>Current sections.</summary>
    /// <returns>Sections.</returns>
    private List<QuickLinkSection> Sections() => Items.Select(i => i.Section).ToList();
}

/// <summary>One Quick Links entry.</summary>
/// <param name="section">Section.</param>
public sealed partial class QuickLinkItemViewModel(QuickLinkSection section) : ObservableObject
{
    /// <summary>Section.</summary>
    public QuickLinkSection Section { get; } = section;

    /// <summary>Label.</summary>
    public string Title => Section.Title;

    /// <summary>Glyph (empty when an instrument icon or nothing is shown).</summary>
    public string Glyph => Section.Glyph ?? "";

    /// <summary>Automation ID.</summary>
    public string AutomationId => Section.AutomationId;

    /// <summary>Whether this is the current section (<c>aria-current="location"</c>).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(AccessibleName))]
    private bool isActive;

    /// <summary>Narrator name, with "current" for the active section.</summary>
    public string AccessibleName => IsActive ? $"{Section.AccessibleTitle}, current section" : Section.AccessibleTitle;
}
#endregion
