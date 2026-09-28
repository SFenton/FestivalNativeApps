using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Song leaderboard row
/// <summary>One solo chart row; season and stars collapse below 520 epx so rank, name, accuracy and score stay readable.</summary>
public sealed partial class LeaderboardsSongRow : UserControl
{
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

    /// <summary>Projects the model into the template.</summary>
    private void Update()
    {
        if (Row is not { } row) return;
        RankText.Text = row.RankText;
        NameText.Text = row.Name;
        SeasonText.Text = row.Season;
        StarsText.Text = row.Stars;
        PillText.Text = row.AccuracyPill;
        Pill.Visibility = row.HasAccuracy ? Visibility.Visible : Visibility.Collapsed;
        ScoreText.Text = row.Score;
        AutomationProperties.SetName(RowButton, row.Announcement);
        AutomationProperties.SetAutomationId(RowButton, row.AutomationId);
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

    /// <summary>Collapses secondary columns at narrow widths.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">New size.</param>
    private void OnSizeChanged(object sender, SizeChangedEventArgs e)
    {
        var wide = e.NewSize.Width >= WideWidth;
        var visibility = wide ? Visibility.Visible : Visibility.Collapsed;
        if (SeasonText.Visibility == visibility) return;
        SeasonText.Visibility = StarsText.Visibility = visibility;
    }

    /// <summary>Opens Statistics for the selected player, otherwise the player's profile.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (Row is { } row) MainWindow.Instance?.Navigate(row.Route);
    }
}
#endregion
