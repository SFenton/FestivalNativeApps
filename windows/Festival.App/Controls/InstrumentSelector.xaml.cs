using System.Numerics;
using Festival.App.Services;
using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace Festival.App.Controls;

#region Instrument selector
/// <summary>
/// Native port of the web <c>InstrumentSelector</c>: a centred row of 64 epx instrument circles (a green disc grows behind
/// the selected one), hidden/disabled/muted instruments, optional required selection, and a compact
/// previous/centre/next mode chosen automatically when the row is too narrow (or forced by <see cref="CompactMode"/>).
/// <see cref="DetailContent"/> expands below the row while an instrument is selected. Rules live in
/// <see cref="InstrumentSelectorState"/>; this control only renders and forwards input.
/// </summary>
public sealed partial class InstrumentSelector : UserControl
{
    /// <summary>Content shown under the row while an instrument is selected.</summary>
    public static readonly DependencyProperty DetailContentProperty = DependencyProperty.Register(
        nameof(DetailContent), typeof(object), typeof(InstrumentSelector),
        new PropertyMetadata(null, (d, e) => ((InstrumentSelector)d).OnDetailContentChanged(e.NewValue)));

    private static readonly SolidColorBrush SelectedFill = new(ColorHelper.FromArgb(0xFF, 0x2E, 0xCC, 0x71));
    private readonly InstrumentSelectorState state = new();
    private readonly Dictionary<Instrument, (ToggleButton Button, Ellipse Disc)> buttons = [];
    private ToggleButton? compactButton;
    private Ellipse? compactDisc;
    private InstrumentIcon? compactIcon;
    private InstrumentSelectorCompactMode compactMode;
    private bool keyboardLead;
    private bool isCompact;
    private bool syncing;
    private string idPrefix = "fst.instrument-selector";

    /// <summary>Creates the selector.</summary>
    public InstrumentSelector()
    {
        InitializeComponent();
        SizeChanged += (_, e) => UpdateCompact(e.NewSize.Width);
    }

    /// <summary>Raised when the user changes the selection (<see langword="null"/> = cleared).</summary>
    public event EventHandler<Instrument?>? SelectionChanged;

    #region Properties
    /// <summary>Instruments in display order.</summary>
    public IReadOnlyList<Instrument> Instruments
    {
        get => state.Instruments;
        set
        {
            state.Instruments = value;
            Rebuild();
        }
    }

    /// <summary>Selected instrument, or <see langword="null"/>.</summary>
    public Instrument? Selected
    {
        get => state.Selected;
        set
        {
            if (state.Selected == value) return;
            state.Selected = value;
            Refresh();
        }
    }

    /// <summary>Instruments left out of the row.</summary>
    public IReadOnlySet<Instrument> Hidden
    {
        get => state.Hidden;
        set
        {
            state.Hidden = value;
            Rebuild();
        }
    }

    /// <summary>Instruments shown but not selectable.</summary>
    public IReadOnlySet<Instrument> Disabled
    {
        get => state.Disabled;
        set
        {
            state.Disabled = value;
            Refresh();
        }
    }

    /// <summary>Instruments shown as conflicting (still selectable).</summary>
    public IReadOnlySet<Instrument> Muted
    {
        get => state.Muted;
        set
        {
            state.Muted = value;
            Refresh();
        }
    }

    /// <summary>When set, pressing the selected instrument keeps it selected.</summary>
    public bool Required
    {
        get => state.Required;
        set => state.Required = value;
    }

    /// <summary>When set, compact arrows preview without selecting until the centre is pressed.</summary>
    public bool DeferSelection
    {
        get => state.DeferSelection;
        set => state.DeferSelection = value;
    }

    /// <summary>Full row, compact arrows, or automatic (default).</summary>
    public InstrumentSelectorCompactMode CompactMode
    {
        get => compactMode;
        set
        {
            compactMode = value;
            UpdateCompact(ActualWidth);
        }
    }

    /// <summary>Whether the song's Lead signature is Keyboard (keys icon variants).</summary>
    public bool KeyboardLead
    {
        get => keyboardLead;
        set
        {
            keyboardLead = value;
            Rebuild();
        }
    }

    /// <summary>Automation ID prefix; buttons get <c>&lt;prefix&gt;.&lt;Solo_…&gt;</c>, arrows <c>.previous</c>/<c>.next</c>.</summary>
    public string IdPrefix
    {
        get => idPrefix;
        set
        {
            idPrefix = value;
            Rebuild();
        }
    }

    /// <summary>Content that expands under the row while an instrument is selected.</summary>
    public object? DetailContent
    {
        get => GetValue(DetailContentProperty);
        set => SetValue(DetailContentProperty, value);
    }
    #endregion

    #region Rendering
    /// <summary>Recreates the row buttons for the current instruments.</summary>
    private void Rebuild()
    {
        Row.Children.Clear();
        buttons.Clear();
        foreach (var instrument in state.Available)
        {
            var (button, disc, _) = CreateCircle(instrument);
            AutomationProperties.SetAutomationId(button, $"{idPrefix}.{instrument.ServiceId()}");
            var captured = instrument;
            button.Click += (_, _) => Commit(state.Press(captured, out var changed), changed);
            buttons[instrument] = (button, disc);
            Row.Children.Add(button);
        }
        (compactButton, compactDisc, compactIcon) = CreateCircle(null);
        AutomationProperties.SetAutomationId(compactButton, idPrefix + ".compact");
        compactButton.Click += (_, _) => Commit(state.PressCompact(out var changed), changed);
        CompactHost.Child = compactButton;
        AutomationProperties.SetAutomationId(PreviousButton, idPrefix + ".previous");
        AutomationProperties.SetAutomationId(NextButton, idPrefix + ".next");
        UpdateCompact(ActualWidth);
        Refresh();
    }

    /// <summary>Builds one circle button.</summary>
    /// <param name="instrument">Instrument, or <see langword="null"/> for the compact centre (icon set later).</param>
    /// <returns>Button, its disc and icon.</returns>
    private (ToggleButton Button, Ellipse Disc, InstrumentIcon Icon) CreateCircle(Instrument? instrument)
    {
        var disc = new Ellipse
        {
            Fill = SelectedFill,
            Scale = new Vector3(0, 0, 1),
            CenterPoint = new Vector3(32, 32, 0),
        };
        var icon = new InstrumentIcon { Width = 48, Height = 48, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        AutomationProperties.SetAccessibilityView(icon, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        if (instrument is { } i)
        {
            icon.File = i.IconFile(keyboardLead);
            icon.Label = i.Label();
        }
        var grid = new Grid { Width = 64, Height = 64 };
        grid.Children.Add(disc);
        grid.Children.Add(icon);
        var button = new ToggleButton { Style = (Style)Resources["FSTInstrumentCircleButtonStyle"], Content = grid };
        if (instrument is { } named)
        {
            AutomationProperties.SetName(button, named.Label());
            ToolTipService.SetToolTip(button, named.Label());
        }
        return (button, disc, icon);
    }

    /// <summary>Applies selection, disabled and muted states to every button.</summary>
    private void Refresh()
    {
        syncing = true;
        var selected = state.EffectiveSelected;
        foreach (var (instrument, (button, disc)) in buttons)
        {
            var on = selected == instrument;
            button.IsChecked = on;
            button.IsEnabled = !state.IsDisabled(instrument);
            button.Opacity = state.IsDisabled(instrument) ? 0.28 : state.IsMuted(instrument) ? 0.42 : 1;
            SetDisc(disc, on);
        }
        if (compactButton is not null && compactDisc is not null && compactIcon is not null && state.CompactKey is { } key)
        {
            compactIcon.File = key.IconFile(keyboardLead);
            compactIcon.Label = key.Label();
            AutomationProperties.SetName(compactButton, key.Label());
            ToolTipService.SetToolTip(compactButton, key.Label());
            compactButton.IsChecked = selected == key;
            compactButton.IsEnabled = !state.IsDisabled(key);
            compactButton.Opacity = state.IsDisabled(key) ? 0.28 : state.IsCompactMuted() ? 0.42 : 1;
            SetDisc(compactDisc, selected is not null);
        }
        DetailsPresenter.Visibility = state.HasSelection && DetailContent is not null ? Visibility.Visible : Visibility.Collapsed;
        syncing = false;
    }

    /// <summary>Grows or shrinks the green disc on the composition thread (instant under reduced motion).</summary>
    /// <param name="disc">Disc.</param>
    /// <param name="on">Selected.</param>
    private static void SetDisc(Ellipse disc, bool on)
    {
        disc.ScaleTransition = Motion.Allowed ? new Vector3Transition { Duration = TimeSpan.FromMilliseconds(300) } : null;
        disc.Scale = on ? Vector3.One : new Vector3(0, 0, 1);
    }

    /// <summary>Switches between the full row and compact arrows.</summary>
    /// <param name="width">Available width.</param>
    private void UpdateCompact(double width)
    {
        var compact = state.IsCompact(compactMode, width);
        if (compact == isCompact && Row.Visibility != CompactRow.Visibility) return;
        isCompact = compact;
        Row.Visibility = compact ? Visibility.Collapsed : Visibility.Visible;
        CompactRow.Visibility = compact ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>Shows the detail content under the row when set.</summary>
    /// <param name="content">New content.</param>
    private void OnDetailContentChanged(object? content)
    {
        DetailsPresenter.Content = content;
        Refresh();
    }
    #endregion

    #region Input
    /// <summary>Reports a new selection and redraws.</summary>
    /// <param name="next">New selection.</param>
    /// <param name="changed">Whether anything should be reported.</param>
    private void Commit(Instrument? next, bool changed)
    {
        if (syncing) return;
        if (changed)
        {
            state.Selected = next;
            SelectionChanged?.Invoke(this, next);
        }
        Refresh();
    }

    /// <summary>Compact previous arrow.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnPrevious(object sender, RoutedEventArgs e) => Commit(state.Cycle(-1, out var changed), changed);

    /// <summary>Compact next arrow.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnNext(object sender, RoutedEventArgs e) => Commit(state.Cycle(1, out var changed), changed);
    #endregion
}
#endregion
