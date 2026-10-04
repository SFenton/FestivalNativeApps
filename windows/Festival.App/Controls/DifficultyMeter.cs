using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Difficulty meter
/// <summary>
/// Branded seven-bar difficulty meter: seven 8×20 parallelograms on a 62×20 canvas, filled white, unfilled
/// #666666 (difficulty-meter spec); under a Windows contrast theme filled bars use WindowText and unfilled bars become
/// GrayText outlines. A non-finite level shows the text "Difficulty unavailable" instead of bars.
/// One image-like accessible element (text when unavailable); the polygons and text are hidden from UI Automation.
/// </summary>
public sealed partial class DifficultyMeter : Grid
{
    /// <summary>Raw 0–6 service difficulty; <see cref="double.NaN"/> means unavailable.</summary>
    public static readonly DependencyProperty RawProperty = DependencyProperty.Register(
        nameof(Raw), typeof(double), typeof(DifficultyMeter), new PropertyMetadata(double.NaN, (d, _) => ((DifficultyMeter)d).Update()));

    private readonly Polygon[] bars = new Polygon[DifficultyScale.BarCount];
    private readonly Canvas canvas = new() { Width = DifficultyScale.Width, Height = DifficultyScale.Height };
    private readonly TextBlock unavailable = new()
    {
        Text = DifficultyScale.UnavailableText,
        VerticalAlignment = VerticalAlignment.Center,
        TextWrapping = TextWrapping.NoWrap,
    };
    private DifficultyMeterState state;

    /// <summary>Builds the seven polygons and the unavailable text.</summary>
    public DifficultyMeter()
    {
        for (var i = 0; i < bars.Length; i++)
        {
            var polygon = new Polygon();
            foreach (var (x, y) in DifficultyScale.BarPolygon(i)) polygon.Points.Add(new Point(x, y));
            bars[i] = polygon;
            canvas.Children.Add(polygon);
        }
        AutomationProperties.SetAccessibilityView(canvas, AccessibilityView.Raw);
        AutomationProperties.SetAccessibilityView(unavailable, AccessibilityView.Raw);
        unavailable.Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"];
        Children.Add(canvas);
        Children.Add(unavailable);
        // Bar and text brushes are set from code, so a contrast-theme switch must re-resolve them (theme-accessibility:
        // inline brush assignments do not follow {ThemeResource}).
        Loaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            ContrastTheme.Changed += OnColorsChanged;
            Update();
        };
        Unloaded += (_, _) => ContrastTheme.Changed -= OnColorsChanged;
        Update();
    }

    /// <summary>Raw difficulty.</summary>
    public double Raw
    {
        get => (double)GetValue(RawProperty);
        set => SetValue(RawProperty, value);
    }

    /// <summary>Exposes the meter as a single image (or text when unavailable) with a spoken level.</summary>
    /// <returns>Automation peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new MeterPeer(this);

    /// <summary>Re-resolves brushes on the UI thread after a system colour change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(Update);

    /// <summary>Applies the state for <see cref="Raw"/>: bar colours or unavailable text, accessible name and ID.</summary>
    private void Update()
    {
        state = DifficultyScale.State(Raw);
        canvas.Visibility = state.IsAvailable ? Visibility.Visible : Visibility.Collapsed;
        unavailable.Visibility = state.IsAvailable ? Visibility.Collapsed : Visibility.Visible;
        if (state.IsAvailable)
        {
            var filled = ContrastTheme.Brush("FSTMeterFilledBrush");
            var empty = ContrastTheme.Brush("FSTMeterEmptyBrush");
            // Contrast themes may put WindowText and GrayText close together (Desert: #3D3D3D vs #676767), so unfilled
            // bars become GrayText outlines: filled vs unfilled is told apart by shape, not colour alone.
            var outline = ContrastTheme.IsOn;
            for (var i = 0; i < bars.Length; i++)
            {
                var isFilled = state.IsFilled(i);
                bars[i].Fill = isFilled ? filled : outline ? null : empty;
                bars[i].Stroke = !isFilled && outline ? empty : null;
                bars[i].StrokeThickness = !isFilled && outline ? 1 : 0;
            }
        }
        else
        {
            unavailable.Foreground = ContrastTheme.Brush("FSTDeemphasisTextBrush");
        }
        AutomationProperties.SetName(this, state.Name);
        AutomationProperties.SetAutomationId(this, state.AutomationId);
    }

    /// <summary>Image-typed peer (Text while unavailable) with no children.</summary>
    /// <param name="owner">Meter.</param>
    private sealed partial class MeterPeer(DifficultyMeter owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() =>
            owner.state.IsAvailable ? AutomationControlType.Image : AutomationControlType.Text;

        /// <inheritdoc />
        protected override string GetClassNameCore() => nameof(DifficultyMeter);

        /// <inheritdoc />
        protected override bool IsControlElementCore() => true;

        /// <inheritdoc />
        protected override IList<AutomationPeer>? GetChildrenCore() => null;
    }
}
#endregion
