using Festival.Core.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Skeleton
/// <summary>
/// Static placeholder rows shown while a Leaderboards card loads. Static on purpose: a shimmer would add per-frame work
/// beside a game. Hidden from Narrator; the card's loading state is conveyed by its heading and rows appearing. Each row is
/// the canonical <see cref="LeaderboardEntryRow"/> drawing a <see cref="LeaderboardSkeletonRow"/>, spaced like the loaded
/// rows, so it takes the loaded rows' column plan, stacked lines and percentile caption line at every text size and card
/// width and rows don't jump when data arrives (issues #90 and #281; <c>leaderboard-row</c> R2).
/// </summary>
public sealed partial class LeaderboardsSkeleton : StackPanel
{
    /// <summary>Placeholder rows (the card's <c>SkeletonRows</c>).</summary>
    public static readonly DependencyProperty RowsProperty = DependencyProperty.Register(
        nameof(Rows), typeof(IReadOnlyList<LeaderboardSkeletonRow>), typeof(LeaderboardsSkeleton),
        new PropertyMetadata(null, (d, _) => ((LeaderboardsSkeleton)d).Build()));

    /// <summary>Creates the empty block; <see cref="Rows"/> fills it.</summary>
    public LeaderboardsSkeleton()
    {
        Spacing = LeaderboardRowMetrics.Spacing;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
    }

    /// <summary>Whether the placeholder rows sit inside their card (issue #643).</summary>
    private bool inCard;

    /// <summary>
    /// Whether the placeholders sit inside the card that will hold the loaded rows (Leaderboards overview cards, issue #643):
    /// they touch and draw in-card <see cref="GroupedRowSlice"/>s (no surface, a hairline between them), like the loaded rows.
    /// </summary>
    public bool InCard
    {
        get => inCard;
        set
        {
            if (inCard == value) return;
            inCard = value;
            Spacing = value ? 0 : LeaderboardRowMetrics.Spacing;
            Build();
        }
    }

    /// <summary>Placeholder rows.</summary>
    public IReadOnlyList<LeaderboardSkeletonRow>? Rows
    {
        get => (IReadOnlyList<LeaderboardSkeletonRow>?)GetValue(RowsProperty);
        set => SetValue(RowsProperty, value);
    }

    /// <summary>Draws one canonical row per placeholder.</summary>
    private void Build()
    {
        Children.Clear();
        var rows = Rows ?? [];
        for (var i = 0; i < rows.Count; i++)
        {
            var row = new LeaderboardEntryRow { Row = rows[i] };
            if (inCard) row.Slice = GroupedRowSlice.For(i, rows.Count, false, false, inCard: true);
            Children.Add(row);
        }
    }
}
#endregion
