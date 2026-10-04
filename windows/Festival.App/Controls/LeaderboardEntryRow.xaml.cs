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
    private static Windows.UI.ViewManagement.AccessibilitySettings? accessibility;

    private double width = double.NaN;
    private bool current;
    private string? rowAutomationId;

    /// <summary>Row model: any <see cref="ILeaderboardEntryRow"/>.</summary>
    public static readonly DependencyProperty RowProperty = DependencyProperty.Register(
        nameof(Row), typeof(object), typeof(LeaderboardEntryRow), new PropertyMetadata(null, (d, e) => ((LeaderboardEntryRow)d).OnRowChanged(e.OldValue)));

    /// <summary>Creates the row.</summary>
    public LeaderboardEntryRow()
    {
        InitializeComponent();
        IsTabStop = false;
        NameText.IsTextTrimmedChanged += (_, _) => UpdateNameToolTip();
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

    /// <summary>
    /// UIA automation ID for this instance instead of the row model's (e.g. the pinned "your rank" row, which would
    /// otherwise repeat the in-list row's <c>….row.&lt;accountId&gt;</c> ID). The row's one UIA element is its inner
    /// Button, so an ID set on this UserControl never reaches the automation tree.
    /// </summary>
    public string? RowAutomationId
    {
        get => rowAutomationId;
        set
        {
            rowAutomationId = value;
            Update();
        }
    }

    /// <summary>Moves focus to the row's button (a no-op for a row without a destination, which is not a tab stop).</summary>
    /// <param name="state">How focus arrives.</param>
    /// <returns>Whether the row's button took focus.</returns>
    public bool FocusRow(FocusState state) => RowButton.Focus(state);

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

    /// <summary>Follows the section's shared columns when they change on an observable row.</summary>
    /// <param name="old">Previous row.</param>
    private void OnRowChanged(object? old)
    {
        if (old is INotifyPropertyChanged previous) previous.PropertyChanged -= OnRowPropertyChanged;
        if (Row is INotifyPropertyChanged next) next.PropertyChanged += OnRowPropertyChanged;
        Update();
    }

    /// <summary>Re-fits the columns when the section's shared content changes (the pinned row arrived).</summary>
    /// <param name="sender">Row.</param>
    /// <param name="e">Change.</param>
    private void OnRowPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(ILeaderboardEntryRow.Section)) UpdateColumns();
    }

    /// <summary>
    /// Shows the full name as the row's tooltip only while the name is trimmed (narrow windows, large text sizes), so
    /// mouse and keyboard users can read what the ellipsis hides; Narrator already reads the full name.
    /// </summary>
    private void UpdateNameToolTip() =>
        ToolTipService.SetToolTip(RowButton, NameText.IsTextTrimmed && NameText.Text.Length > 0 ? NameText.Text : null);

    /// <summary>Projects the model into the columns.</summary>
    private void Update()
    {
        if (Row is not ILeaderboardEntryRow row) return;
        RankText.Text = row.RankText;
        NameText.Text = row.Name;
        UpdateNameToolTip();
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
                StarsView.Stars = 0;
                break;
        }
        AutomationProperties.SetName(RowButton, row.Announcement);
        AutomationProperties.SetAutomationId(RowButton, string.IsNullOrEmpty(rowAutomationId) ? row.AutomationId : rowAutomationId);
        // Rows without a usable identity (production serves some empty account IDs) are shown but not interactive, and
        // UIA reads them as text rather than an invokable button.
        RowButton.IsHitTestVisible = RowButton.IsTabStop = RowButton.IsActionable = row.Route is not null;
        Chevron.Visibility = row.Route is not null ? Visibility.Visible : Visibility.Collapsed;
        ApplyWeights(row);
        ApplySurface();
        UpdateColumns();
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
        // The selected row's text and chevron are already the system HighlightText-on-Highlight pair under a contrast theme;
        // without this, WinUI's automatic adjustment repaints them as WindowText on white backplates inside the fill.
        var adjustment = selected ? ElementHighContrastAdjustment.None : ElementHighContrastAdjustment.Application;
        RankText.HighContrastAdjustment = NameText.HighContrastAdjustment = MetaText.HighContrastAdjustment =
            BayesianText.HighContrastAdjustment = ValueText.HighContrastAdjustment = Chevron.HighContrastAdjustment = adjustment;
    }

    /// <summary>Whether a Windows contrast theme is on.</summary>
    private static bool IsHighContrast => (accessibility ??= new Windows.UI.ViewManagement.AccessibilitySettings()).HighContrast;

    /// <summary>
    /// Applies the section's <see cref="LeaderboardColumnLayout"/> plan (issue #37): every row of a section shows the same
    /// columns at the same widths, measured over all of its rows and its pinned row, so values line up vertically like the
    /// web. A shown column keeps its width on a row without a value (blank badge or star slot) instead of collapsing.
    /// </summary>
    private void UpdateColumns()
    {
        if (Row is not ILeaderboardEntryRow row) return;
        var section = row.Section ?? LeaderboardColumns.Measure(new[] { row });
        var score = row as ILeaderboardScoreRow;
        var plan = LeaderboardColumnLayout.Fit(section, width, TextScaleLayout.Factor, score?.PinsSeason == true);
        RowGrid.ColumnSpacing = plan.Gap;
        RankColumn.MinWidth = RankText.Text.Length == 0 ? 0 : plan.RankWidth;
        MetaColumn.MinWidth = plan.MetaWidth;
        PlaceMeta(plan.MetaBelowName, plan.ValueBelowName);
        MetaText.Visibility = (plan.ShowMeta || plan.MetaBelowName) && MetaText.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        ValueColumn.MinWidth = plan.ValueWidth;
        PillColumn.MinWidth = plan.AccuracyWidth;
        if (plan.ShowAccuracy) Pill.Width = plan.AccuracyWidth;
        Pill.Visibility = plan.ShowAccuracy && score is { HasAccuracy: true } ? Visibility.Visible : Visibility.Collapsed;
        StarsColumn.MinWidth = plan.StarsWidth;
        StarsHost.Visibility = plan.ShowStars && score is { StarCount: > 0 } ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>
    /// Puts the songs label in its own right-aligned column, or under the name when the column would squeeze the name away
    /// (issue #208: 200% text in a compact window left only an ellipsis). When the name is still squeezed the row stacks:
    /// rank and name (across the rating's column) on the first line, the songs label from the rank's edge and the rating
    /// on the second.
    /// </summary>
    /// <param name="below">Whether the label goes under the name.</param>
    /// <param name="stacked">Whether the rating goes under the name too.</param>
    private void PlaceMeta(bool below, bool stacked)
    {
        var nameColumn = Grid.GetColumn(NameText);
        var ranked = RankText.Visibility == Visibility.Visible;
        Grid.SetRowSpan(RankText, stacked ? 1 : 2);
        Grid.SetRow(NameText, 0);
        Grid.SetRowSpan(NameText, below || stacked ? 1 : 2);
        Grid.SetColumnSpan(NameText, (ranked ? 1 : 2) + (stacked ? 2 : 0));
        NameText.VerticalAlignment = below || stacked ? VerticalAlignment.Bottom : VerticalAlignment.Center;
        Grid.SetRow(ValueStack, stacked ? 1 : 0);
        Grid.SetRowSpan(ValueStack, stacked ? 1 : 2);
        ValueStack.VerticalAlignment = stacked ? VerticalAlignment.Top : VerticalAlignment.Center;
        Grid.SetRow(MetaText, below ? 1 : 0);
        Grid.SetRowSpan(MetaText, below ? 1 : 2);
        Grid.SetColumn(MetaText, !below ? 2 : stacked ? 0 : nameColumn);
        Grid.SetColumnSpan(MetaText, !below ? 1 : stacked ? 2 : (ranked ? 1 : 2));
        MetaText.VerticalAlignment = below ? VerticalAlignment.Top : VerticalAlignment.Center;
        MetaText.HorizontalAlignment = below ? HorizontalAlignment.Left : HorizontalAlignment.Right;
        MetaText.TextAlignment = below ? TextAlignment.Left : TextAlignment.Right;
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
