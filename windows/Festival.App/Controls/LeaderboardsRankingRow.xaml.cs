using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Rankings row
/// <summary>
/// A rankings row for either an account (<see cref="RankingRowViewModel"/>) or a band (<see cref="BandRankingRowViewModel"/>).
/// Set in code rather than x:Bind so one lightweight control serves both row types inside virtualized repeaters.
/// </summary>
public sealed partial class LeaderboardsRankingRow : UserControl, ISeparatedRow
{
    /// <summary>Rank column width per character, epx (web <c>Layout.rankCharWidth</c>).</summary>
    private const double RankCharWidth = 8.5;

    /// <summary>Narrowest rank column ("#1" to "#10" share it), epx.</summary>
    private const double MinRankWidth = 28;

    private bool separatorWanted;
    private bool selected;
    private bool current;

    /// <summary>Row model: <see cref="RankingRowViewModel"/> or <see cref="BandRankingRowViewModel"/>.</summary>
    public static readonly DependencyProperty RowProperty = DependencyProperty.Register(
        nameof(Row), typeof(object), typeof(LeaderboardsRankingRow), new PropertyMetadata(null, (d, _) => ((LeaderboardsRankingRow)d).Update()));

    /// <summary>Creates the row.</summary>
    public LeaderboardsRankingRow()
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

    /// <inheritdoc />
    public bool ShowSeparator
    {
        set
        {
            separatorWanted = value;
            UpdateSeparator();
        }
    }

    /// <summary>
    /// Whether this row's destination is showing in the page's detail column (list + detail layout): a subtle fill so the
    /// list shows which player the detail belongs to. The selected player's own accent wins.
    /// </summary>
    public bool IsCurrent
    {
        get => current;
        set
        {
            if (current == value) return;
            current = value;
            ApplyFill();
        }
    }

    /// <summary>The row's destination (a player profile or Band Detail), if it has one.</summary>
    public AppRoute? Route => route;

    /// <summary>Destination for the current row.</summary>
    private AppRoute? route;

    /// <summary>Projects the model into the template.</summary>
    private void Update()
    {
        switch (Row)
        {
            case RankingRowViewModel account:
                Apply(account.RankText, account.Name, account.SongsText, account.RatingText, account.BayesianText, account.Announcement,
                    account.AutomationId, account.IsSelected);
                route = account.Route;
                break;
            case BandRankingRowViewModel band:
                Apply(band.RankText, band.Name, band.SongsText, band.RatingText, band.BayesianText, band.Announcement,
                    band.AutomationId, false);
                route = band.Route;
                break;
        }
        // Rows without a usable identity (production serves some empty account IDs) are shown but not interactive.
        RowButton.IsHitTestVisible = RowButton.IsTabStop = route is not null;
    }

    /// <summary>Writes texts, accessibility and the selected-player accent.</summary>
    /// <param name="rank">Rank text.</param>
    /// <param name="name">Name or roster.</param>
    /// <param name="songs">Songs subtitle.</param>
    /// <param name="rating">Rating.</param>
    /// <param name="bayesian">Bayesian value or empty.</param>
    /// <param name="announcement">UIA name.</param>
    /// <param name="automationId">UIA ID.</param>
    /// <param name="selected">Whether it is the selected player's row.</param>
    private void Apply(string rank, string name, string songs, string rating, string bayesian, string announcement,
        string automationId, bool selected)
    {
        RankText.Text = rank;
        NameText.Text = name;
        SongsText.Text = songs;
        RatingText.Text = rating;
        BayesianText.Text = bayesian;
        BayesianText.Visibility = bayesian.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        AutomationProperties.SetName(RowButton, announcement);
        AutomationProperties.SetAutomationId(RowButton, automationId);
        // Ranks of equal length share a width, so names line up down a card or page (web computeRankWidth).
        RankColumn.MinWidth = Math.Max(MinRankWidth, Math.Ceiling(rank.Length * RankCharWidth));
        // The selected player's row is bold throughout (web RankingEntry isPlayer; operator batch 6.42).
        var weight = selected ? Microsoft.UI.Text.FontWeights.Bold : Microsoft.UI.Text.FontWeights.Normal;
        RankText.FontWeight = NameText.FontWeight = SongsText.FontWeight = BayesianText.FontWeight = weight;
        RatingText.FontWeight = selected ? Microsoft.UI.Text.FontWeights.Bold : Microsoft.UI.Text.FontWeights.SemiBold;
        this.selected = selected;
        UpdateSeparator();
        ApplyFill();
    }

    /// <summary>Accent fill and border for the selected player, a subtle fill for the row shown in a detail column.</summary>
    private void ApplyFill()
    {
        if (selected)
        {
            var accent = (Windows.UI.Color)Application.Current.Resources["FSTAccentPurpleColor"];
            RowButton.Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x2E, accent.R, accent.G, accent.B));
            RowButton.BorderBrush = (Brush)Application.Current.Resources["FSTAccentPurpleBrush"];
            return;
        }
        RowButton.Background = current ? (Brush)Application.Current.Resources["FSTRowHoverBrush"] : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
        RowButton.BorderBrush = current ? (Brush)Application.Current.Resources["FSTCardStrokeBrush"] : new SolidColorBrush(Microsoft.UI.Colors.Transparent);
    }

    /// <summary>Shows the hairline above a non-first row, except over the selected row's own accent border.</summary>
    private void UpdateSeparator() =>
        Separator.Visibility = separatorWanted && !selected ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>Opens the player profile or Band Detail.</summary>
    /// <param name="sender">Button.</param>
    /// <param name="e">Unused.</param>
    private void OnClick(object sender, RoutedEventArgs e)
    {
        if (route is null) return;
        for (DependencyObject? node = this; node is not null; node = VisualTreeHelper.GetParent(node))
            if (node is IRouteHost host && host.TryShow(route)) return;
        MainWindow.Instance?.Navigate(route);
    }
}
#endregion
