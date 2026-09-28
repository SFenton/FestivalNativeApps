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
/// #666666 (difficulty-meter spec). One image-like accessible element; the polygons are hidden.
/// </summary>
public sealed partial class DifficultyMeter : Canvas
{
    /// <summary>Raw 0–6 service difficulty; <see cref="double.NaN"/> means unavailable.</summary>
    public static readonly DependencyProperty RawProperty = DependencyProperty.Register(
        nameof(Raw), typeof(double), typeof(DifficultyMeter), new PropertyMetadata(double.NaN, (d, _) => ((DifficultyMeter)d).Update()));

    private readonly Polygon[] bars = new Polygon[DifficultyScale.BarCount];

    /// <summary>Builds the seven polygons.</summary>
    public DifficultyMeter()
    {
        Width = DifficultyScale.Width;
        Height = DifficultyScale.Height;
        for (var i = 0; i < bars.Length; i++)
        {
            var polygon = new Polygon();
            foreach (var (x, y) in DifficultyScale.BarPolygon(i)) polygon.Points.Add(new Point(x, y));
            AutomationProperties.SetAccessibilityView(polygon, AccessibilityView.Raw);
            bars[i] = polygon;
            Children.Add(polygon);
        }
        AutomationProperties.SetAutomationId(this, "fst.songs.difficulty-meter");
        Update();
    }

    /// <summary>Raw difficulty.</summary>
    public double Raw
    {
        get => (double)GetValue(RawProperty);
        set => SetValue(RawProperty, value);
    }

    /// <summary>Exposes the meter as a single image with a spoken level.</summary>
    /// <returns>Automation peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new MeterPeer(this);

    /// <summary>Recolours bars and updates the accessible name.</summary>
    private void Update()
    {
        var filledCount = DifficultyScale.BarsForRaw(Raw);
        var filled = (Brush)Application.Current.Resources["FSTMeterFilledBrush"];
        var empty = (Brush)Application.Current.Resources["FSTMeterEmptyBrush"];
        for (var i = 0; i < bars.Length; i++) bars[i].Fill = i < filledCount ? filled : empty;
        var available = filledCount > 0;
        Opacity = available ? 1 : 0.4;
        AutomationProperties.SetName(this, DifficultyScale.Announcement(available ? Raw : null));
        if (!available) AutomationProperties.SetAutomationId(this, "fst.songs.difficulty-unavailable");
    }

    /// <summary>Image-typed peer.</summary>
    /// <param name="owner">Meter.</param>
    private sealed partial class MeterPeer(DifficultyMeter owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Image;

        /// <inheritdoc />
        protected override bool IsControlElementCore() => true;

        /// <inheritdoc />
        protected override IList<AutomationPeer>? GetChildrenCore() => null;
    }
}
#endregion
