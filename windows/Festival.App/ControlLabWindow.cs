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
            var detail = new TextBlock { Text = "Detail content for the selected instrument", Margin = new Thickness(0, 8, 0, 0), HorizontalAlignment = HorizontalAlignment.Center };
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
}
#endregion
