using System.Runtime.CompilerServices;
using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Band score footer panel
/// <summary>
/// Two-child panel for a band row's team score footer: the score (first child) on the left and the badges (second child:
/// FC, accuracy, stars) on the right, or on a second line under the score when they don't fit
/// (<see cref="BandScoreFooterLayout.Stacks"/>). Rows under the same <see cref="IsSectionProperty"/> ancestor share one plan
/// (<see cref="BandScoreFooterSection{TKey}"/>, leaderboard-row R8). Deciding at measure time reports the stacked height at
/// once, so virtualized rows never keep a one-line height (as <c>LeaderboardEntryRow</c>, issue #220).
/// </summary>
public sealed partial class BandScoreFooterPanel : Panel
{
    /// <summary>Plans shared by the rows of each section element.</summary>
    private static readonly ConditionalWeakTable<DependencyObject, BandScoreFooterSection<BandScoreFooterPanel>> Sections = new();

    /// <summary>Marks the element whose descendant footers share one plan (a section's rows host or a board's list).</summary>
    public static readonly DependencyProperty IsSectionProperty = DependencyProperty.RegisterAttached(
        "IsSection", typeof(bool), typeof(BandScoreFooterPanel), new PropertyMetadata(false));

    /// <summary>Gets <see cref="IsSectionProperty"/>.</summary>
    /// <param name="element">Element.</param>
    /// <returns>Whether the element is a footer section.</returns>
    public static bool GetIsSection(DependencyObject element) => (bool)element.GetValue(IsSectionProperty);

    /// <summary>Sets <see cref="IsSectionProperty"/>.</summary>
    /// <param name="element">Element.</param>
    /// <param name="value">Whether the element is a footer section.</param>
    public static void SetIsSection(DependencyObject element, bool value) => element.SetValue(IsSectionProperty, value);

    /// <summary>Gap between the score and the badges, across or down.</summary>
    public double Spacing { get; set; } = 6;

    /// <summary>This row's section plan, or its own when it has no section ancestor.</summary>
    private BandScoreFooterSection<BandScoreFooterPanel>? section;

    /// <summary>Whether the last measure put the badges on their own line.</summary>
    private bool stacked;

    /// <summary>Creates the panel and leaves its section plan when it leaves the tree.</summary>
    public BandScoreFooterPanel() => Unloaded += (_, _) =>
    {
        if (section?.Remove(this) == true) InvalidateSection();
        section = null;
    };

    /// <inheritdoc />
    protected override Size MeasureOverride(Size availableSize)
    {
        var (score, badges) = Parts();
        var infinite = new Size(double.PositiveInfinity, double.PositiveInfinity);
        score?.Measure(infinite);
        badges?.Measure(infinite);
        var scoreSize = Visible(score);
        var badgesSize = Visible(badges);
        var needs = BandScoreFooterLayout.Stacks(availableSize.Width, scoreSize.Width, badgesSize.Width, Spacing);
        section ??= FindSection();
        if (section.Report(this, needs)) InvalidateSection();
        stacked = section.Stacked && badgesSize.Width > 0;
        if (stacked)
        {
            // The badges' own line may still be narrower than they want (extreme text sizes): let them clip at the edge
            // rather than push the footer wider than its card.
            badges?.Measure(new Size(availableSize.Width, double.PositiveInfinity));
            var width = Math.Max(scoreSize.Width, Visible(badges).Width);
            return new Size(double.IsInfinity(availableSize.Width) ? width : Math.Min(width, availableSize.Width),
                scoreSize.Height + Spacing + Visible(badges).Height);
        }
        var across = scoreSize.Width + (badgesSize.Width > 0 ? Spacing + badgesSize.Width : 0);
        return new Size(double.IsInfinity(availableSize.Width) ? across : Math.Min(across, availableSize.Width),
            Math.Max(scoreSize.Height, badgesSize.Height));
    }

    /// <inheritdoc />
    protected override Size ArrangeOverride(Size finalSize)
    {
        var (score, badges) = Parts();
        var scoreSize = Visible(score);
        var badgesSize = Visible(badges);
        if (stacked)
        {
            score?.Arrange(new Rect(0, 0, Math.Min(scoreSize.Width, finalSize.Width), scoreSize.Height));
            badges?.Arrange(new Rect(0, scoreSize.Height + Spacing, Math.Min(badgesSize.Width, finalSize.Width), badgesSize.Height));
            return finalSize;
        }
        var line = Math.Max(scoreSize.Height, badgesSize.Height);
        score?.Arrange(new Rect(0, (line - scoreSize.Height) / 2, scoreSize.Width, scoreSize.Height));
        badges?.Arrange(new Rect(Math.Max(0, finalSize.Width - badgesSize.Width), (line - badgesSize.Height) / 2,
            badgesSize.Width, badgesSize.Height));
        return finalSize;
    }

    /// <summary>The plan of the nearest <see cref="IsSectionProperty"/> ancestor, or a plan of this row alone.</summary>
    /// <returns>Section plan.</returns>
    private BandScoreFooterSection<BandScoreFooterPanel> FindSection()
    {
        for (var parent = VisualTreeHelper.GetParent(this); parent is not null; parent = VisualTreeHelper.GetParent(parent))
        {
            if (GetIsSection(parent)) return Sections.GetValue(parent, _ => new());
        }
        return new();
    }

    /// <summary>Re-measures the other rows after the section's plan changed.</summary>
    private void InvalidateSection()
    {
        if (section is null) return;
        foreach (var row in section.Members)
        {
            if (!ReferenceEquals(row, this)) row.InvalidateMeasure();
        }
    }

    /// <summary>The score and badges children.</summary>
    /// <returns>First and second child, either may be missing.</returns>
    private (UIElement? Score, UIElement? Badges) Parts() =>
        (Children.Count > 0 ? Children[0] : null, Children.Count > 1 ? Children[1] : null);

    /// <summary>A child's desired size, or zero when it is missing or collapsed.</summary>
    /// <param name="element">Child.</param>
    /// <returns>Desired size.</returns>
    private static Size Visible(UIElement? element) =>
        element is { Visibility: Visibility.Visible } ? element.DesiredSize : new Size(0, 0);
}
#endregion
