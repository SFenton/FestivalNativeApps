using System.ComponentModel;
using Festival.App.Services;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

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
    private Rectangle[]? bars;
    private System.Windows.Input.ICommand? command;

    /// <summary>Row model: any <see cref="ILeaderboardEntryRow"/>.</summary>
    public static readonly DependencyProperty RowProperty = DependencyProperty.Register(
        nameof(Row), typeof(object), typeof(LeaderboardEntryRow), new PropertyMetadata(null, (d, e) => ((LeaderboardEntryRow)d).OnRowChanged(e.OldValue)));

    /// <summary>Creates the row.</summary>
    public LeaderboardEntryRow()
    {
        InitializeComponent();
        IsTabStop = false;
        NameText.IsTextTrimmedChanged += (_, _) => UpdateNameToolTip();
        // The surface, text and badge brushes are set from code, so a contrast-theme switch while a board is open must
        // re-resolve them (issue #242: inline brush assignments do not follow {ThemeResource}).
        Loaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            ContrastTheme.Changed += OnColorsChanged;
            if (command is not null)
            {
                command.CanExecuteChanged -= OnCommandCanExecuteChanged;
                command.CanExecuteChanged += OnCommandCanExecuteChanged;
                Update();
            }
            ApplySurface();
        };
        Unloaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            if (command is not null) command.CanExecuteChanged -= OnCommandCanExecuteChanged;
        };
    }

    /// <summary>Re-applies the row's brushes on the UI thread after a system colour change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(ApplySurface);

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

    /// <summary>
    /// The pinned selected row's in-page action (pattern <c>leaderboard-row</c> R7, issue #307): while it can execute,
    /// activating the row runs it (jump to the page containing the row) instead of opening <see cref="Route"/> (the
    /// profile). The row's announcement names whichever destination applies.
    /// </summary>
    public System.Windows.Input.ICommand? Command
    {
        get => command;
        set
        {
            if (ReferenceEquals(command, value)) return;
            if (command is not null) command.CanExecuteChanged -= OnCommandCanExecuteChanged;
            command = value;
            // Subscribed only while loaded: a cached page model's command must not keep an unloaded row alive.
            if (command is not null && IsLoaded) command.CanExecuteChanged += OnCommandCanExecuteChanged;
            Update();
        }
    }

    /// <summary>Refreshes interactivity when the in-page action turns on or off.</summary>
    /// <param name="sender">Command.</param>
    /// <param name="e">Unused.</param>
    private void OnCommandCanExecuteChanged(object? sender, EventArgs e) => Update();

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
    /// Shows the full name as the row's tooltip only while the name is ellipsized (Animation effects or Reduce Motion
    /// off stops the marquee), so mouse and keyboard users can read what the ellipsis hides; Narrator already reads the
    /// full name.
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
        switch (row)
        {
            case ILeaderboardScoreRow score:
                MetaText.Text = score.Season;
                MetaText.FontSize = 14;
                ValueText.Text = score.Score;
                BayesianText.Visibility = Visibility.Collapsed;
                PillText.Text = score.BadgeText;
                AutomationProperties.SetAutomationId(PillText, BadgeAutomationId(score));
                AutomationProperties.SetAutomationId(MetaText, LeaderboardScoreRowIds.Season(BadgeAutomationId(score)));
                Pill.RenderTransform = ScoreBadge.Skew(score.IsFullCombo);
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
                PillText.ClearValue(AutomationProperties.AutomationIdProperty);
                MetaText.ClearValue(AutomationProperties.AutomationIdProperty);
                break;
        }
        AutomationProperties.SetAutomationId(RowButton, string.IsNullOrEmpty(rowAutomationId) ? row.AutomationId : rowAutomationId);
        // Rows without a usable identity (production serves some empty account IDs) are shown but not interactive, and
        // UIA reads them as text rather than an invokable button.
        var actionable = row.Route is not null || command?.CanExecute(null) == true;
        RowButton.IsHitTestVisible = RowButton.IsTabStop = RowButton.IsActionable = actionable;
        // The section reserves the chevron slot (UpdateColumns); a row without a destination leaves it blank so its
        // values stay in line with openable rows (issue #209).
        Chevron.Opacity = actionable ? 1 : 0;
        ApplyPlaceholder(row as LeaderboardSkeletonRow);
        ApplyWeights(row);
        ApplySurface();
        UpdateColumns();
    }

    /// <summary>
    /// The badge's UIA ID: the model's <c>fst.score.accuracy.…</c>, or one derived from <see cref="RowAutomationId"/> so a
    /// pinned copy of a listed row doesn't repeat the listed badge's ID.
    /// </summary>
    /// <param name="score">Score row.</param>
    /// <returns>Automation ID.</returns>
    private string BadgeAutomationId(ILeaderboardScoreRow score) =>
        string.IsNullOrEmpty(rowAutomationId) ? score.BadgeAutomationId
            : "fst.score.accuracy." + rowAutomationId[(rowAutomationId.LastIndexOf('.') + 1)..];

    /// <summary>
    /// A loading placeholder (<see cref="LeaderboardSkeletonRow"/>, issue #281) lays out exactly like a loaded row, so it
    /// is as tall at every text size and width, but its text is invisible, it is raw-view only (Narrator skips it; the
    /// card's loading is conveyed by its rows arriving) and it draws static placeholder bars in the text's cells. A
    /// recycled row turns all of that back off.
    /// </summary>
    /// <param name="skeleton">Placeholder model, or <see langword="null"/> for a loaded row.</param>
    private void ApplyPlaceholder(LeaderboardSkeletonRow? skeleton)
    {
        if (skeleton is null) RowButton.ClearValue(AutomationProperties.AccessibilityViewProperty);
        else AutomationProperties.SetAccessibilityView(RowButton, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
        RankText.Opacity = NameText.Opacity = MetaText.Opacity = ValueStack.Opacity = skeleton is null ? 1 : 0;
        if (skeleton is { ShowBars: true } && bars is null)
        {
            bars = [Bar(28, HorizontalAlignment.Left), Bar(0, HorizontalAlignment.Left), Bar(48, HorizontalAlignment.Left),
                Bar(56, HorizontalAlignment.Right)];
            foreach (var bar in bars) RowGrid.Children.Add(bar);
        }
        if (skeleton is not null && bars is not null) bars[1].Width = Math.Max(56, 140 - skeleton.Index * 12);
    }

    /// <summary>One static rounded placeholder bar (no shimmer: no per-frame work beside a game).</summary>
    /// <param name="width">Width in epx.</param>
    /// <param name="alignment">Alignment in its cell, like the text it stands in for.</param>
    /// <returns>Bar.</returns>
    private static Rectangle Bar(double width, HorizontalAlignment alignment) => new()
    {
        Height = 14, Width = width, RadiusX = 7, RadiusY = 7, HorizontalAlignment = alignment,
        VerticalAlignment = VerticalAlignment.Center, IsHitTestVisible = false,
        Fill = (Brush)Application.Current.Resources["FSTSurfaceMutedBrush"],
    };

    /// <summary>
    /// Puts a placeholder's bars in the cells of the text they stand in for: rank, name and rating, plus the songs label
    /// when large text gives it its own line, so a stacked placeholder shows a bar on each line.
    /// </summary>
    /// <param name="songsOwnLine">Whether the songs label sits on its own line under the name.</param>
    private void PlaceBars(bool songsOwnLine)
    {
        if (bars is null) return;
        var show = Row is LeaderboardSkeletonRow { ShowBars: true };
        Mirror(bars[0], RankText, show && RankText.Visibility == Visibility.Visible);
        Mirror(bars[1], NameText, show);
        Mirror(bars[2], MetaText, show && songsOwnLine && MetaText.Visibility == Visibility.Visible);
        Mirror(bars[3], ValueStack, show);
    }

    /// <summary>Copies a text element's grid cell to its placeholder bar.</summary>
    /// <param name="bar">Bar.</param>
    /// <param name="source">Text element.</param>
    /// <param name="visible">Whether the bar shows.</param>
    private static void Mirror(Rectangle bar, FrameworkElement source, bool visible)
    {
        Grid.SetRow(bar, Grid.GetRow(source));
        Grid.SetRowSpan(bar, Grid.GetRowSpan(source));
        Grid.SetColumn(bar, Grid.GetColumn(source));
        Grid.SetColumnSpan(bar, Grid.GetColumnSpan(source));
        bar.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
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

    /// <summary>
    /// Selected (purpleHighlight), current (muted) or plain frosted surface, the matching text colours and a score row's
    /// accuracy badge brushes. Re-run on a system colour change, because code-set brushes do not follow a contrast theme.
    /// </summary>
    private void ApplySurface()
    {
        var selected = (Row as ILeaderboardEntryRow)?.IsSelected == true;
        var resources = Application.Current.Resources;
        // A full-combo badge has no fill of its own, so on the selected row under a contrast theme its WindowText outline
        // and text would sit on Highlight (low contrast, then a system backplate): it follows the row's HighlightText.
        var badgeOnHighlight = false;
        if (Row is ILeaderboardScoreRow score)
        {
            badgeOnHighlight = selected && score.IsFullCombo && IsHighContrast;
            Pill.Background = ScoreBadge.Fill(score.IsFullCombo, score.AccuracyValue);
            Pill.BorderBrush = badgeOnHighlight ? (Brush)resources["FSTPlayerRowTextBrush"] : ScoreBadge.Stroke(score.IsFullCombo);
            PillText.Foreground = badgeOnHighlight ? (Brush)resources["FSTPlayerRowTextBrush"] : ScoreBadge.Text(score.IsFullCombo);
        }
        PillText.HighContrastAdjustment = badgeOnHighlight ? ElementHighContrastAdjustment.None : ElementHighContrastAdjustment.Application;
        Surface.Background = (Brush)resources[selected ? "FSTPlayerRowBrush" : current ? "FSTCurrentRowBrush" : "FSTCardSurfaceBrush"];
        Surface.BorderBrush = (Brush)resources[selected ? "FSTPlayerRowStrokeBrush" : "FSTCardStrokeBrush"];
        if (bars is not null)
            foreach (var bar in bars) bar.Fill = (Brush)resources["FSTSurfaceMutedBrush"];
        // Selected-row text follows the fill (HighlightText under a contrast theme); other rows inherit the button's.
        if (selected)
        {
            var text = (Brush)resources["FSTPlayerRowTextBrush"];
            RankText.Foreground = MetaText.Foreground = BayesianText.Foreground = Chevron.Foreground = text;
            NameText.Foreground = text;
        }
        else
        {
            RankText.ClearValue(TextBlock.ForegroundProperty);
            NameText.Foreground = null;
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
        RankText.HighContrastAdjustment = NameText.TextHighContrastAdjustment = MetaText.HighContrastAdjustment =
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
        MetaColumn.MinWidth = plan.Stacked ? 0 : plan.MetaWidth;
        MetaText.Visibility = (plan.ShowMeta || plan.MetaBelowName) && MetaText.Text.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        // The row is one UIA stop with Raw parts, so a season on screen must be in its name (issue #262).
        AutomationProperties.SetName(RowButton,
            score is not null && MetaText.Visibility == Visibility.Visible ? score.SeasonShownAnnouncement : row.Announcement);
        ValueColumn.MinWidth = plan.Stacked ? 0 : plan.ValueWidth;
        PillColumn.MinWidth = plan.AccuracyWidth;
        if (plan.ShowAccuracy) Pill.Width = plan.AccuracyWidth;
        Pill.Visibility = plan.ShowAccuracy && score is { BadgeText.Length: > 0 } ? Visibility.Visible : Visibility.Collapsed;
        StarsColumn.MinWidth = plan.StarsWidth;
        StarsHost.Visibility = plan.ShowStars && score is { StarCount: > 0 } ? Visibility.Visible : Visibility.Collapsed;
        Chevron.Visibility = plan.ShowChevron ? Visibility.Visible : Visibility.Collapsed;
        PlaceColumns(plan, RankText.Text.Length > 0);
    }

    /// <summary>
    /// Places the columns on one line, or under the name when large text in a narrow row would squeeze the name to an
    /// ellipsis. A rankings row moves its songs label under the name (issue #208), and when the name is still squeezed
    /// stacks: rank and name (across the rating's column) on the first line, the songs label from the rank's edge and the
    /// rating on the second. A score row stacks its values (issue #207): the name across the first line, a pinned season
    /// and the score, badge and stars under it in the name's columns (a third line when they don't fit side by side).
    /// </summary>
    /// <param name="plan">Section column plan.</param>
    /// <param name="ranked">Whether the row has a rank (labelled rows put the name in the rank column too).</param>
    private void PlaceColumns(LeaderboardColumnPlan plan, bool ranked)
    {
        var nameColumn = ranked ? 1 : 0;
        var nameSpan = ranked ? 1 : 2;
        var below = plan.MetaBelowName;
        var rankingStack = plan.ValueBelowName;
        var scoreStack = plan.Stacked;
        var multiLine = below || rankingStack || scoreStack;
        var underSpan = 4 - nameColumn;
        var valueLine = plan.SplitValues ? 2 : 1;

        Place(RankText, 0, rankingStack || scoreStack ? 1 : 3, 0, 1, VerticalAlignment.Center);
        Place(NameText, 0, multiLine ? 1 : 3, nameColumn, nameSpan + (scoreStack ? 4 : rankingStack ? 2 : 0),
            below || rankingStack ? VerticalAlignment.Bottom : VerticalAlignment.Center);

        if (scoreStack) Place(MetaText, 1, 1, nameColumn, underSpan, VerticalAlignment.Center);
        else if (below) Place(MetaText, 1, 1, rankingStack ? 0 : nameColumn, rankingStack ? 2 : nameSpan, VerticalAlignment.Top);
        else Place(MetaText, 0, 3, 2, 1, VerticalAlignment.Center);
        var left = below || scoreStack;
        MetaText.HorizontalAlignment = left ? HorizontalAlignment.Left : HorizontalAlignment.Right;
        MetaText.TextAlignment = left ? TextAlignment.Left : TextAlignment.Right;

        if (scoreStack) Place(ValueStack, valueLine, 1, nameColumn, underSpan, VerticalAlignment.Center);
        else if (rankingStack) Place(ValueStack, 1, 1, 3, 1, VerticalAlignment.Top);
        else Place(ValueStack, 0, 3, 3, 1, VerticalAlignment.Center);
        Place(Pill, scoreStack ? valueLine : 0, scoreStack ? 1 : 3, 4, 1, VerticalAlignment.Center);
        Place(StarsHost, scoreStack ? valueLine : 0, scoreStack ? 1 : 3, 5, 1, VerticalAlignment.Center);
        RowButton.Padding = scoreStack ? new Thickness(12, 6, 12, 6) : new Thickness(12, 0, 12, 0);
        PlaceBars(below || rankingStack);
    }

    /// <summary>Puts an element in the row grid.</summary>
    /// <param name="element">Element.</param>
    /// <param name="row">First grid row.</param>
    /// <param name="rowSpan">Grid rows spanned.</param>
    /// <param name="column">First grid column.</param>
    /// <param name="columnSpan">Grid columns spanned.</param>
    /// <param name="vertical">Vertical alignment within the span.</param>
    private static void Place(FrameworkElement element, int row, int rowSpan, int column, int columnSpan, VerticalAlignment vertical)
    {
        Grid.SetRow(element, row);
        Grid.SetRowSpan(element, rowSpan);
        Grid.SetColumn(element, column);
        Grid.SetColumnSpan(element, columnSpan);
        element.VerticalAlignment = vertical;
    }
    /// <summary>
    /// Fits the columns to the width offered in the measure pass, before the grid measures, so a newly realized row
    /// reports its stacked height at once (issue #220). Waiting for <see cref="OnSizeChanged"/> measured it on one line
    /// first, and the virtualizing list could keep that height after the row stacked, drawing its values over the next row.
    /// </summary>
    /// <param name="availableSize">Space offered by the list.</param>
    /// <returns>Desired size.</returns>
    protected override Windows.Foundation.Size MeasureOverride(Windows.Foundation.Size availableSize)
    {
        if (double.IsFinite(availableSize.Width) && availableSize.Width != width)
        {
            width = availableSize.Width;
            UpdateColumns();
        }
        return base.MeasureOverride(availableSize);
    }

    /// <summary>Re-evaluates the width-dependent columns.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">New size.</param>
    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        width = e.NewSize.Width;
        UpdateColumns();
    }

    /// <summary>Runs the in-page action when it applies, else opens the row's destination (in the page's detail column when it hosts one).</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (command?.CanExecute(null) == true)
        {
            command.Execute(null);
            return;
        }
        if (Route is not { } route) return;
        for (DependencyObject? node = this; node is not null; node = VisualTreeHelper.GetParent(node))
            if (node is IRouteHost host && host.TryShow(route)) return;
        MainWindow.Instance?.Navigate(route);
    }
}
#endregion
