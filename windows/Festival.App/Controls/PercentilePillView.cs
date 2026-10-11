using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Percentile pill view
/// <summary>
/// XAML-bindable host for the one shared percentile pill (<see cref="MetadataPills.Percentile"/>, pattern
/// <c>metadata-pills</c>), for data templates that cannot build it in code, such as the Band Detail best/worst song rows
/// (web <c>BandSongsSection</c> → <c>PlayerSongRow</c> → <c>PercentilePill</c>). The pill stays in the raw view: the host
/// row speaks the value.
/// </summary>
public sealed partial class PercentilePillView : Grid
{
    /// <summary>Label, e.g. <c>Top 4%</c>.</summary>
    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(PercentilePillView), new PropertyMetadata("", (d, _) => ((PercentilePillView)d).Apply()));

    /// <summary>Tier that picks the gold or neutral look.</summary>
    public static readonly DependencyProperty TierProperty = DependencyProperty.Register(
        nameof(Tier), typeof(SongPercentileTier), typeof(PercentilePillView),
        new PropertyMetadata(SongPercentileTier.Ordinary, (d, _) => ((PercentilePillView)d).Apply()));

    private readonly MetadataPill pill = MetadataPills.Create();

    /// <summary>Creates the host with an empty pill.</summary>
    public PercentilePillView()
    {
        VerticalAlignment = VerticalAlignment.Center;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        Children.Add(pill);
        // The shared pill re-resolves its own role brushes on a contrast-theme switch (MetadataPill.ApplyLook).
        Apply();
    }

    /// <summary>Label.</summary>
    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }

    /// <summary>Tier.</summary>
    public SongPercentileTier Tier
    {
        get => (SongPercentileTier)GetValue(TierProperty);
        set => SetValue(TierProperty, value);
    }

    /// <summary>Restyles the pill for the current label and tier.</summary>
    private void Apply() => MetadataPills.ApplyPercentile(pill, Text ?? "", Tier);
}
#endregion
