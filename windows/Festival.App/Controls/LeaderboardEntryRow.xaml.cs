using System.ComponentModel;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Leaderboard row
/// <summary>
/// The single leaderboard row control (operator batch 7.7): draws any <see cref="ILeaderboardEntryRow"/> — a score row
/// (<see cref="ILeaderboardScoreRow"/>, web <c>LeaderboardEntry</c>) or a rankings row (<see cref="ILeaderboardRankingRow"/>,
/// web <c>RankingEntry</c>) — as the web's frosted <c>entryRow</c>. Set in code rather than x:Bind so one lightweight
/// control serves every row type inside virtualized repeaters.
/// </summary>
public sealed partial class LeaderboardEntryRow : UserControl
{
    /// <summary>Rank column width per character, epx (web <c>Layout.rankCharWidth</c>).</summary>
    private const double RankCharWidth = 8.5;

    /// <summary>Narrowest rank column ("#1" to "#10" share it), epx.</summary>
    private const double MinRankWidth = 28;

    /// <summary>Score column width per character, epx (semibold body digits).</summary>
    private const double ScoreCharWidth = 9;

    /// <summary>Rating column width per character, epx (wider than a bold digit).</summary>
    private const double RatingCharWidth = 9.5;

    /// <summary>Row width from which the season shows (web <c>SEASON_BREAKPOINT</c>).</summary>
    private const double SeasonWidth = 520;

    /// <summary>Row width from which stars show (web <c>QUERY_SHOW_STARS</c>, less the page chrome).</summary>
    private const double StarsWidth = 700;

    /// <summary>Row width below which column gaps tighten (web <c>NARROW_BREAKPOINT</c>).</summary>
    private const double CompactWidth = 420;

    private static Windows.UI.ViewManagement.AccessibilitySettings? accessibility;

    private double width = double.NaN;
    private bool current;

    /// <summary>Row model: any <see cref="ILeaderboardEntryRow"/>.</summary>
    public static readonly DependencyProperty RowProperty = DependencyProperty.Register(
        nameof(Row), typeof(object), typeof(LeaderboardEntryRow), new PropertyMetadata(null, (d, e) => ((LeaderboardEntryRow)d).OnRowChanged(e.OldValue)));

    /// <summary>Creates the row.</summary>
    public LeaderboardEntryRow()
    {
        InitializeComponent();
        IsTabStop = false;
    }

    /// <summary>Row model.</summary>
    public object? Row
    {
        get => GetValue(RowProperty);
        set => SetValue(RowProperty, value);
    }

    /// <summary>Whether the row floats over other rows (pinned "your rank" footer): adds an opaque backplate.</summary>
    public bool IsFloating
    {
        get => Backplate.Visibility == Visibility.Visible;
        set => Backplate.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>The row's destination, if it has one.</summary>
    public AppRoute? Route => (Row as ILeaderboardEntryRow)?.Route;

    /// <summary>
    /// Whether this row's destination is showing in the page's detail column (list + detail layout): a muted fill so the
    /// list shows which entry the detail belongs to. The selected player's own accent wins.
    /// </summary>
    public bool IsCurrent
    {
        get => current;
        set
        {
            if (current == value) return;
            current = value;
            ApplySurface();
        }
    }

    /// <summary>Follows the board's shared rank width when it changes on an observable row.</summary>
    /// <param name="old">Previous row.</param>
    private void OnRowChanged(object? old)
    {
        if (old is INotifyPropertyChanged previous) previous.PropertyChanged -= OnRowPropertyChanged;
        if (Row is INotifyPropertyChanged next) next.PropertyChanged += OnRowPropertyChanged;
        Update();
    }

    /// <summary>Re-sizes the rank column when the board's shared width changes (the pinned row arrived).</summary>
    /// <param name="sender">Row.</param>
    /// <param name="e">Change.</param>
    private void OnRowPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ILeaderboardEntryRow.RankChars)) UpdateWidths();
    }

    /// <summary>Projects the model into the columns.</summary>
    private void Update()
    {
        if (Row is not ILeaderboardEntryRow row) return;
        RankText.Text = row.RankText;
        NameText.Text = row.Name;
        // A labelled row (score history date) has no rank: the label takes the rank column too (web label rows).
        var ranked = row.RankText.Length > 0;
        RankText.Visibility = ranked ? Visibility.Visible : Visibility.Collapsed;
        Grid.SetColumn(NameText, ranked ? 1 : 0);
        Grid.SetColumnSpan(NameText, ranked ? 1 : 2);
        switch (row)
        {
            case ILeaderboardScoreRow score:
                MetaText.Text = score.Season;
                MetaText.FontSize = 14;
                ValueText.Text = score.Score;
                BayesianText.Visibility = Visibility.Collapsed;
                PillText.Text = score.Accuracy;
                Pill.Visibility = score.HasAccuracy ? Visibility.Visible : Visibility.Collapsed;
                Pill.Background = ScoreBadge.Fill(score.IsFullCombo, score.AccuracyValue);
                Pill.BorderBrush = ScoreBadge.Stroke(score.IsFullCombo);
                Pill.RenderTransform = ScoreBadge.Skew(score.IsFullCombo);
                PillText.Foreground = ScoreBadge.Text(score.IsFullCombo);
                PillText.FontStyle = ScoreBadge.Style(score.IsFullCombo);
                StarsView.Stars = score.StarCount;
                break;
            case ILeaderboardRankingRow ranking:
                MetaText.Text = ranking.SongsText;
                MetaText.FontSize = 12;
                ValueText.Text = ranking.RatingText;
                BayesianText.Text = ranking.BayesianText;
                BayesianText.Visibility = ranking.BayesianText.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
                Pill.Visibility = Visibility.Collapsed;
                StarsView.Stars = 0;
                break;
        }
        AutomationProperties.SetName(RowButton, row.Announcement);
        AutomationProperties.SetAutomationId(RowButton, row.AutomationId);
        // Rows without a usable identity (production serves some empty account IDs) are shown but not interactive.
        RowButton.IsHitTestVisible = RowButton.IsTabStop = row.Route is not null;
        Chevron.Visibility = row.Route is not null ? Visibility.Visible : Visibility.Collapsed;
        ApplyWeights(row);
        ApplySurface();
        UpdateColumns();
        UpdateWidths();
    }

    /// <summary>
    /// Bold for the selected player (web <c>isPlayer</c>; operator batch 6.42): rank and name on score rows, plus the songs
    /// label and rating on rankings rows. Scores and ratings are otherwise semibold.
    /// </summary>
    /// <param name="row">Row.</param>
    private void ApplyWeights(ILeaderboardEntryRow row)
    {
        var selected = row.IsSelected;
        var ranking = row is ILeaderboardRankingRow;
        RankText.FontWeight = NameText.FontWeight = selected ? FontWeights.Bold : FontWeights.Normal;
        MetaText.FontWeight = BayesianText.FontWeight = selected && ranking ? FontWeights.Bold : FontWeights.Normal;
        ValueText.FontWeight = selected && ranking ? FontWeights.Bold : FontWeights.SemiBold;
        PillText.FontWeight = FontWeights.SemiBold;
    }

    /// <summary>Selected (purpleHighlight), current (muted) or plain frosted surface, and the matching text colours.</summary>
    private void ApplySurface()
    {
        var selected = (Row as ILeaderboardEntryRow)?.IsSelected == true;
        var resources = Application.Current.Resources;
        Surface.Background = (Brush)resources[selected ? "FSTPlayerRowBrush" : current ? "FSTCurrentRowBrush" : "FSTCardSurfaceBrush"];
        Surface.BorderBrush = (Brush)resources[selected ? "FSTPlayerRowStrokeBrush" : "FSTCardStrokeBrush"];
        // Selected-row text follows the fill (HighlightText under a contrast theme); other rows inherit the button's.
        if (selected)
        {
            var text = (Brush)resources["FSTPlayerRowTextBrush"];
            RankText.Foreground = NameText.Foreground = MetaText.Foreground = BayesianText.Foreground = Chevron.Foreground = text;
        }
        else
        {
            RankText.ClearValue(TextBlock.ForegroundProperty);
            NameText.ClearValue(TextBlock.ForegroundProperty);
            MetaText.ClearValue(TextBlock.ForegroundProperty);
            BayesianText.ClearValue(TextBlock.ForegroundProperty);
            Chevron.ClearValue(IconElement.ForegroundProperty);
        }
        // Ratings are the web's accentBlueBright; under a contrast theme the selected row keeps HighlightText.
        if (Row is ILeaderboardRankingRow && !(selected && IsHighContrast)) ValueText.Foreground = (Brush)resources["FSTRatingTextBrush"];
        else if (selected) ValueText.Foreground = (Brush)resources["FSTPlayerRowTextBrush"];
        else ValueText.ClearValue(TextBlock.ForegroundProperty);
    }

    /// <summary>Whether a Windows contrast theme is on.</summary>
    private static bool IsHighContrast => (accessibility ??= new Windows.UI.ViewManagement.AccessibilitySettings()).HighContrast;

    /// <summary>Season below <see cref="SeasonWidth"/> and stars below <see cref="StarsWidth"/> collapse, like the web's queries.</summary>
    private void UpdateColumns()
    {
        var known = !double.IsNaN(width);
        var score = Row as ILeaderboardScoreRow;
        var showMeta = Row is ILeaderboardRankingRow
            ? MetaText.Text.Length > 0
            : score is { Season.Length: > 0 } && known && width >= SeasonWidth;
        MetaText.Visibility = showMeta ? Visibility.Visible : Visibility.Collapsed;
        StarsHost.Visibility = score is { StarCount: > 0 } && known && width >= StarsWidth ? Visibility.Visible : Visibility.Collapsed;
        RowGrid.ColumnSpacing = known && width < CompactWidth ? 8 : 12;
    }

    /// <summary>Rank and score minimums shared by the board, so columns line up down the list and the pinned row.</summary>
    private void UpdateWidths()
    {
        if (Row is not ILeaderboardEntryRow row) return;
        var rankChars = Math.Max(RankText.Text.Length, row.RankChars);
        RankColumn.MinWidth = rankChars == 0 ? 0 : Math.Max(MinRankWidth, Math.Ceiling(rankChars * RankCharWidth));
        // Ratings reserve a little more than their own semibold width, so a bold (selected) rating of the same length
        // keeps the songs label in the same place (web colRating min width).
        ValueColumn.MinWidth = Row is ILeaderboardScoreRow score
            ? Math.Ceiling(score.ScoreChars * ScoreCharWidth)
            : Math.Ceiling(ValueText.Text.Length * RatingCharWidth);
    }

    /// <summary>Re-evaluates the width-dependent columns.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">New size.</param>
    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        width = e.NewSize.Width;
        UpdateColumns();
    }

    /// <summary>Opens the row's destination (in the page's detail column when it hosts one).</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (Route is not { } route) return;
        for (DependencyObject? node = this; node is not null; node = VisualTreeHelper.GetParent(node))
            if (node is IRouteHost host && host.TryShow(route)) return;
        MainWindow.Instance?.Navigate(route);
    }
}
#endregion
