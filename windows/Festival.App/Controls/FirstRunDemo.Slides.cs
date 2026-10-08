using System.Diagnostics;
using Festival.App.Services;
using Microsoft.UI;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.UI;
using Windows.UI.ViewManagement;

namespace Festival.App.Controls;

#region First-run demo slides
/// <summary>
/// The 42 first-run slide demos (issue #380). Each one is built from the controls and layout of the page it introduces
/// (<see cref="SongRowCard"/>, <see cref="LeaderboardEntryRow"/>, <see cref="SuggestionSongRow"/>, <see cref="RivalRowView"/>,
/// <see cref="PlayerStatTileView"/>, Fluent menus, radio groups, expanders and the navigation pane), staggered in with the
/// web's <c>FadeIn</c> timings (<see cref="FirstRunEntrance"/>), and made inert: no hit testing, no tab stops and a Raw
/// accessibility view, because the slide's title and description carry its meaning.
/// </summary>
public sealed partial class FirstRunDemo
{
    private const string DemoArtist = "Epic Games";
    private const int DemoSeason = 12;

    /// <summary>The four core charts the demos' instrument selectors and chips show.</summary>
    private static readonly Instrument[] DemoInstruments = [Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals];

    private readonly List<UIElement> staged = [];
    private bool inertQueued;
    private bool inertHooked;

    /// <summary>Marks a part whose Loaded re-walk is already hooked.</summary>
    private static readonly DependencyProperty InertHookedProperty = DependencyProperty.RegisterAttached(
        "InertHooked", typeof(bool), typeof(FirstRunDemo), new PropertyMetadata(false));

    #region Build
    /// <summary>Builds the demo for the slide.</summary>
    private void Build()
    {
        // Finish swaps on the rows being discarded before they go.
        CompleteSwaps();
        StopAutoScroll();
        root.Children.Clear();
        slots.Clear();
        slotSetters.Clear();
        pulseRings.Clear();
        pulseFills.Clear();
        staged.Clear();
        scroller = null;
        scrollFade = null;
        advance = null;
        activeInterval = FirstRunDemoTiming.Interval;
        step = 0;
        swaps = 0;
        lastSwapFaded = false;
        kind = FirstRunDemos.KindFor(SlideId);
        if (kind is not { } k || SlideId is not { } id) return;
        songs = SongPoolFor(k);
        AutomationProperties.SetAutomationId(this, $"fst.first-run.demo.{id}");
        artLoads?.Cancel();
        artLoads = new CancellationTokenSource();
        switch (id)
        {
            case "songs-song-list": BuildSongList(SongRowDecoration.None); break;
            case "songs-icons": BuildSongList(SongRowDecoration.Chips); break;
            case "songs-metadata": BuildSongList(SongRowDecoration.Metadata); break;
            case "songs-sort": BuildSongsSort(); break;
            case "songs-navigation": BuildNavigation(); break;
            case "songs-filter": BuildSongsFilter(); break;
            case "songs-shop-highlight":
            case "songs-new-in-shop":
            case "songs-leaving-tomorrow":
            case "shop-highlighting":
            case "shop-new-items":
            case "shop-leaving-tomorrow":
                BuildShopRows(id);
                break;
            case "shop-overview": BuildShopTiles(); break;
            case "songinfo-chart": BuildChart(selectable: false); break;
            case "songinfo-bar-select": BuildChart(selectable: true); break;
            case "songinfo-view-all": BuildScoreCard(history: true); break;
            case "songinfo-top-scores": BuildScoreCard(history: false); break;
            case "songinfo-paths": BuildPaths(); break;
            case "songinfo-shop-button": BuildSongHeaderButtons(null); break;
            case "songinfo-new-in-shop": BuildSongHeaderButtons(ShopHighlight.New); break;
            case "songinfo-leaving-tomorrow": BuildSongHeaderButtons(ShopHighlight.LeavingTomorrow); break;
            case "playerhistory-score-list": BuildHistoryList(); break;
            case "playerhistory-sort": BuildHistorySort(); break;
            case "statistics-select-profile": BuildProfilePicker(); break;
            case "statistics-drill-down":
            case "statistics-overview":
                BuildStatTiles(id, header: false);
                break;
            case "statistics-instrument-breakdown": BuildStatTiles(id, header: true); break;
            case "statistics-percentiles": BuildPercentiles(); break;
            case "statistics-top-songs": BuildTopSongs(); break;
            case "suggestions-category-card": BuildSuggestionCard(); break;
            case "suggestions-global-filter": BuildSuggestionsGeneralFilter(); break;
            case "suggestions-instrument-filter": BuildSuggestionsInstrumentFilter(); break;
            case "suggestions-infinite-scroll": BuildInfiniteScroll(); break;
            case "leaderboards-overview":
            case "compete-leaderboards":
                BuildRankingsCard(id, yourRank: false);
                break;
            case "leaderboards-your-rank": BuildRankingsCard(id, yourRank: true); break;
            case "leaderboards-experimental-metrics": BuildExperimentalMetrics(); break;
            case "compete-hub": BuildCompeteHub(); break;
            case "compete-rivals":
            case "rivals-overview":
                BuildRivalsSection();
                break;
            case "rivals-instruments": BuildInstrumentRivals(); break;
            case "rivals-detail": BuildRivalDetail(); break;
        }
        MakeInert();
        if (active) PlayEntrance();
        else SyncEntranceVisibility();
        PublishStatus();
    }
    #endregion

    #region Songs
    /// <summary>What a Songs demo row shows after its title.</summary>
    private enum SongRowDecoration
    {
        /// <summary>Nothing (a signed-out Songs row).</summary>
        None,
        /// <summary>Instrument status chips.</summary>
        Chips,
        /// <summary>Two metadata pills.</summary>
        Metadata,
    }

    /// <summary>
    /// Songs rows (<c>songs-song-list</c>, <c>songs-icons</c>, <c>songs-metadata</c>): the real <see cref="SongRowCard"/>
    /// with instrument chips or metadata pills, swapping songs with the web's row rotation.
    /// </summary>
    /// <param name="decoration">Trailing content.</param>
    private void BuildSongList(SongRowDecoration decoration)
    {
        var rotation = new FirstRunRowRotation<FirstRunDemoSong>(songs, FirstRunDemos.RowCount);
        for (var i = 0; i < FirstRunDemos.RowCount; i++)
        {
            var (host, card, set) = SongCard();
            var row = i;
            Action<int> setter = poolIndex =>
            {
                var song = songs[poolIndex % songs.Count];
                set(song);
                card.Trailing.Children.Clear();
                if (decoration == SongRowDecoration.Chips)
                {
                    var charts = DemoInstruments;
                    var states = FirstRunDemoScorePattern.States(song.Row.Title, charts.Length);
                    for (var c = 0; c < charts.Length; c++)
                        card.Trailing.Children.Add(SongRowVisuals.Chip(new SongInstrumentBadge(charts[c], Status(states[c])), song.SongId ?? "demo", false));
                }
                else if (decoration == SongRowDecoration.Metadata)
                {
                    var metadata = FirstRunDemos.MetaData[poolIndex % FirstRunDemos.MetaData.Count];
                    var layout = FirstRunDemos.MetadataLayouts[(poolIndex + row) % FirstRunDemos.MetadataLayouts.Count];
                    foreach (var field in FirstRunDemoContent.MetadataFields(metadata, layout))
                        card.Trailing.Children.Add(SongRowVisuals.Pill(field, song.SongId));
                }
            };
            setter(i);
            AddSlot(host, setter);
        }
        advance = _ =>
        {
            var indices = rotation.NextSwap();
            if (indices.Count == 0) return;
            rotation.Replace(indices);
            foreach (var rowIndex in indices) FadeSwap(rowIndex, SongPoolIndex(rotation.Rows[rowIndex]));
            QueueInert();
        };
    }

    /// <summary>Maps the web icon pattern to a Songs chip status.</summary>
    /// <param name="state">Pattern state.</param>
    /// <returns>Status.</returns>
    private static SongInstrumentStatus Status(FirstRunDemoScorePattern.State state) => state switch
    {
        FirstRunDemoScorePattern.State.FullCombo => SongInstrumentStatus.FullCombo,
        FirstRunDemoScorePattern.State.Scored => SongInstrumentStatus.Scored,
        _ => SongInstrumentStatus.NoScore,
    };

    /// <summary>
    /// Songs Sort (web <c>SortDemo</c>): the page's Sort drop-down button, then its open flyout with the Sort By and
    /// Direction radio groups side by side.
    /// </summary>
    private void BuildSongsSort()
    {
        Stage(new DropDownButton { Content = GlyphLabel("\uE8CB", "Title"), HorizontalAlignment = HorizontalAlignment.Right });
        var modes = SongSortModeInfo.ModesFor(false, false, App.Session.Settings.HideShop).Take(4).Select(m => (object)m.Label()).ToList();
        var sortBy = new RadioButtons { Header = "Sort By", ItemsSource = modes, SelectedIndex = 0 };
        var direction = new RadioButtons
        {
            Header = "Direction",
            ItemsSource = new List<object> { DirectionOption("\uE74A", "Ascending", "A–Z, low–high"), DirectionOption("\uE74B", "Descending", "Z–A, high–low") },
            SelectedIndex = 0,
        };
        var columns = new Grid { ColumnSpacing = 24 };
        columns.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        columns.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        columns.Children.Add(sortBy);
        Grid.SetColumn(direction, 1);
        columns.Children.Add(direction);
        var content = new StackPanel { Spacing = 12 };
        content.Children.Add(new TextBlock { Text = "Sort Songs", Style = S("FSTSectionHeaderStyle"), Margin = new Thickness(0) });
        content.Children.Add(columns);
        Stage(FlyoutSurface(content));
    }

    /// <summary>A Direction radio item: arrow glyph, label and range caption.</summary>
    /// <param name="glyph">Arrow glyph.</param>
    /// <param name="label">Label.</param>
    /// <param name="caption">Range caption.</param>
    /// <returns>Item content.</returns>
    private static StackPanel DirectionOption(string glyph, string label, string caption)
    {
        var text = new StackPanel();
        text.Children.Add(new TextBlock { Text = label });
        text.Children.Add(new TextBlock { Text = caption, FontSize = 12, Foreground = B("FSTSecondaryTextBrush") });
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        row.Children.Add(new FontIcon { Glyph = glyph, FontSize = 14, VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(text);
        return row;
    }

    /// <summary>
    /// Navigation (web <c>NavigationDemo</c> sidebar): the app's own left <see cref="NavigationView"/> pane with the
    /// sections a signed-in player sees, Songs selected and Settings at the foot.
    /// </summary>
    private void BuildNavigation()
    {
        var nav = new NavigationView
        {
            PaneDisplayMode = NavigationViewPaneDisplayMode.Left,
            IsBackButtonVisible = NavigationViewBackButtonVisible.Collapsed,
            IsPaneToggleButtonVisible = false,
            IsSettingsVisible = true,
            IsPaneOpen = true,
            OpenPaneLength = 240,
            Height = 300,
            HorizontalAlignment = HorizontalAlignment.Center,
            Width = 240,
        };
        NavigationViewItem? first = null;
        foreach (var section in AppSections.Visible(true, App.Session.Settings.HideShop).Where(s => s != AppSection.Settings))
        {
            var item = new NavigationViewItem { Content = section.Label(), Icon = new FontIcon { Glyph = MainWindow.Glyph(section) } };
            first ??= item;
            nav.MenuItems.Add(item);
        }
        nav.SelectedItem = first;
        Stage(nav);
    }

    /// <summary>
    /// Songs Filter (web <c>FilterDemo</c>): the filter sheet's Selected Instrument Filters selector, then its bucket
    /// expanders (Season, Percentile, Stars, Song Intensity).
    /// </summary>
    private void BuildSongsFilter()
    {
        var top = new StackPanel { Spacing = 8 };
        top.Children.Add(Heading("Selected Instrument Filters", "Choose an instrument to filter by its scores."));
        top.Children.Add(new InstrumentSelector { Instruments = DemoInstruments, Selected = Instrument.Lead, IdPrefix = $"fst.first-run.demo.{SlideId}.instrument" });
        Stage(top);
        var buckets = new StackPanel { Spacing = 4 };
        foreach (var bucket in SongBuckets.All)
        {
            buckets.Children.Add(new Expander
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Header = Heading(bucket.Title(), bucket.Hint(), new Thickness(0, 8, 0, 8)),
            });
        }
        Stage(buckets);
    }
    #endregion

    #region Item Shop
    /// <summary>
    /// Shop-highlight rows: Songs rows (<c>songs-*</c>) with the Item Shop bag and pulse ring, or Item Shop list rows
    /// (<c>shop-*</c>) with the New / Leaving Tomorrow badge and the open-in-Shop button (web <c>ShopHighlightDemo</c>,
    /// <c>NewInShopDemo</c>, <c>LeavingTomorrowDemo</c>).
    /// </summary>
    /// <param name="id">Slide ID.</param>
    private void BuildShopRows(string id)
    {
        var shopPage = id.StartsWith("shop-", StringComparison.Ordinal);
        var rows = FirstRunDemos.RowCount;
        for (var i = 0; i < rows; i++)
        {
            var (host, card, set) = SongCard();
            var pulse = FirstRunShopPattern.Pulse(id, i, rows);
            card.ApplyShop(pulse, showBag: !shopPage);
            if (pulse is not null) pulseRings.Add(card.PulseRing);
            if (shopPage)
            {
                if (FirstRunShopPattern.Badge(id, i, rows) is { } badge) card.Trailing.Children.Add(ShopBadge(badge));
                card.Trailing.Children.Add(new Button
                {
                    Width = 44, Height = 44, Padding = new Thickness(0), CornerRadius = new CornerRadius(22),
                    Content = new FontIcon { Glyph = "\uE719", FontSize = 16 },
                });
            }
            set(songs[i % songs.Count]);
            Stage(host);
        }
    }

    /// <summary>The Item Shop list badge (New on the accent surface, Leaving Tomorrow in red).</summary>
    /// <param name="highlight">Highlight.</param>
    /// <returns>Badge.</returns>
    private static Border ShopBadge(ShopHighlight highlight)
    {
        var leaving = highlight == ShopHighlight.LeavingTomorrow;
        return new Border
        {
            Padding = new Thickness(8, 2, 8, 2), CornerRadius = new CornerRadius(10), VerticalAlignment = VerticalAlignment.Center,
            Background = B(leaving ? "FSTShopLeavingBrush" : "FSTShopNewBadgeSurfaceBrush"),
            Child = new TextBlock
            {
                Text = highlight.Label(), FontSize = 12, FontWeight = Microsoft.UI.Text.FontWeights.Bold,
                Foreground = B(leaving ? "FSTShopBadgeTextBrush" : "FSTShopNewBrush"),
            },
        };
    }

    /// <summary>
    /// Item Shop overview (web <c>ShopOverviewDemo</c>): the page's grid tiles (art, caption scrim, badge, pulse ring) at
    /// their real 200 epx size, scaled to the frame.
    /// </summary>
    private void BuildShopTiles()
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 16 };
        for (var i = 0; i < 3; i++)
        {
            var song = songs[i % songs.Count];
            var highlight = FirstRunShopPattern.Tile(i);
            var art = new Image { Stretch = Stretch.UniformToFill };
            var tile = new Grid { Width = 200, Height = 200, CornerRadius = new CornerRadius(8), Background = B("FSTSurfaceMutedBrush") };
            tile.Children.Add(art);
            tile.Children.Add(new Rectangle
            {
                Fill = new LinearGradientBrush
                {
                    StartPoint = new Windows.Foundation.Point(0, 0), EndPoint = new Windows.Foundation.Point(0, 1),
                    GradientStops =
                    {
                        new GradientStop { Color = Color.FromArgb(0, 0, 0, 0), Offset = 0.55 },
                        new GradientStop { Color = Color.FromArgb(0xCC, 0, 0, 0), Offset = 1 },
                    },
                },
            });
            var caption = new StackPanel { Padding = new Thickness(16), Spacing = 4 };
            if (song.IsPlaceholder)
            {
                caption.Children.Add(RedactedBar(120, 14));
                caption.Children.Add(RedactedBar(80, 10));
            }
            else
            {
                caption.Children.Add(new TextBlock
                {
                    Text = song.Row.Title, Style = S("BodyStrongTextBlockStyle"), FontSize = 16, Foreground = B("FSTShopTileTextBrush"),
                    TextTrimming = TextTrimming.CharacterEllipsis,
                });
                caption.Children.Add(new TextBlock
                {
                    Text = song.Row.Detail, Style = S("BodyTextBlockStyle"), Foreground = B("FSTShopTileTextBrush"),
                    TextTrimming = TextTrimming.CharacterEllipsis, TextWrapping = TextWrapping.NoWrap,
                });
            }
            tile.Children.Add(new Border { VerticalAlignment = VerticalAlignment.Bottom, Background = B("FSTShopTileCaptionBrush"), Child = caption });
            if (highlight is { } h)
            {
                var badge = ShopBadge(h);
                badge.HorizontalAlignment = HorizontalAlignment.Right;
                badge.VerticalAlignment = VerticalAlignment.Top;
                badge.Margin = new Thickness(16);
                badge.Padding = new Thickness(8, 3, 8, 3);
                tile.Children.Add(badge);
                var ring = new ShopPulseRing { Live = active };
                ring.Apply(SongRowShopPulse.For(true, h));
                pulseRings.Add(ring);
                tile.Children.Add(ring);
            }
            LoadArt(art, song.Art, 200);
            row.Children.Add(tile);
        }
        Stage(new Viewbox { Child = row, Stretch = Stretch.Uniform, MaxHeight = 200 });
    }
    #endregion

    #region Song Detail
    /// <summary>
    /// Score History chart (web <c>ChartDemo</c>/<c>BarSelectDemo</c>): the Song Detail chart's axes, accuracy bars, gold
    /// FC bar, score line and date labels; <c>songinfo-bar-select</c> moves the selection every 2.5 s and fades the real
    /// detail row under it.
    /// </summary>
    /// <param name="selectable">Whether the selection cycles.</param>
    private void BuildChart(bool selectable)
    {
        var today = DateTimeOffset.Now;
        var canvas = new Canvas { Height = selectable ? 150 : 200 };
        var selected = FirstRunDemos.BarSelectBars.Count - 1;
        void Draw() => DrawChart(canvas, FirstRunDemoContent.ChartBars(today, selectable ? selected : null));
        canvas.SizeChanged += (_, _) => Draw();
        Stage(canvas);
        if (!selectable) return;
        var detail = new LeaderboardEntryRow { Row = FirstRunDemoContent.ChartDetail(today, selected) };
        Stage(detail);
        slots.Add(detail);
        activeInterval = FirstRunDemoTiming.BarSelect;
        void Select(int index)
        {
            selected = index % FirstRunDemos.BarSelectBars.Count;
            Draw();
            detail.Row = FirstRunDemoContent.ChartDetail(today, selected);
            QueueInert();
        }
        advance = _ => Fade(detail, () => Select(selected + 1), FirstRunDemoTiming.BarSelectFade);
    }

    /// <summary>Draws the Song Detail chart replica (same geometry and brushes as <see cref="SongScoreHistoryChart"/>).</summary>
    /// <param name="plot">Canvas.</param>
    /// <param name="bars">Bars.</param>
    private static void DrawChart(Canvas plot, IReadOnlyList<ScoreHistoryBar> bars)
    {
        plot.Children.Clear();
        var width = plot.ActualWidth;
        if (width <= 0 || bars.Count == 0) return;
        const double left = 44, right = 40, topPad = 8, labelBand = 22;
        var plotWidth = width - left - right;
        var plotHeight = plot.Height - topPad - labelBand;
        var bottom = topPad + plotHeight;
        var niceMax = ScoreHistoryChartScale.NiceMax(bars.Max(b => b.Point.Score));
        var axis = ContrastTheme.Brush("FSTChartAxisBrush");
        void Line(double x1, double y1, double x2, double y2) => plot.Children.Add(new Microsoft.UI.Xaml.Shapes.Line { X1 = x1, Y1 = y1, X2 = x2, Y2 = y2, Stroke = axis, StrokeThickness = 1 });
        void Label(string text, double x, double y, double w, TextAlignment alignment)
        {
            var block = new TextBlock { Text = text, FontSize = 12, Width = Math.Max(0, w), TextAlignment = alignment, TextWrapping = TextWrapping.NoWrap };
            Canvas.SetLeft(block, x);
            Canvas.SetTop(block, y);
            plot.Children.Add(block);
        }
        Line(left, topPad, left, bottom);
        Line(left + plotWidth, topPad, left + plotWidth, bottom);
        Line(left, bottom, left + plotWidth, bottom);
        for (var i = 0; i <= 4; i += 2)
        {
            Label(ScoreHistoryChartScale.Tick(niceMax * i / 4.0), 0, bottom - plotHeight * i / 4 - 8, left - 6, TextAlignment.Right);
            Label($"{25 * i}%", left + plotWidth + 6, bottom - (plotHeight - 4) * i / 4 - 8, right - 6, TextAlignment.Left);
        }
        var lineBrush = ContrastTheme.Brush("FSTChartLineBrush");
        var contrast = ContrastTheme.IsOn;
        var slot = plotWidth / bars.Count;
        var barWidth = Math.Max(4, slot * 0.8);
        var line = new Polyline { Stroke = lineBrush, StrokeThickness = 2 };
        var dots = new List<Ellipse>();
        foreach (var bar in bars)
        {
            var point = bar.Point;
            var centre = left + slot * (bar.Index + 0.5);
            var height = Math.Max(2, (plotHeight - 4) * point.AccuracyPercent / 100);
            Brush fill;
            if (point.IsGold) fill = ContrastTheme.Brush("FSTChartFcBrush");
            else if (contrast) fill = ContrastTheme.Brush("FSTChartBarBrush");
            else
            {
                var (r, g, b) = SongScoreHistory.AccuracyColor(point.AccuracyPercent);
                fill = new SolidColorBrush(ColorHelper.FromArgb(0xFF, r, g, b));
            }
            var rect = new Border
            {
                Width = barWidth, Height = height, CornerRadius = new CornerRadius(4, 4, 0, 0), Background = fill,
                BorderBrush = bar.IsSelected ? ContrastTheme.Brush("FSTChartSelectedStrokeBrush") : null,
                BorderThickness = new Thickness(bar.IsSelected ? 3 : 0),
            };
            Canvas.SetLeft(rect, centre - barWidth / 2);
            Canvas.SetTop(rect, bottom - height);
            plot.Children.Add(rect);
            Label(point.DateLabel, centre - slot / 2, bottom + 4, slot, TextAlignment.Center);
            var y = bottom - plotHeight * point.Score / (double)niceMax;
            line.Points.Add(new Windows.Foundation.Point(centre, y));
            var dot = new Ellipse { Width = 8, Height = 8, Fill = lineBrush };
            Canvas.SetLeft(dot, centre - 4);
            Canvas.SetTop(dot, y - 4);
            dots.Add(dot);
        }
        plot.Children.Add(line);
        foreach (var dot in dots) plot.Children.Add(dot);
    }

    /// <summary>
    /// Song Detail score cards: Score History (web <c>ViewAllDemo</c>: the player's plays, best highlighted, then a pulsing
    /// View All Scores) or the leaderboard's Top Scores (web <c>TopScoresDemo</c>, then a pulsing View Full Leaderboard).
    /// </summary>
    /// <param name="history">Score History instead of Top Scores.</param>
    private void BuildScoreCard(bool history)
    {
        var id = SlideId ?? "";
        Stage(new CardHeader
        {
            Title = history ? "Score History" : "Lead Leaderboard",
            Subtitle = history ? "Your best Lead plays" : "Top Lead scores",
            IconFile = Instrument.Lead.IconFile(),
            HeadingLevel = AutomationHeadingLevel.Level3,
            MinHeight = 44,
        });
        IEnumerable<object> rows = history
            ? FirstRunDemoContent.History(id, 3, DateTimeOffset.Now, DemoSeason)
            : FirstRunDemoContent.TopScores(id).Take(3);
        foreach (var row in rows) Stage(new LeaderboardEntryRow { Row = row });
        Stage(PulsingButton(history ? "View All Scores" : "View Full Leaderboard"));
    }

    /// <summary>The page's View All button inside the web <c>pulseWrap</c> accent ring.</summary>
    /// <param name="text">Label.</param>
    /// <returns>Host.</returns>
    private Grid PulsingButton(string text)
    {
        var host = new Grid();
        host.Children.Add(new Button { Content = text, Style = S("FSTViewAllButtonStyle") });
        var ring = new ShopPulseRing { Live = active, Margin = new Thickness(-3, 1, -3, -3) };
        ring.Apply(FirstRunDemoContent.ViewAllPulse);
        pulseRings.Add(ring);
        host.Children.Add(ring);
        return host;
    }

    /// <summary>
    /// Paths (web <c>PathPreviewDemo</c>): the Paths dialog's instrument selector, Difficulty and Display radio groups,
    /// then its path image area (no path image is fetched for the demo).
    /// </summary>
    private void BuildPaths()
    {
        Stage(new InstrumentSelector
        {
            Instruments = DemoInstruments,
            Selected = Instrument.Lead,
            Required = true,
            IdPrefix = $"fst.first-run.demo.{SlideId}.instrument",
        });
        var pickers = new FlowPanel { Spacing = 20, HorizontalAlignment = HorizontalAlignment.Center };
        pickers.Children.Add(new RadioButtons
        {
            Header = "Difficulty", MaxColumns = 4, SelectedIndex = 3,
            ItemsSource = PathDifficultyInfo.All.Select(d => (object)d.Label()).ToList(),
        });
        pickers.Children.Add(new RadioButtons { Header = "Display", MaxColumns = 2, SelectedIndex = 0, ItemsSource = new List<object> { "Image", "Text" } });
        Stage(pickers);
        var image = new Border
        {
            Height = 48, CornerRadius = new CornerRadius(8), Background = B("FSTSurfaceMutedBrush"),
            Child = new FontIcon { Glyph = "\uE707", FontSize = 20, Foreground = B("FSTSecondaryTextBrush") },
        };
        Stage(image);
    }

    /// <summary>
    /// Song Detail header actions (web <c>ShopButtonDemo</c>, <c>NewInShopDemo</c>, <c>LeavingTomorrowDemo</c>): the
    /// song header, then Paths and the Item Shop button whose fill breathes in its Shop colour.
    /// </summary>
    /// <param name="highlight">Shop highlight (none for a plain in-Shop song).</param>
    private void BuildSongHeaderButtons(ShopHighlight? highlight)
    {
        var song = songs[0];
        var art = new Image { Stretch = Stretch.UniformToFill };
        var header = new Grid { ColumnSpacing = 16 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(72) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.Children.Add(new Border { Width = 72, Height = 72, CornerRadius = new CornerRadius(8), Background = B("FSTSurfaceMutedBrush"), Child = art });
        FrameworkElement text = song.IsPlaceholder
            ? new StackPanel { Spacing = 8, VerticalAlignment = VerticalAlignment.Center, Children = { RedactedBar(180, 20), RedactedBar(110, 12) } }
            : new SongHeaderText
            {
                Title = song.Row.Title, Artist = song.Row.Detail, VerticalAlignment = VerticalAlignment.Center,
                TitleStyle = S("TitleLargeTextBlockStyle"), ArtistStyle = S("FSTMarqueeSongHeaderArtistStyle"),
            };
        Grid.SetColumn(text, 1);
        header.Children.Add(text);
        LoadArt(art, song.Art, 72);
        Stage(header);

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center };
        buttons.Children.Add(new Button { Style = S("AccentButtonStyle"), Content = GlyphLabel("\uE707", "Paths") });
        var fill = new ShopPulseFill { Live = active };
        fill.Apply(highlight, breathe: true);
        pulseFills.Add(fill);
        var shopContent = new Grid();
        shopContent.Children.Add(fill);
        var label = GlyphLabel("\uE719", "Item Shop");
        label.Padding = new Thickness(11, 5, 11, 6);
        shopContent.Children.Add(label);
        buttons.Children.Add(new Button
        {
            Padding = new Thickness(0), Background = B("FSTShopButtonSurfaceBrush"), Foreground = B("FSTShopBadgeTextBrush"), Content = shopContent,
        });
        Stage(buttons);
    }
    #endregion

    #region Player history
    /// <summary>Score History list (web <c>ScoreListDemo</c>): the page's real rows, newest first, best highlighted.</summary>
    private void BuildHistoryList()
    {
        foreach (var row in FirstRunDemoContent.History(SlideId ?? "", 4, DateTimeOffset.Now, DemoSeason))
            Stage(new LeaderboardEntryRow { Row = row });
    }

    /// <summary>
    /// Score History sort (web <c>HistorySortDemo</c>): the page's Sort drop-down button, then its open menu of radio
    /// items (Date, Score, Accuracy, Season; Ascending, Descending) and Reset.
    /// </summary>
    private void BuildHistorySort()
    {
        Stage(new DropDownButton { Content = GlyphLabel("\uE8CB", "Date"), HorizontalAlignment = HorizontalAlignment.Right });
        var menu = new StackPanel();
        foreach (var (text, i) in new[] { "Date", "Score", "Accuracy", "Season" }.Select((t, i) => (t, i)))
            menu.Children.Add(new RadioMenuFlyoutItem { Text = text, GroupName = "first-run-sort", IsChecked = i == 0 });
        menu.Children.Add(MenuDivider());
        menu.Children.Add(new RadioMenuFlyoutItem { Text = "Ascending", GroupName = "first-run-direction" });
        menu.Children.Add(new RadioMenuFlyoutItem { Text = "Descending", GroupName = "first-run-direction", IsChecked = true });
        menu.Children.Add(MenuDivider());
        menu.Children.Add(new MenuFlyoutItem { Text = "Reset" });
        var surface = MenuSurface(menu);
        surface.HorizontalAlignment = HorizontalAlignment.Right;
        Stage(surface);
    }
    #endregion

    #region Statistics
    /// <summary>
    /// Select a profile (web <c>SelectProfileDemo</c>, the player page's <c>SelectProfilePill</c>): the player page's title
    /// row, the player's name as its H1 over the accent Select Profile button.
    /// </summary>
    private void BuildProfilePicker()
    {
        var row = new StackPanel { Spacing = 12, HorizontalAlignment = HorizontalAlignment.Center };
        row.Children.Add(new TextBlock { Text = "KeyDrifter", Style = S("FSTPageTitleStyle"), HorizontalAlignment = HorizontalAlignment.Center });
        row.Children.Add(new Button
        {
            Content = "Select Profile", Style = S("AccentButtonStyle"), MinHeight = (double)Application.Current.Resources["FSTMinTargetSize"],
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        Stage(row);
    }
    /// <summary>
    /// Statistics tiles (web <c>OverviewDemo</c>, <c>DrillDownDemo</c>, <c>InstrumentBreakdownDemo</c>): the page's stat
    /// tiles in two columns; linked tiles pulse on the drill-down slide, and the breakdown sits under its instrument header.
    /// </summary>
    /// <param name="id">Slide.</param>
    /// <param name="header">Whether the Lead instrument header leads.</param>
    private void BuildStatTiles(string id, bool header)
    {
        if (header)
        {
            var title = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
            title.Children.Add(new InstrumentIcon { File = Instrument.Lead.IconFile(), Label = Instrument.Lead.Label(), Width = 36, Height = 36 });
            title.Children.Add(new TextBlock { Text = Instrument.Lead.Label(), Style = S("FSTSectionHeaderStyle"), Margin = new Thickness(0), VerticalAlignment = VerticalAlignment.Center });
            Stage(title);
        }
        var tiles = FirstRunDemoContent.StatTiles(id);
        for (var i = 0; i < tiles.Count; i += 2)
        {
            var row = new Grid { ColumnSpacing = 8 };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            for (var c = 0; c < 2 && i + c < tiles.Count; c++)
            {
                var tile = tiles[i + c];
                tile.Scope = "first-run";
                var cell = new Grid { MinHeight = 88 };
                cell.Children.Add(new PlayerStatTileView { Tile = tile });
                if (FirstRunDemoContent.TilePulses(id, tile))
                {
                    var ring = new ShopPulseRing { Live = active, Margin = new Thickness(-3) };
                    ring.Apply(FirstRunDemoContent.ViewAllPulse);
                    pulseRings.Add(ring);
                    cell.Children.Add(ring);
                }
                Grid.SetColumn(cell, c);
                row.Children.Add(cell);
            }
            Stage(row);
        }
    }

    /// <summary>Percentiles (web <c>PercentileDemo</c>): the page's Percentiles table card.</summary>
    private void BuildPercentiles()
    {
        var head = new Grid { Padding = new Thickness(16, 12, 16, 12), BorderBrush = B("FSTCardStrokeBrush"), BorderThickness = new Thickness(0, 0, 0, 1) };
        head.Children.Add(CapsLabel("PERCENTILE", HorizontalAlignment.Left));
        head.Children.Add(CapsLabel("SONGS", HorizontalAlignment.Right));
        var list = new StackPanel();
        list.Children.Add(head);
        foreach (var bucket in FirstRunDemoContent.PercentileBuckets.Take(4))
        {
            list.Children.Add(new Border
            {
                BorderBrush = B("FSTCardStrokeBrush"), BorderThickness = new Thickness(0, 0, 0, 1),
                Child = new PlayerPercentileRowView { Row = new PlayerPercentileRow(bucket, Instrument.Lead) },
            });
        }
        var card = new Border { Style = S("FSTCardStyle"), Padding = new Thickness(0), Child = list };
        Stage(card);
    }

    /// <summary>An uppercase table column label.</summary>
    /// <param name="text">Text.</param>
    /// <param name="alignment">Alignment.</param>
    /// <returns>Label.</returns>
    private static TextBlock CapsLabel(string text, HorizontalAlignment alignment) => new()
    {
        Text = text, FontSize = 12, FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, CharacterSpacing = 60,
        Foreground = B("FSTSecondaryTextBrush"), HorizontalAlignment = alignment,
    };

    /// <summary>
    /// Highest and lowest rank breakdown (web <c>TopSongsDemo</c>): Songs rows whose songs rotate under fixed percentile
    /// pills (web <c>fitRows</c>: up to four). Each pill is a raw-view <c>fst.first-run.demo.statistics-top-songs.pill.N</c> whose ItemStatus turns from
    /// "initial" to "rotated" once its own row's song has swapped.
    /// </summary>
    private void BuildTopSongs()
    {
        var demo = new FirstRunTopSongsDemo(songs);
        for (var slot = 0; slot < FirstRunTopSongsDemo.SlotCount; slot++)
        {
            var (host, card, set) = SongCard();
            var pill = SongRowVisuals.Pill(FirstRunDemoContent.TopSongPill(slot));
            AutomationProperties.SetAutomationId(pill, $"fst.first-run.demo.{SlideId}.pill.{slot}");
            AutomationProperties.SetItemStatus(pill, "initial");
            card.Trailing.Children.Add(pill);
            set(demo.Songs[slot]);
            AddSlot(host, poolIndex =>
            {
                set(songs[poolIndex % songs.Count]);
                AutomationProperties.SetItemStatus(pill, "rotated");
            });
        }
        advance = _ =>
        {
            foreach (var slot in demo.Advance())
                if (slot < slots.Count) FadeSwap(slot, SongPoolIndex(demo.Songs[slot]));
        };
    }
    #endregion

    #region Suggestions
    /// <summary>
    /// A Suggestions category card (web <c>CategoryCardDemo</c>): header with title, description and instrument icon over
    /// a card of the page's suggestion rows.
    /// </summary>
    /// <param name="template">Template.</param>
    /// <param name="first">First song in the pool.</param>
    /// <param name="count">Rows.</param>
    /// <returns>Card.</returns>
    private StackPanel SuggestionCard(FirstRunSuggestionTemplate template, int first, int count)
    {
        var header = new Grid { ColumnSpacing = 12 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel { Spacing = 2 };
        text.Children.Add(new TextBlock { Text = template.Title, Style = S("BodyStrongTextBlockStyle"), FontSize = 16, TextTrimming = TextTrimming.CharacterEllipsis });
        text.Children.Add(new TextBlock { Text = template.Description, FontSize = 12, Foreground = B("FSTSecondaryTextBrush"), TextTrimming = TextTrimming.CharacterEllipsis });
        header.Children.Add(text);
        if (FirstRunDemoContent.HeaderInstrument(template) is { } instrument)
        {
            var icon = new InstrumentIcon { File = instrument.IconFile(), Label = instrument.Label(), Width = 36, Height = 36 };
            Grid.SetColumn(icon, 1);
            header.Children.Add(icon);
        }
        var rows = new StackPanel();
        for (var i = 0; i < count; i++)
        {
            var song = songs[(first + i) % songs.Count];
            var presentation = FirstRunDemoContent.Suggestion(template, song.IsPlaceholder ? "" : song.Row.Title, song.IsPlaceholder ? "" : song.Row.Detail, i);
            rows.Children.Add(new SuggestionSongRow
            {
                Item = new SuggestionRowItem(presentation, new AppRoute.SongDetail(song.SongId ?? "demo"), song.Art,
                    $"fst.first-run.demo.{SlideId}.{template.Key}.{i}", IsFirst: i == 0),
            });
        }
        var card = new StackPanel { Spacing = 8 };
        card.Children.Add(header);
        card.Children.Add(new Border { Style = S("FSTCardStyle"), Padding = new Thickness(0), Child = rows });
        return card;
    }

    /// <summary>Suggestions category card cycling the web templates (fade, 8 epx drop).</summary>
    private void BuildSuggestionCard()
    {
        var host = new Grid();
        var index = 0;
        void Apply(int templateIndex)
        {
            index = templateIndex % FirstRunDemos.SuggestionTemplates.Count;
            host.Children.Clear();
            host.Children.Add(SuggestionCard(FirstRunDemos.SuggestionTemplates[index], index * 2, 2));
            QueueInert();
        }
        Apply(0);
        Stage(host);
        slots.Add(host);
        advance = _ => Fade(host, () => Apply(index + 1), FirstRunDemoTiming.FadeOut, 8);
    }

    /// <summary>Suggestions filter, General (web <c>GlobalFilterDemo</c>): the sheet's General expander and switches.</summary>
    private void BuildSuggestionsGeneralFilter()
    {
        var toggles = new StackPanel();
        foreach (var (type, i) in SuggestionCategoryTypeInfo.All.Take(3).Select((t, i) => (t, i)))
            toggles.Children.Add(TypeToggle(type, i != 1));
        Stage(new Expander
        {
            HorizontalAlignment = HorizontalAlignment.Stretch,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            IsExpanded = true,
            Header = Heading("General", "Toggle broad suggestion types on or off.", new Thickness(0, 8, 0, 8)),
            Content = toggles,
        });
    }

    /// <summary>
    /// Suggestions filter, Instrument-Specific (web <c>InstrumentFilterDemo</c>): heading, the deferred instrument
    /// selector with Lead picked and its per-instrument switches.
    /// </summary>
    private void BuildSuggestionsInstrumentFilter()
    {
        Stage(Heading("Instrument-Specific", "Select an instrument to filter its suggestion types individually."));
        var toggles = new StackPanel { Margin = new Thickness(0, 8, 0, 0) };
        foreach (var (type, i) in SuggestionCategoryTypeInfo.All.Take(2).Select((t, i) => (t, i)))
            toggles.Children.Add(TypeToggle(type, i == 0));
        Stage(new InstrumentSelector
        {
            Instruments = DemoInstruments,
            DeferSelection = true,
            Selected = Instrument.Lead,
            IdPrefix = $"fst.first-run.demo.{SlideId}.instrument",
            DetailContent = toggles,
        });
    }

    /// <summary>A Suggestions filter switch row (label, 12 epx description, label-less switch).</summary>
    /// <param name="type">Type.</param>
    /// <param name="on">Switch state.</param>
    /// <returns>Row.</returns>
    private static Grid TypeToggle(SuggestionCategoryType type, bool on)
    {
        var row = new Grid { ColumnSpacing = 12, MinHeight = 40 };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        text.Children.Add(new TextBlock { Text = type.Label() });
        text.Children.Add(new TextBlock { Text = type.FilterDescription(), FontSize = 12, Foreground = B("FSTSecondaryTextBrush"), TextTrimming = TextTrimming.CharacterEllipsis });
        row.Children.Add(text);
        var toggle = new ToggleSwitch { OnContent = "", OffContent = "", MinWidth = 0, IsOn = on, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(toggle, 1);
        row.Children.Add(toggle);
        return row;
    }
    #endregion

    #region Infinite scroll
    private ScrollViewer? scroller;
    private AutoScrollEdgeFade? scrollFade;
    private DispatcherQueueTimer? scrollTimer;
    private readonly Stopwatch scrollClock = new();
    private UISettings? fadeSettings;

    /// <summary>
    /// Suggestions infinite scroll (web <c>InfiniteScrollDemo</c>): six category cards that scroll down at 30 epx/s,
    /// jump back to the top at the end, and fade 36 epx at an edge while content lies past it. Reduce Motion holds the
    /// list at the top.
    /// </summary>
    private void BuildInfiniteScroll()
    {
        var list = new StackPanel { Spacing = 16 };
        for (var i = 0; i < FirstRunAutoScroll.Cards; i++)
            list.Children.Add(SuggestionCard(FirstRunDemoContent.ScrollTemplates[i], i * FirstRunAutoScroll.SongsPerCard, FirstRunAutoScroll.SongsPerCard));
        var viewer = new ScrollViewer
        {
            Height = 200,
            Content = list,
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollMode = ScrollMode.Disabled,
            VerticalScrollMode = ScrollMode.Enabled,
            ZoomMode = ZoomMode.Disabled,
        };
        var fadeHost = new Grid { IsHitTestVisible = false };
        var frame = new Grid { Height = 200 };
        frame.Children.Add(viewer);
        frame.Children.Add(fadeHost);
        scroller = viewer;
        scrollFade = new AutoScrollEdgeFade(viewer, fadeHost);
        viewer.ViewChanged += (_, _) => UpdateScrollFade();
        viewer.SizeChanged += (_, _) => UpdateScrollFade();
        Stage(frame);
    }

    /// <summary>Runs the scroll clock only on the visible, loaded, foreground slide with motion allowed.</summary>
    private void UpdateAutoScroll()
    {
        if (scroller is not { } viewer) return;
        var run = active && IsLoaded && Motion.Allowed && !Motion.Paused && Motion.Foreground;
        if (!run)
        {
            scrollTimer?.Stop();
            scrollClock.Stop();
            if (!Motion.Allowed)
            {
                scrollClock.Reset();
                viewer.ChangeView(null, 0, null, true);
            }
            UpdateScrollFade();
            return;
        }
        if (scrollTimer is null)
        {
            scrollTimer = DispatcherQueue.CreateTimer();
            scrollTimer.Interval = TimeSpan.FromMilliseconds(16);
            scrollTimer.Tick += (_, _) => TickAutoScroll();
        }
        scrollClock.Start();
        if (!scrollTimer.IsRunning) scrollTimer.Start();
    }

    /// <summary>Moves the list to the web's offset for the elapsed time (wrapping to the top at the end).</summary>
    private void TickAutoScroll()
    {
        if (scroller is not { } viewer) return;
        var range = FirstRunAutoScroll.Range(viewer.ExtentHeight, viewer.ViewportHeight);
        var offset = FirstRunAutoScroll.Offset(scrollClock.Elapsed - FirstRunAutoScroll.StartDelay, range);
        viewer.ChangeView(null, offset, null, true);
    }

    /// <summary>Redraws the edge fades for the list's position (hard edges when fades are disabled).</summary>
    private void UpdateScrollFade()
    {
        if (scroller is not { } viewer || scrollFade is null) return;
        fadeSettings ??= new UISettings();
        var settings = App.Session.Settings;
        var on = SongHeaderEdgeFade.IsEnabled(ContrastTheme.IsOn, fadeSettings.AdvancedEffectsEnabled, settings.LessTransparency, settings.MoreContrast);
        scrollFade.Update(on, viewer.VerticalOffset, FirstRunAutoScroll.Range(viewer.ExtentHeight, viewer.ViewportHeight));
    }

    /// <summary>Stops the scroll clock (rebuild or unload).</summary>
    private void StopAutoScroll()
    {
        scrollTimer?.Stop();
        scrollClock.Reset();
    }
    #endregion

    #region Leaderboards and Compete
    /// <summary>
    /// Leaderboards card (web <c>LeaderboardOverviewDemo</c>, <c>CompeteLeaderboardsDemo</c>, <c>YourRankDemo</c>): the
    /// page's card header and ranking rows, then View All Rankings, or for Your Rank the player's floating row.
    /// </summary>
    /// <param name="id">Slide.</param>
    /// <param name="yourRank">Whether the player's floating row replaces View All.</param>
    private void BuildRankingsCard(string id, bool yourRank)
    {
        Stage(new CardHeader
        {
            Title = Instrument.Lead.Label(),
            Subtitle = "Total Score",
            IconFile = Instrument.Lead.IconFile(),
            HeadingLevel = AutomationHeadingLevel.Level3,
            MinHeight = 44,
        });
        var rankings = yourRank
            ? FirstRunDemoContent.Rankings(FirstRunDemos.Rankings.Take(2).Append(FirstRunDemos.PlayerRanking), id)
            : FirstRunDemoContent.Rankings(FirstRunDemos.Rankings.Take(3), id);
        foreach (var row in rankings)
            Stage(new LeaderboardEntryRow { Row = row, IsFloating = row.IsSelected });
        if (!yourRank) Stage(new Button { Content = "View All Rankings", Style = S("FSTViewAllButtonStyle") });
    }

    /// <summary>
    /// Experimental metrics (web <c>ExperimentalMetricsDemo</c>): the Rank By drop-down button over its open menu; the
    /// checked metric moves every step with no fade, and the caption explains it.
    /// </summary>
    private void BuildExperimentalMetrics()
    {
        var label = new TextBlock { Text = FirstRunDemoContent.Metrics[0].Label() };
        var button = new DropDownButton { HorizontalAlignment = HorizontalAlignment.Right };
        var content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        content.Children.Add(new FontIcon { Glyph = "\uE8CB", FontSize = 14 });
        content.Children.Add(label);
        button.Content = content;
        Stage(button);
        var menu = new StackPanel();
        var items = FirstRunDemoContent.Metrics.Select(m => new RadioMenuFlyoutItem { Text = m.Label(), GroupName = "first-run-metric" }).ToList();
        foreach (var item in items) menu.Children.Add(item);
        var surface = MenuSurface(menu);
        surface.HorizontalAlignment = HorizontalAlignment.Right;
        Stage(surface);
        var caption = new TextBlock { FontSize = 12, Foreground = B("FSTSecondaryTextBrush"), TextWrapping = TextWrapping.Wrap, HorizontalAlignment = HorizontalAlignment.Right };
        Stage(caption);
        void Select(int index)
        {
            var i = index % items.Count;
            for (var n = 0; n < items.Count; n++) items[n].IsChecked = n == i;
            label.Text = FirstRunDemoContent.Metrics[i].Label();
            caption.Text = FirstRunDemos.ExperimentalMetrics[i % FirstRunDemos.ExperimentalMetrics.Count].Description;
        }
        Select(0);
        advance = s =>
        {
            Select(s + 1);
            CountSwap(faded: false);
        };
    }

    /// <summary>Compete hub (web <c>CompeteHubDemo</c>): the Leaderboards card and the Rivals card alternate (fade, 6 epx rise).</summary>
    private void BuildCompeteHub()
    {
        var host = new Grid();
        var mode = 0;
        void Apply(int next)
        {
            mode = next % 2;
            host.Children.Clear();
            var panel = new StackPanel { Spacing = 4 };
            if (mode == 0)
            {
                panel.Children.Add(new CardHeader { Title = "Leaderboards", Subtitle = "Lead · Total Score", IconFile = Instrument.Lead.IconFile(), HeadingLevel = AutomationHeadingLevel.Level3, MinHeight = 44 });
                foreach (var row in FirstRunDemoContent.Rankings(FirstRunDemos.Rankings.Take(2).Append(FirstRunDemos.PlayerRanking), SlideId ?? ""))
                    panel.Children.Add(new LeaderboardEntryRow { Row = row, IsFloating = row.IsSelected });
            }
            else
            {
                panel.Children.Add(new CardHeader { Title = "Rivals", Subtitle = "Players just above and below you", IconFile = Instrument.Lead.IconFile(), HeadingLevel = AutomationHeadingLevel.Level3, MinHeight = 44 });
                foreach (var rival in FirstRunDemos.RivalsAbove.Take(2))
                    panel.Children.Add(RivalRow(FirstRunDemoContent.RivalRow(rival, RivalDirection.Above)));
                panel.Children.Add(RivalRow(FirstRunDemoContent.RivalRow(FirstRunDemos.RivalsBelow[0], RivalDirection.Below)));
            }
            host.Children.Add(panel);
            QueueInert();
        }
        Apply(0);
        Stage(host);
        slots.Add(host);
        advance = _ => Fade(host, () => Apply(mode + 1), FirstRunDemoTiming.FadeOut, -6);
    }
    #endregion

    #region Rivals
    /// <summary>A Rivals list row (the page's rival row button and view).</summary>
    /// <param name="item">Row.</param>
    /// <returns>Button.</returns>
    private static LeaderboardRowButton RivalRow(RivalRowItem item) => new()
    {
        Style = S("FSTRivalRowButtonStyle"),
        Content = new RivalRowView { Item = item },
    };

    /// <summary>
    /// Rivals section (web <c>RivalsOverviewDemo</c>, <c>CompeteRivalsDemo</c>): the page's instrument header with View
    /// All, then a card of two rivals above and two below; the halves page through their pools in turn.
    /// </summary>
    private void BuildRivalsSection()
    {
        Stage(SectionHeader(Instrument.Lead, viewAll: true));
        var above = new FirstRunWindowRotation<FirstRunDemoRival>(FirstRunDemos.RivalsAbove, 2);
        var below = new FirstRunWindowRotation<FirstRunDemoRival>(FirstRunDemos.RivalsBelow, 2);
        var aboveRows = new StackPanel { Spacing = 4 };
        var belowRows = new StackPanel { Spacing = 4 };
        void Set(StackPanel panel, IReadOnlyList<FirstRunDemoRival> rivals, RivalDirection direction)
        {
            panel.Children.Clear();
            foreach (var rival in rivals) panel.Children.Add(RivalRow(FirstRunDemoContent.RivalRow(rival, direction)));
            QueueInert();
        }
        Set(aboveRows, above.Rows, RivalDirection.Above);
        Set(belowRows, below.Rows, RivalDirection.Below);
        var stack = new StackPanel { Spacing = 4 };
        stack.Children.Add(aboveRows);
        stack.Children.Add(belowRows);
        Stage(new Border { Style = S("FSTCardStyle"), Padding = new Thickness(8, 8, 8, 12), Child = stack });
        slots.Add(aboveRows);
        slots.Add(belowRows);
        advance = s =>
        {
            if (s % 2 == 0)
            {
                above.Advance();
                Fade(aboveRows, () => Set(aboveRows, above.Rows, RivalDirection.Above), FirstRunDemoTiming.FadeOut, 4);
            }
            else
            {
                below.Advance();
                Fade(belowRows, () => Set(belowRows, below.Rows, RivalDirection.Below), FirstRunDemoTiming.FadeOut, 4);
            }
        };
    }

    /// <summary>A Rivals section header: instrument icon, title and an optional View All link.</summary>
    /// <param name="instrument">Instrument.</param>
    /// <param name="viewAll">Whether View All shows.</param>
    /// <returns>Header.</returns>
    private static Grid SectionHeader(Instrument instrument, bool viewAll)
    {
        var header = new Grid { ColumnSpacing = 12 };
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        header.Children.Add(new InstrumentIcon { File = instrument.IconFile(), Label = instrument.Label(), Width = 36, Height = 36 });
        var title = new TextBlock { Text = instrument.Label(), Style = S("FSTSectionHeaderStyle"), Margin = new Thickness(0), VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(title, 1);
        header.Children.Add(title);
        if (viewAll)
        {
            var link = new HyperlinkButton { Content = "View All", VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(link, 2);
            header.Children.Add(link);
        }
        return header;
    }

    /// <summary>
    /// Rivals per instrument (web <c>RivalsInstrumentsDemo</c>): three instrument sections, each with one rival row that
    /// steps through that instrument's rivals above and below in turn.
    /// </summary>
    private void BuildInstrumentRivals()
    {
        var keys = FirstRunDemos.InstrumentRivals.Keys.ToList();
        var cursors = new int[keys.Count];
        for (var i = 0; i < keys.Count; i++)
        {
            var key = keys[i];
            var (aboveRivals, belowRivals) = FirstRunDemos.InstrumentRivals[key];
            var pool = aboveRivals.Zip(belowRivals, (a, b) => new[] { (a, RivalDirection.Above), (b, RivalDirection.Below) }).SelectMany(p => p).ToList();
            var section = new StackPanel { Spacing = 6 };
            section.Children.Add(SectionHeader(FirstRunDemoContent.RivalInstrument(key), viewAll: false));
            var rowHost = new Grid();
            void Set(int n)
            {
                var (rival, direction) = pool[n % pool.Count];
                rowHost.Children.Clear();
                rowHost.Children.Add(RivalRow(FirstRunDemoContent.RivalRow(rival, direction)));
                QueueInert();
            }
            Set(0);
            section.Children.Add(rowHost);
            Stage(section);
            slots.Add(rowHost);
            slotSetters.Add(Set);
        }
        advance = s =>
        {
            var slot = s % keys.Count;
            cursors[slot]++;
            FadeSwap(slot, cursors[slot]);
        };
    }

    /// <summary>
    /// Rival detail (web <c>RivalDetailDemo</c>): a category title in its sentiment colour, its subtitle and a card of the
    /// page's compact head-to-head song rows; the category changes every step.
    /// </summary>
    private void BuildRivalDetail()
    {
        var categories = FirstRunDemos.RivalDetailCategories.ToList();
        var host = new StackPanel { Spacing = 8 };
        var index = 0;
        void Apply(int next)
        {
            index = next % categories.Count;
            var (title, ranks) = categories[index];
            host.Children.Clear();
            var description = RivalCategorization.Describe(FirstRunDemoContent.RivalCategoryKey(title));
            var heading = new StackPanel();
            heading.Children.Add(new TextBlock
            {
                Text = title, Style = S("SubtitleTextBlockStyle"),
                Foreground = description is { } d ? RivalsUi.Sentiment(d.Sentiment) : B("FSTSecondaryTextBrush"),
            });
            if (description is { } desc)
                heading.Children.Add(new TextBlock { Text = desc.Subtitle, Style = S("CaptionTextBlockStyle"), Foreground = B("FSTSecondaryTextBrush"), TextTrimming = TextTrimming.CharacterEllipsis });
            host.Children.Add(heading);
            var rows = new StackPanel { Spacing = 4 };
            for (var i = 0; i < 3; i++)
            {
                var song = songs[(index + i) % songs.Count];
                var rank = ranks[i % ranks.Count];
                var comparison = new RivalSongComparison(song.SongId ?? $"demo-{i}", song.IsPlaceholder ? "" : song.Row.Title,
                    song.IsPlaceholder ? "" : song.Row.Detail, Instrument.Lead.ServiceId(), null, null,
                    rank.UserRank, rank.RivalRank, rank.RivalRank - rank.UserRank, rank.UserScore, rank.RivalScore);
                var catalogSong = song.SongId is { } songId ? App.Session.Catalog?.Songs.FirstOrDefault(s => s.SongId == songId) : null;
                rows.Children.Add(new Button
                {
                    Style = S("FSTRivalRowButtonStyle"),
                    Content = new RivalSongRowView { Item = new RivalSongItem(comparison, catalogSong, "You", "KeyDrifter"), Compact = true },
                });
            }
            host.Children.Add(new Border { Style = S("FSTCardStyle"), Padding = new Thickness(8), Child = rows });
            QueueInert();
        }
        Apply(0);
        Stage(host);
        slots.Add(host);
        advance = _ => Fade(host, () => Apply(index + 1));
    }
    #endregion

    #region Pieces
    /// <summary>
    /// A Songs row: the real <see cref="SongRowCard"/>, with muted bars over the text area for a placeholder (Fluent's
    /// loading-skeleton look) so a loading row never reads as an untitled song.
    /// </summary>
    /// <returns>Host, card and a song setter.</returns>
    private (Grid Host, SongRowCard Card, Action<FirstRunDemoSong> Set) SongCard()
    {
        var card = new SongRowCard();
        var bars = new StackPanel
        {
            Spacing = 6, Margin = new Thickness(66, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Left, Visibility = Visibility.Collapsed,
        };
        bars.Children.Add(RedactedBar(140, 12));
        bars.Children.Add(RedactedBar(90, 9));
        var host = new Grid();
        host.Children.Add(card);
        host.Children.Add(bars);
        void Set(FirstRunDemoSong song)
        {
            card.Title = song.IsPlaceholder ? "" : song.Row.Title;
            card.Subtitle = song.IsPlaceholder ? "" : song.Row.Detail;
            bars.Visibility = song.IsPlaceholder ? Visibility.Visible : Visibility.Collapsed;
            LoadArt(card.Art, song.Art, SongRowCard.ArtSize);
        }
        return (host, card, Set);
    }

    /// <summary>A muted bar standing in for a placeholder song's text.</summary>
    /// <param name="width">Width in epx.</param>
    /// <param name="height">Height in epx.</param>
    /// <returns>Bar.</returns>
    private static Border RedactedBar(double width, double height) => new()
    {
        Width = width, Height = height, CornerRadius = new CornerRadius(3), HorizontalAlignment = HorizontalAlignment.Left,
        Background = new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF)),
    };

    /// <summary>A section heading: strong title over a 12 epx secondary hint.</summary>
    /// <param name="title">Title.</param>
    /// <param name="hint">Hint.</param>
    /// <param name="padding">Padding.</param>
    /// <returns>Heading.</returns>
    private static StackPanel Heading(string title, string hint, Thickness padding = default)
    {
        var panel = new StackPanel { Padding = padding };
        panel.Children.Add(new TextBlock { Text = title, Style = S("BodyStrongTextBlockStyle") });
        panel.Children.Add(new TextBlock { Text = hint, FontSize = 12, Foreground = B("FSTSecondaryTextBrush"), TextWrapping = TextWrapping.Wrap });
        return panel;
    }

    /// <summary>A glyph and label (drop-down and action button content).</summary>
    /// <param name="glyph">Segoe Fluent Icons glyph.</param>
    /// <param name="text">Label.</param>
    /// <returns>Content.</returns>
    private static StackPanel GlyphLabel(string glyph, string text)
    {
        var panel = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        panel.Children.Add(new FontIcon { Glyph = glyph, FontSize = 14, VerticalAlignment = VerticalAlignment.Center });
        panel.Children.Add(new TextBlock { Text = text, VerticalAlignment = VerticalAlignment.Center });
        return panel;
    }

    /// <summary>An open flyout's surface (the system flyout presenter's fill, stroke, corner and padding).</summary>
    /// <param name="content">Content.</param>
    /// <returns>Surface.</returns>
    private static Border FlyoutSurface(UIElement content) => new()
    {
        Background = B("FlyoutPresenterBackground"),
        BorderBrush = B("FlyoutBorderThemeBrush"),
        BorderThickness = Resource("FlyoutBorderThemeThickness", new Thickness(1)),
        CornerRadius = Resource("OverlayCornerRadius", new CornerRadius(8)),
        Padding = new Thickness(16),
        Child = content,
    };

    /// <summary>An open menu's surface (the system menu presenter's fill, stroke, corner and padding).</summary>
    /// <param name="content">Menu items.</param>
    /// <returns>Surface.</returns>
    private static Border MenuSurface(UIElement content) => new()
    {
        Background = B("MenuFlyoutPresenterBackground"),
        BorderBrush = B("MenuFlyoutPresenterBorderBrush"),
        BorderThickness = Resource("MenuFlyoutPresenterBorderThemeThickness", new Thickness(1)),
        CornerRadius = Resource("OverlayCornerRadius", new CornerRadius(8)),
        Padding = Resource("MenuFlyoutPresenterThemePadding", new Thickness(0, 2, 0, 2)),
        MinWidth = 180,
        Child = content,
    };

    /// <summary>
    /// A menu separator line (a <see cref="MenuFlyoutSeparator"/> outside a menu presenter would be a focusable control).
    /// </summary>
    /// <returns>Divider.</returns>
    private static Rectangle MenuDivider() => new()
    {
        Height = 1, Margin = new Thickness(0, 2, 0, 2), Fill = B("MenuFlyoutSeparatorBackground"),
    };

    /// <summary>An app brush, or a faint white for a missing key.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Brush.</returns>
    private static Brush B(string key) =>
        Application.Current.Resources.TryGetValue(key, out var value) && value is Brush brush ? brush : new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF));

    /// <summary>An app style.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>Style.</returns>
    private static Style S(string key) => (Style)Application.Current.Resources[key];

    /// <summary>A typed app resource, or a fallback.</summary>
    /// <typeparam name="T">Value type.</typeparam>
    /// <param name="key">Resource key.</param>
    /// <param name="fallback">Fallback.</param>
    /// <returns>Value.</returns>
    private static T Resource<T>(string key, T fallback) =>
        Application.Current.Resources.TryGetValue(key, out var value) && value is T typed ? typed : fallback;

    /// <summary>Loads catalogue art through the shared bounded cache (nothing with Save Data or no art).</summary>
    /// <param name="image">Target.</param>
    /// <param name="art">Art reference.</param>
    /// <param name="size">Display size in epx.</param>
    private async void LoadArt(Image image, string? art, double size)
    {
        image.Source = null;
        if (art is null || App.Session.Settings.SaveData || App.Options.NoArt || artLoads is not { } loads) return;
        var pixels = (int)Math.Ceiling(size * (XamlRoot?.RasterizationScale ?? 1.5));
        var bitmap = await ArtworkImages.LoadAsync(art, pixels, loads.Token);
        if (!loads.IsCancellationRequested) image.Source = bitmap;
    }

    /// <summary>Adds a staged element that is also a swappable slot.</summary>
    /// <param name="element">Slot element.</param>
    /// <param name="setter">Content setter taking a pool index.</param>
    private void AddSlot(FrameworkElement element, Action<int> setter)
    {
        Stage(element);
        slots.Add(element);
        slotSetters.Add(setter);
    }

    /// <summary>Adds an entrance-staggered block to the demo.</summary>
    /// <param name="element">Block.</param>
    private void Stage(UIElement element)
    {
        root.Children.Add(element);
        staged.Add(element);
    }

    /// <summary>Finds a song's current pool index.</summary>
    /// <param name="song">Song item.</param>
    /// <returns>Pool index, or 0 if missing.</returns>
    private int SongPoolIndex(FirstRunDemoSong song)
    {
        for (var i = 0; i < songs.Count; i++)
            if (string.Equals(songs[i].Id, song.Id, StringComparison.Ordinal)) return i;
        return 0;
    }
    #endregion

    #region Entrance
    /// <summary>Fades the demo's blocks up one stagger step apart (web <c>FadeIn</c> delays; instant with motion off).</summary>
    private void PlayEntrance()
    {
        var entrance = FirstRunEntrance.For(SlideId);
        for (var i = 0; i < staged.Count; i++) FadeIn.Play(staged[i], entrance.ItemDelay(i));
    }

    /// <summary>
    /// Holds an inactive slide's blocks hidden while motion is allowed, so a slide fades in when it is shown instead of
    /// appearing and then replaying; with motion off every block shows at once.
    /// </summary>
    private void SyncEntranceVisibility()
    {
        foreach (var element in staged)
        {
            if (!active && Motion.Allowed) ElementCompositionPreview.GetElementVisual(element).Opacity = 0;
            else if (!Motion.Allowed) FadeIn.Reset(element);
        }
    }
    #endregion

    #region Inert
    /// <summary>
    /// Makes the demo a picture of the page rather than a second copy of it: no hit testing, no tab stops (Tab goes from
    /// the dialog's text straight to its buttons) and a Raw accessibility view on every part. Templates realize later, so
    /// every part not yet loaded re-walks its own subtree once when it loads.
    /// </summary>
    private void MakeInert()
    {
        root.IsHitTestVisible = false;
        if (!inertHooked)
        {
            // A real control's bring-into-view (a selected item realizing) must not scroll the carousel off its slide.
            root.BringIntoViewRequested += (_, e) => e.Handled = true;
            inertHooked = true;
        }
        QueueInert();
    }

    /// <summary>Walks the demo after its content changed, and once more after the next layout settles.</summary>
    private void QueueInert()
    {
        Inert(root);
        if (inertQueued) return;
        inertQueued = true;
        DispatcherQueue?.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            inertQueued = false;
            Inert(root);
        });
    }

    /// <summary>Walks a part's subtree once its template has realized.</summary>
    /// <param name="sender">The loaded part.</param>
    /// <param name="e">Unused.</param>
    private void OnInertLoaded(object sender, RoutedEventArgs e)
    {
        var element = (FrameworkElement)sender;
        element.Loaded -= OnInertLoaded;
        Inert(element);
    }

    /// <summary>
    /// Clears tab stops and hides one subtree from Narrator. App (<c>fst.</c>) automation IDs are prefixed with the
    /// demo's own, so UI tests never find a demo copy of a real page control; WinUI template-part IDs are left alone (an
    /// Expander re-applies its own and renaming it spins the UI thread).
    /// </summary>
    /// <param name="node">Subtree root.</param>
    private void Inert(DependencyObject node)
    {
        if (node is Control control && control.IsTabStop) control.IsTabStop = false;
        if (node is FrameworkElement { IsLoaded: false } pending && pending.GetValue(InertHookedProperty) is not true)
        {
            pending.SetValue(InertHookedProperty, true);
            pending.Loaded += OnInertLoaded;
        }
        if (node is UIElement element)
        {
            if (AutomationProperties.GetAccessibilityView(element) != AccessibilityView.Raw) AutomationProperties.SetAccessibilityView(element, AccessibilityView.Raw);
            var id = AutomationProperties.GetAutomationId(element);
            if (id.StartsWith("fst.", StringComparison.Ordinal) && !id.StartsWith("fst.first-run.", StringComparison.Ordinal))
                AutomationProperties.SetAutomationId(element, $"fst.first-run.demo.{SlideId}.{id}");
        }
        for (var i = 0; i < VisualTreeHelper.GetChildrenCount(node); i++) Inert(VisualTreeHelper.GetChild(node, i));
    }
    #endregion
}
#endregion
