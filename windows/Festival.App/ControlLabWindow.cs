using Festival.App.Controls;
using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;

namespace Festival.App;

#region Control lab
/// <summary>
/// Automation-only window (<c>--control-lab</c>, honoured only in Debug and automation launches) that shows one control in
/// every reachable state side by side, including states no live page reaches yet (disabled and muted instruments are
/// used only by the web's band filter). UI tests drive it through stable automation IDs; it never touches the service.
/// </summary>
public sealed partial class ControlLabWindow : Window
{
    /// <summary>Creates the lab for <paramref name="lab"/>.</summary>
    /// <param name="lab">A <see cref="LaunchOptions.ControlLabs"/> entry.</param>
    /// <param name="options">Launch options (window size).</param>
    public ControlLabWindow(string lab, LaunchOptions options)
    {
        Title = "Festival Score Tracker control lab";
        var sections = new StackPanel { Spacing = 24, Padding = new Thickness(24) };
        var motion = new TextBlock { Text = Motion.Allowed ? "Motion: allowed" : "Motion: reduced" };
        AutomationProperties.SetAutomationId(motion, "fst.control-lab.motion");
        sections.Children.Add(motion);
        if (lab == "instrument-selector") AddInstrumentSelectorSections(sections);
        else if (lab == "service-status") AddServiceStatusSections(sections);
        var root = new ScrollViewer
        {
            Content = sections,
            Background = (Brush)Application.Current.Resources["ApplicationPageBackgroundThemeBrush"],
        };
        AutomationProperties.SetAutomationId(root, "fst.control-lab");
        Content = root;
        var scale = (double)Win32.GetDpiForWindow(WinRT.Interop.WindowNative.GetWindowHandle(this)) / 96;
        AppWindow.Resize(new SizeInt32((int)((options.Width ?? 1280) * scale), (int)((options.Height ?? 820) * scale)));
    }

    /// <summary>Adds one Instrument Selector per reachable state (spec <c>.agents/controls/instrument-selector</c>).</summary>
    /// <param name="sections">Lab stack.</param>
    private static void AddInstrumentSelectorSections(StackPanel sections)
    {
        const string root = "fst.instrument-selector";
        Add(sections, "None", root, s => s.CompactMode = InstrumentSelectorCompactMode.Never);
        Add(sections, "Selected (Lead)", root + ".selected", s =>
        {
            s.CompactMode = InstrumentSelectorCompactMode.Never;
            s.Selected = Instrument.Lead;
        });
        Add(sections, "Required (Bass)", root + ".required", s =>
        {
            s.CompactMode = InstrumentSelectorCompactMode.Never;
            s.Required = true;
            s.Selected = Instrument.Bass;
        });
        Add(sections, "Hidden (Karaoke, Pro Bass)", root + ".hidden", s =>
        {
            s.CompactMode = InstrumentSelectorCompactMode.Never;
            s.Hidden = new HashSet<Instrument> { Instrument.Karaoke, Instrument.ProBass };
        });
        Add(sections, "Disabled (Drums, Pro Lead)", root + ".disabled", s =>
        {
            s.CompactMode = InstrumentSelectorCompactMode.Never;
            s.Disabled = new HashSet<Instrument> { Instrument.Drums, Instrument.ProLead };
        });
        Add(sections, "Muted (Bass, Vocals) with Lead selected", root + ".muted", s =>
        {
            s.CompactMode = InstrumentSelectorCompactMode.Never;
            s.Muted = new HashSet<Instrument> { Instrument.Bass, Instrument.Vocals };
            s.Selected = Instrument.Lead;
        });
        Add(sections, "Compact (Lead)", root + ".compact-mode", s =>
        {
            s.CompactMode = InstrumentSelectorCompactMode.Always;
            s.Selected = Instrument.Lead;
        });
        Add(sections, "Compact, deferred", root + ".deferred", s =>
        {
            s.CompactMode = InstrumentSelectorCompactMode.Always;
            s.DeferSelection = true;
        });
        Add(sections, "Automatic (compact when narrow)", root + ".auto", _ => { });
        Add(sections, "Detail content", root + ".detail", s =>
        {
            s.CompactMode = InstrumentSelectorCompactMode.Never;
            var detail = new TextBlock { Text = "Detail content for the selected instrument", Margin = new Thickness(0, 8, 0, 0), HorizontalAlignment = HorizontalAlignment.Left, TextWrapping = TextWrapping.Wrap, MaxWidth = 280 };
            AutomationProperties.SetAutomationId(detail, root + ".detail.content");
            s.DetailContent = detail;
        });
    }

    /// <summary>Adds a headed section with a selector and a live value readout (<c>&lt;prefix&gt;.value</c>).</summary>
    /// <param name="sections">Lab stack.</param>
    /// <param name="title">Section heading (also the selector's accessible name).</param>
    /// <param name="prefix">Selector <see cref="InstrumentSelector.IdPrefix"/>.</param>
    /// <param name="configure">Applies the state.</param>
    private static void Add(StackPanel sections, string title, string prefix, Action<InstrumentSelector> configure)
    {
        var heading = new TextBlock { Text = title, Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"] };
        AutomationProperties.SetHeadingLevel(heading, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level2);
        var selector = new InstrumentSelector { Instruments = InstrumentInfo.All, IdPrefix = prefix };
        AutomationProperties.SetName(selector, title);
        configure(selector);
        var value = new TextBlock { Text = ValueText(selector.Selected) };
        AutomationProperties.SetAutomationId(value, prefix + ".value");
        AutomationProperties.SetLiveSetting(value, Microsoft.UI.Xaml.Automation.Peers.AutomationLiveSetting.Polite);
        selector.SelectionChanged += (_, selected) => value.Text = ValueText(selected);
        var section = new StackPanel { Spacing = 8 };
        section.Children.Add(heading);
        // A fixed full row is wider than a compact window; scroll it rather than clip both ends.
        section.Children.Add(selector.CompactMode == InstrumentSelectorCompactMode.Never
            ? new ScrollViewer
            {
                Content = selector,
                HorizontalScrollMode = ScrollMode.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                VerticalScrollMode = ScrollMode.Disabled,
                VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
                IsTabStop = false,
            }
            : selector);
        section.Children.Add(value);
        sections.Children.Add(section);
    }

    /// <summary>Readout text.</summary>
    /// <param name="selected">Selection.</param>
    /// <returns>"Selected: Lead" or "Selected: none".</returns>
    private static string ValueText(Instrument? selected) => "Selected: " + (selected?.Label() ?? "none");

    /// <summary>
    /// Adds one Service Status per reachable state (spec <c>.agents/controls/service-status</c>): every reload re-reports the
    /// same issue, so a scrape freeze keeps counting down with the doubled backoff and the readout records it.
    /// </summary>
    /// <param name="sections">Lab stack.</param>
    private static void AddServiceStatusSections(StackPanel sections)
    {
        const string root = "fst.service-status";
        AddStatus(sections, "Scrape freeze, counting down", root + ".scrape-freeze-countdown", "Songs unavailable",
            new ServiceIssue(ServiceIssueKind.ScrapeInProgress, 120), inline: false);
        AddStatus(sections, "Scrape freeze, retrying with backoff", root + ".scrape-freeze-retrying", "Songs unavailable",
            new ServiceIssue(ServiceIssueKind.ScrapeInProgress, 2), inline: false);
        AddStatus(sections, "Unavailable", root + ".unavailable", "Songs unavailable",
            new ServiceIssue(ServiceIssueKind.Unavailable, 12), inline: false);
        AddStatus(sections, "Offline", root + ".offline", "Songs unavailable", new ServiceIssue(ServiceIssueKind.Offline), inline: false);
        AddStatus(sections, "Syncing", root + ".syncing", "Player unavailable", new ServiceIssue(ServiceIssueKind.Syncing), inline: false);
        AddStatus(sections, "Not found", root + ".not-found", "Song unavailable", new ServiceIssue(ServiceIssueKind.NotFound), inline: false);
        AddStatus(sections, "Other error", root + ".other", "Songs unavailable",
            new ServiceIssue(ServiceIssueKind.Other, null, "The service returned data we could not read. Try again."), inline: false);
        AddStatus(sections, "Inline section, scrape freeze", root + ".inline", "Leaderboard unavailable",
            new ServiceIssue(ServiceIssueKind.ScrapeInProgress, 240), inline: true);
        AddStatus(sections, "Inline section, offline", root + ".inline-offline", "Rivals unavailable",
            new ServiceIssue(ServiceIssueKind.Offline), inline: true);
    }

    /// <summary>Adds a headed section with a full-page or inline status and a reload readout (<c>&lt;prefix&gt;.value</c>).</summary>
    /// <param name="sections">Lab stack.</param>
    /// <param name="title">Section heading.</param>
    /// <param name="prefix">Status automation ID root.</param>
    /// <param name="fallbackTitle">Screen title used when the issue has none.</param>
    /// <param name="issue">Issue reported on load and after every reload.</param>
    /// <param name="inline">Whether to show the compact inline row inside a card instead of the full-page view.</param>
    private static void AddStatus(StackPanel sections, string title, string prefix, string fallbackTitle, ServiceIssue issue, bool inline)
    {
        var heading = new TextBlock { Text = title, Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"] };
        AutomationProperties.SetHeadingLevel(heading, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level2);
        var value = new TextBlock();
        AutomationProperties.SetAutomationId(value, prefix + ".value");
        var reloads = 0;
        ServiceStatusViewModel? status = null;
        status = new ServiceStatusViewModel(prefix, fallbackTitle, () =>
        {
            reloads++;
            status!.Report(issue);
            value.Text = StatusValueText(reloads, status);
            return Task.CompletedTask;
        }, TimeProvider.System);
        status.Report(issue);
        value.Text = StatusValueText(reloads, status);
        var section = new StackPanel { Spacing = 8 };
        section.Children.Add(heading);
        section.Children.Add(inline
            ? new Border
            {
                Style = (Style)Application.Current.Resources["FSTCardStyle"],
                MaxWidth = 480,
                HorizontalAlignment = HorizontalAlignment.Left,
                Child = new ServiceStatusInline { Status = status, IdPrefix = prefix },
            }
            : new ServiceStatusView { Status = status, IdPrefix = prefix, HorizontalAlignment = HorizontalAlignment.Left });
        section.Children.Add(value);
        // A page shows one full-page status; the lab shows several, so name each section to keep its Retry unambiguous.
        var group = new AccessibleGroup { Content = section };
        AutomationProperties.SetName(group, title);
        sections.Children.Add(group);
    }

    /// <summary>Reload readout text.</summary>
    /// <param name="reloads">Reloads so far (Retry and automatic).</param>
    /// <param name="status">Status after the latest report.</param>
    /// <returns>"Reloads: 1, next wait: 60 s" or "Reloads: 0, no automatic retry".</returns>
    private static string StatusValueText(int reloads, ServiceStatusViewModel status) => status.HasCountdown
        ? $"Reloads: {reloads}, next wait: {status.SecondsRemaining} s"
        : $"Reloads: {reloads}, no automatic retry";
}
#endregion
