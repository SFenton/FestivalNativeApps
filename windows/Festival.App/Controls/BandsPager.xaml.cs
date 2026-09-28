using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Bands pager
/// <summary>Renders a <see cref="BandsPagerViewModel"/> with <c>&lt;prefix&gt;.page-first/previous/page-info/next/last</c> IDs.</summary>
public sealed partial class BandsPager : UserControl
{
    /// <summary>Bound pager.</summary>
    public static readonly DependencyProperty PagerProperty = DependencyProperty.Register(
        nameof(Pager), typeof(BandsPagerViewModel), typeof(BandsPager), new PropertyMetadata(null, (d, _) => ((BandsPager)d).Bindings.Update()));

    /// <summary>Automation ID prefix such as <c>fst.player-bands</c>.</summary>
    public static readonly DependencyProperty IdPrefixProperty = DependencyProperty.Register(
        nameof(IdPrefix), typeof(string), typeof(BandsPager), new PropertyMetadata(null, (d, _) => ((BandsPager)d).ApplyIds()));

    /// <summary>Creates the pager.</summary>
    public BandsPager() => InitializeComponent();

    /// <summary>Pager to render.</summary>
    public BandsPagerViewModel? Pager
    {
        get => (BandsPagerViewModel?)GetValue(PagerProperty);
        set => SetValue(PagerProperty, value);
    }

    /// <summary>Automation ID prefix.</summary>
    public string? IdPrefix
    {
        get => (string?)GetValue(IdPrefixProperty);
        set => SetValue(IdPrefixProperty, value);
    }

    /// <summary>Stamps the per-button automation IDs.</summary>
    private void ApplyIds()
    {
        var prefix = IdPrefix ?? "fst.bands";
        AutomationProperties.SetAutomationId(FirstButton, prefix + ".page-first");
        AutomationProperties.SetAutomationId(PreviousButton, prefix + ".page-previous");
        AutomationProperties.SetAutomationId(PageInfo, prefix + ".page-info");
        AutomationProperties.SetAutomationId(NextButton, prefix + ".page-next");
        AutomationProperties.SetAutomationId(LastButton, prefix + ".page-last");
    }
}
#endregion
