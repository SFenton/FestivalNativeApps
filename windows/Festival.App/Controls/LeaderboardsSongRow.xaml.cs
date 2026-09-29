using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Song leaderboard row
/// <summary>One solo chart row; season and stars collapse below 520 epx so rank, name, accuracy and score stay readable.</summary>
public sealed partial class LeaderboardsSongRow : UserControl, ISeparatedRow
{
    /// <summary>Rank column width per character, epx (web <c>Layout.rankCharWidth</c>).</summary>
    private const double RankCharWidth = 8.5;

    private bool separatorWanted;
    private bool compact;

    /// <summary>Wide-row threshold in effective pixels.</summary>
    private const double WideWidth = 520;

    /// <summary>Row model.</summary>
    public static readonly DependencyProperty RowProperty = DependencyProperty.Register(
        nameof(Row), typeof(SongLeaderboardRowViewModel), typeof(LeaderboardsSongRow),
        new PropertyMetadata(null, (d, _) => ((LeaderboardsSongRow)d).Update()));

    /// <summary>Creates the row.</summary>
    public LeaderboardsSongRow()
    {
        InitializeComponent();
        IsTabStop = false;
    }

    /// <summary>Row model.</summary>
    public SongLeaderboardRowViewModel? Row
    {
        get => (SongLeaderboardRowViewModel?)GetValue(RowProperty);
        set => SetValue(RowProperty, value);
    }

    /// <inheritdoc />
    public bool ShowSeparator
    {
        set
        {
            separatorWanted = value;
            UpdateSeparator();
        }
    }

    /// <summary>Hairline above a non-first row, except over the selected row's accent border.</summary>
    private void UpdateSeparator() =>
        Separator.Visibility = separatorWanted && Row?.IsSelected != true ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>Rank column minimum: ranks of equal length share a width so names align (web computeRankWidth).</summary>
    private void UpdateRankWidth()
    {
        var rankChars = Math.Max(RankText.Text.Length, Row?.RankChars ?? 0);
        RankColumn.MinWidth = Math.Max(compact ? 24 : 28, Math.Ceiling(rankChars * RankCharWidth));
        // Shared score width too (web "ch" width over the page and the pinned row).
        var scoreWidth = Math.Ceiling((Row?.ScoreChars ?? 0) * ScoreCharWidth);
        ScoreColumn.MinWidth = compact ? scoreWidth : Math.Max(88, scoreWidth);
    }

    /// <summary>Score column width per character, epx (semibold body digits).</summary>
    private const double ScoreCharWidth = 9;

    /// <summary>Projects the model into the template.</summary>
    private void Update()
    {
        if (Row is not { } row) return;
        RankText.Text = row.RankText;
        NameText.Text = row.Name;
        SeasonText.Text = row.Season;
        StarsView.Stars = row.StarCount;
        PillText.Text = row.AccuracyPill;
        Pill.Visibility = row.HasAccuracy ? Visibility.Visible : Visibility.Collapsed;
        Pill.Background = ScoreBadge.Fill(row.IsFullCombo, row.AccuracyValue);
        Pill.BorderBrush = ScoreBadge.Stroke(row.IsFullCombo);
        Pill.RenderTransform = ScoreBadge.Skew(row.IsFullCombo);
        PillText.Foreground = ScoreBadge.Text(row.IsFullCombo);
        PillText.FontStyle = ScoreBadge.Style(row.IsFullCombo);
        ScoreText.Text = row.Score;
        AutomationProperties.SetName(RowButton, row.Announcement);
        AutomationProperties.SetAutomationId(RowButton, row.AutomationId);
        RowButton.IsHitTestVisible = RowButton.IsTabStop = row.Route is not null;
        Chevron.Visibility = row.Route is not null ? Visibility.Visible : Visibility.Collapsed;
        // The selected player's row is bold throughout (web isPlayer; operator batch 6.42).
        var weight = row.IsSelected ? Microsoft.UI.Text.FontWeights.Bold : Microsoft.UI.Text.FontWeights.Normal;
        RankText.FontWeight = NameText.FontWeight = SeasonText.FontWeight = PillText.FontWeight = weight;
        ScoreText.FontWeight = row.IsSelected ? Microsoft.UI.Text.FontWeights.Bold : Microsoft.UI.Text.FontWeights.SemiBold;
        UpdateRankWidth();
        UpdateSeparator();
        if (row.IsSelected)
        {
            var accent = (Windows.UI.Color)Application.Current.Resources["FSTAccentPurpleColor"];
            RowButton.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x2E, accent.R, accent.G, accent.B));
            RowButton.BorderBrush = (Brush)Application.Current.Resources["FSTAccentPurpleBrush"];
        }
        else
        {
            RowButton.Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            RowButton.BorderBrush = RowButton.Background;
        }
    }

    /// <summary>Collapses season and stars below <see cref="WideWidth"/> and drops the column minimums below
    /// <see cref="CompactWidth"/> so rank, name, accuracy and score all stay visible.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">New size.</param>
    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var wide = e.NewSize.Width >= WideWidth;
        var visibility = wide ? Visibility.Visible : Visibility.Collapsed;
        if (SeasonText.Visibility != visibility) SeasonText.Visibility = StarsHost.Visibility = visibility;
        compact = e.NewSize.Width < CompactWidth;
        RowGrid.ColumnSpacing = compact ? 8 : 12;
        UpdateRankWidth();
        PillColumn.MinWidth = compact ? 0 : 72;
    }

    /// <summary>Compact-row threshold in effective pixels.</summary>
    private const double CompactWidth = 400;

    /// <summary>Opens Statistics for the selected player, otherwise the player's profile.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (Row?.Route is { } route) MainWindow.Instance?.Navigate(route);
    }
}
#endregion
