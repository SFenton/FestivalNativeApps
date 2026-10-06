using System.Numerics;
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

namespace Festival.App.Controls;

#region First-run demo
/// <summary>
/// Live mini-demo for a first-run slide (<see cref="FirstRunDemos"/>): sample rows, chips, bars or tiles built from the
/// app's own brushes, advancing rotating web demos every <see cref="FirstRunDemoTiming.Interval"/>. Motion effects off
/// keeps data rotation but swaps instantly; hidden or inactive windows pause. Decorative for UI Automation: the slide's
/// title and description carry the meaning.
/// </summary>
public sealed partial class FirstRunDemo : UserControl
{
    /// <summary>Slide ID dependency property.</summary>
    public static readonly DependencyProperty SlideIdProperty =
        DependencyProperty.Register(nameof(SlideId), typeof(string), typeof(FirstRunDemo), new PropertyMetadata(null, (d, _) => ((FirstRunDemo)d).Rebuild()));

    private static readonly string[] Letters = ["#", "A", "B", "C", "D", "E", "F"];

    private readonly StackPanel root = new() { Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
    private readonly List<FrameworkElement> slots = [];
    private readonly List<Action<int>> slotSetters = [];
    private IReadOnlyList<FirstRunDemoSong> songs = [];
    private FirstRunDemoKind? kind;
    private DispatcherQueueTimer? timer;
    private CancellationTokenSource? artLoads;
    private Action<int>? advance;
    private readonly List<ActiveSwap> activeSwaps = [];
    private readonly List<ShopPulseRing> pulseRings = [];
    private readonly List<ShopPulseFill> pulseFills = [];
    private TimeSpan activeInterval = FirstRunDemoTiming.Interval;
    private int step;
    private bool active;
    private int swaps;
    private bool lastSwapFaded;

    /// <summary>One in-flight data swap that must complete if the slide deactivates mid-fade.</summary>
    private sealed class ActiveSwap
    {
        public FrameworkElement Element { get; init; } = null!;
        public Action? Change { get; init; }
        public bool Changed { get; set; }
        public List<DispatcherQueueTimer> Timers { get; } = [];
    }

    /// <summary>Creates the demo.</summary>
    public FirstRunDemo()
    {
        Content = root;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        Loaded += (_, _) =>
        {
            // Idempotent: a repeated Loaded (see Unloaded) must not double-subscribe.
            Motion.Changed -= OnMotionChanged;
            App.Session.PropertyChanged -= OnSessionChanged;
            Motion.Changed += OnMotionChanged;
            App.Session.PropertyChanged += OnSessionChanged;
            if (CatalogueNowAvailable) Build();
            UpdateTimer();
        };
        Unloaded += (_, _) =>
        {
            // The FlipView re-hosts realized slides after the dialog lays out, and WinUI then raises a late Unloaded
            // while the demo is still in the live tree (issue #241). Tearing down there left the visible slide
            // unsubscribed from the catalogue (placeholder rows on a slow network), its art cancelled and swaps cut.
            if (IsLoaded) return;
            Motion.Changed -= OnMotionChanged;
            App.Session.PropertyChanged -= OnSessionChanged;
            timer?.Stop();
            CompleteSwaps();
            artLoads?.Cancel();
        };
    }

    /// <summary>
    /// Raw-view peer so UI tests can read the demo's <c>fst.first-run.demo.*</c> AutomationId and ItemStatus
    /// (Narrator still skips it; its decorative children stay as they were).
    /// </summary>
    /// <returns>A framework element peer.</returns>
    protected override AutomationPeer OnCreateAutomationPeer() => new FrameworkElementAutomationPeer(this);

    #region Fit
    private readonly ScaleTransform fit = new();
    private double fitScale = 1;

    /// <summary>
    /// Lays the demo out at the frame's width and, when large text makes it taller than the 210 epx frame, re-lays it
    /// out wider and shrinks it uniformly so every sample row stays whole (issue #241; <see cref="FirstRunDemoFit"/>).
    /// </summary>
    /// <param name="availableSize">Frame size.</param>
    /// <returns>Desired size, never taller than the frame.</returns>
    protected override Windows.Foundation.Size MeasureOverride(Windows.Foundation.Size availableSize)
    {
        var width = availableSize.Width;
        root.Measure(new Windows.Foundation.Size(width, double.PositiveInfinity));
        fitScale = double.IsFinite(width) ? FirstRunDemoFit.Scale(root.DesiredSize.Height, availableSize.Height) : 1;
        if (fitScale < 1) root.Measure(new Windows.Foundation.Size(width / fitScale, double.PositiveInfinity));
        return new Windows.Foundation.Size(
            double.IsFinite(width) ? width : root.DesiredSize.Width,
            Math.Min(root.DesiredSize.Height * fitScale, availableSize.Height));
    }

    /// <summary>Arranges the (possibly re-laid-out) demo in unscaled space, then applies the fit scale.</summary>
    /// <param name="finalSize">Frame size.</param>
    /// <returns><paramref name="finalSize"/>.</returns>
    protected override Windows.Foundation.Size ArrangeOverride(Windows.Foundation.Size finalSize)
    {
        fit.ScaleX = fit.ScaleY = fitScale;
        root.RenderTransform = fitScale < 1 ? fit : null;
        root.Arrange(new Windows.Foundation.Rect(0, 0, finalSize.Width / fitScale, finalSize.Height / fitScale));
        return finalSize;
    }
    #endregion

    /// <summary>
    /// Statistics Top Songs (<see cref="FirstRunTopSongsDemo"/>): four catalogue rows whose songs rotate under fixed
    /// percentile pills. Each pill is a raw-view <c>fst.first-run.demo.statistics-top-songs.pill.N</c> whose ItemStatus
    /// turns from "initial" to "rotated" once its own row's song has swapped, so UI tests can check every pill after a
    /// real swap.
    /// </summary>
    private void BuildTopSongs()
    {
        var demo = new FirstRunTopSongsDemo(songs);
        for (var slot = 0; slot < demo.Songs.Count; slot++)
        {
            var row = SongRow(out var setter);
            var pill = Pill(FirstRunTopSongsDemo.Pill(slot));
            var label = (TextBlock)pill.Child;
            AutomationProperties.SetAutomationId(label, $"fst.first-run.demo.{SlideId}.pill.{slot}");
            AutomationProperties.SetAccessibilityView(label, AccessibilityView.Raw);
            AutomationProperties.SetItemStatus(label, "initial");
            ((StackPanel)((Grid)row.Child).Children[2]).Children.Add(pill);
            setter(slot);
            AddSlot(row, poolIndex =>
            {
                setter(poolIndex);
                AutomationProperties.SetItemStatus(label, "rotated");
            });
        }
        advance = _ =>
        {
            foreach (var slot in demo.Advance()) FadeSwap(slot, SongPoolIndex(demo.Songs[slot]));
        };
    }

    /// <summary>Song Info bar-select demo with a 2.5-second selection clock.</summary>
    private void BuildBarSelect()
    {
        activeInterval = FirstRunDemoTiming.BarSelect;
        var grid = new Grid { Height = 120, ColumnSpacing = 10 };
        var bars = new List<Border>();
        for (var i = 0; i < FirstRunDemos.BarSelectBars.Count; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var sample = FirstRunDemos.BarSelectBars[i];
            var bar = new Border { CornerRadius = new CornerRadius(8), VerticalAlignment = VerticalAlignment.Bottom, Height = Math.Max(24, sample.Accuracy), Background = new SolidColorBrush(sample.FullCombo ? Color.FromArgb(0xFF, 0xFF, 0xD7, 0x00) : Color.FromArgb(0xFF, 0x7C, 0x3A, 0xED)) };
            Grid.SetColumn(bar, i);
            grid.Children.Add(bar);
            bars.Add(bar);
        }
        root.Children.Add(grid);
        var detail = TextRow(out var setDetail);
        root.Children.Add(detail);
        var selected = 0;
        void Select(int index)
        {
            selected = index % FirstRunDemos.BarSelectBars.Count;
            for (var i = 0; i < bars.Count; i++)
            {
                bars[i].BorderThickness = i == selected ? new Thickness(2) : new Thickness(0);
                bars[i].BorderBrush = new SolidColorBrush(i == selected ? Color.FromArgb(0xFF, 0xA7, 0x78, 0xFF) : Colors.Transparent);
            }
            var sample = FirstRunDemos.BarSelectBars[selected];
            setDetail(new FirstRunDemoRow(sample.FullCombo ? "100% FC" : $"{sample.Accuracy}% accuracy", sample.When, sample.Score.ToString("N0", System.Globalization.CultureInfo.InvariantCulture)));
        }
        Select(0);
        slots.Add(detail);
        advance = _ => Fade(detail, () => Select(selected + 1), FirstRunDemoTiming.BarSelectFade);
    }

    /// <summary>Suggestions category card cycling the web templates.</summary>
    private void BuildSuggestionCard()
    {
        var card = new StackPanel { Spacing = 6 };
        var title = Text("", 15, true);
        var desc = Text("", 12, false);
        card.Children.Add(title);
        card.Children.Add(desc);
        var rows = new StackPanel { Spacing = 4 };
        card.Children.Add(rows);
        var host = RowCard(card);
        void Apply(int templateIndex)
        {
            var template = FirstRunDemos.SuggestionTemplates[templateIndex % FirstRunDemos.SuggestionTemplates.Count];
            title.Text = template.Title;
            desc.Text = template.Description;
            rows.Children.Clear();
            var instruments = new[] { "Lead", "Bass", "Drums", "Vocals" };
            for (var i = 0; i < Math.Min(5, songs.Count); i++)
            {
                var song = songs[(templateIndex * 5 + i) % songs.Count];
                var value = template.Key switch
                {
                    "unfc_guitar" => $"{100 - (2 * i)}%",
                    "pct_push_bass" => $"Top {3 + i}%",
                    "near_fc_any" => instruments[i % instruments.Length],
                    _ => template.Instrument,
                };
                rows.Children.Add(SongLine(song, $" · {value}"));
            }
        }
        Apply(0);
        root.Children.Add(host);
        slots.Add(host);
        advance = s => Fade(host, () => Apply((s + 1) % FirstRunDemos.SuggestionTemplates.Count), FirstRunDemoTiming.FadeOut, 8);
    }

    /// <summary>Experimental metric radio list: selection advances with no fade.</summary>
    private void BuildExperimentalMetrics()
    {
        var setters = new List<Action<FirstRunDemoRow>>();
        for (var i = 0; i < FirstRunDemos.ExperimentalMetrics.Count; i++)
        {
            var row = TextRow(out var setter);
            root.Children.Add(row);
            setters.Add(setter);
        }
        void Select(int selected)
        {
            for (var i = 0; i < setters.Count; i++)
            {
                var metric = FirstRunDemos.ExperimentalMetrics[i];
                setters[i](new FirstRunDemoRow(i == selected ? $"● {metric.Title}" : $"○ {metric.Title}", metric.Description));
            }
        }
        Select(0);
        advance = s =>
        {
            Select((s + 1) % FirstRunDemos.ExperimentalMetrics.Count);
            CountSwap(faded: false);
        };
    }

    /// <summary>Compete hub alternates leaderboard and rival summary layouts.</summary>
    private void BuildCompeteHub()
    {
        var host = new StackPanel { Spacing = 5 };
        var border = RowCard(host);
        void Apply(int mode)
        {
            host.Children.Clear();
            if (mode % 2 == 0)
            {
                foreach (var ranking in FirstRunDemos.Rankings.Take(3))
                    host.Children.Add(Text($"#{ranking.Rank} {ranking.DisplayName} · {ranking.RatingLabel}", 13, true));
                host.Children.Add(Text($"#{FirstRunDemos.PlayerRanking.Rank} {FirstRunDemos.PlayerRanking.DisplayName} · {FirstRunDemos.PlayerRanking.RatingLabel}", 13, true));
            }
            else
            {
                foreach (var rival in FirstRunDemos.RivalsAbove.Take(2).Concat(FirstRunDemos.RivalsBelow.Take(2)))
                    host.Children.Add(Text($"{rival.DisplayName} · {Math.Abs(rival.AvgSignedDelta)} pts", 13, true));
            }
        }
        Apply(0);
        root.Children.Add(border);
        slots.Add(border);
        advance = s => Fade(border, () => Apply(s + 1), FirstRunDemoTiming.FadeOut, -6);
    }

    /// <summary>Rivals groups page through above and below windows.</summary>
    private void BuildRivalWindows()
    {
        var aboveRotation = new FirstRunWindowRotation<FirstRunDemoRival>(FirstRunDemos.RivalsAbove, 3);
        var belowRotation = new FirstRunWindowRotation<FirstRunDemoRival>(FirstRunDemos.RivalsBelow, 3);
        var above = RivalGroup("Above", aboveRotation.Rows);
        var below = RivalGroup("Below", belowRotation.Rows);
        root.Children.Add(above.Group);
        root.Children.Add(below.Group);
        slots.Add(above.Group);
        slots.Add(below.Group);
        slotSetters.Add(_ => above.Set(aboveRotation.Rows));
        slotSetters.Add(_ => below.Set(belowRotation.Rows));
        advance = s =>
        {
            if (s % 2 == 0)
            {
                aboveRotation.Advance();
                Fade(above.Group, () => above.Set(aboveRotation.Rows), FirstRunDemoTiming.FadeOut, 4);
            }
            else
            {
                belowRotation.Advance();
                Fade(below.Group, () => below.Set(belowRotation.Rows), FirstRunDemoTiming.FadeOut, 4);
            }
        };
    }

    /// <summary>Rivals instruments swaps two instrument-side slots per tick.</summary>
    private void BuildInstrumentRivals()
    {
        var pool = FirstRunDemos.InstrumentRivals.SelectMany(pair => new[]
        {
            new FirstRunDemoRival($"{pair.Key}-above", $"{pair.Key} ↑ {pair.Value.Above[0].DisplayName}", pair.Value.Above[0].RivalScore, pair.Value.Above[0].SharedSongCount, pair.Value.Above[0].AheadCount, pair.Value.Above[0].BehindCount, pair.Value.Above[0].AvgSignedDelta),
            new FirstRunDemoRival($"{pair.Key}-below", $"{pair.Key} ↓ {pair.Value.Below[0].DisplayName}", pair.Value.Below[0].RivalScore, pair.Value.Below[0].SharedSongCount, pair.Value.Below[0].AheadCount, pair.Value.Below[0].BehindCount, pair.Value.Below[0].AvgSignedDelta),
        }).ToList();
        var rotation = new FirstRunRowRotation<FirstRunDemoRival>(pool.Concat(FirstRunDemos.InstrumentRivals.SelectMany(p => p.Value.Above.Skip(1).Concat(p.Value.Below.Skip(1)))).ToList(), 6);
        for (var i = 0; i < rotation.Rows.Count; i++)
        {
            var row = TextRow(out var setter);
            var slot = i;
            Action<int> set = _ => setter(RivalRow(rotation.Rows[slot]));
            set(0);
            AddSlot(row, set);
        }
        advance = _ =>
        {
            var indices = rotation.NextSwap();
            if (indices.Count == 0) return;
            rotation.Replace(indices);
            foreach (var index in indices) FadeSwap(index, 0);
        };
    }

    /// <summary>Rival detail cycles through category rank-data groups.</summary>
    private void BuildRivalDetail()
    {
        var host = new StackPanel { Spacing = 5 };
        var border = RowCard(host);
        var categories = FirstRunDemos.RivalDetailCategories.ToList();
        void Apply(int index)
        {
            var category = categories[index % categories.Count];
            host.Children.Clear();
            host.Children.Add(Text($"{category.Key} · KeyDrifter", 14, true));
            for (var i = 0; i < category.Value.Count; i++)
            {
                var data = category.Value[i];
                var song = songs[(index + i) % songs.Count];
                host.Children.Add(SongLine(song, $": #{data.UserRank} vs #{data.RivalRank}"));
            }
        }
        Apply(0);
        root.Children.Add(border);
        slots.Add(border);
        advance = s => Fade(border, () => Apply(s + 1));
    }

    /// <summary>Slide ID.</summary>
    public string? SlideId
    {
        get => (string?)GetValue(SlideIdProperty);
        set => SetValue(SlideIdProperty, value);
    }

    /// <summary>Whether this demo's slide is the visible one (set by the carousel).</summary>
    public bool Active
    {
        get => active;
        set
        {
            if (active == value) return;
            active = value;
            UpdateTimer();
        }
    }

    /// <summary>Whether the rows are placeholders while the catalogue could now supply real songs.</summary>
    private bool CatalogueNowAvailable => songs.Count > 0 && songs[0].IsPlaceholder && !SongPoolFor(kind)[0].IsPlaceholder;

    /// <summary>The songs a demo kind rotates through (Shop demos prefer the publication-matched Shop feed).</summary>
    /// <param name="k">Kind, or <see langword="null"/>.</param>
    /// <returns>Pool, placeholders while the catalogue is loading or unavailable.</returns>
    private static IReadOnlyList<FirstRunDemoSong> SongPoolFor(FirstRunDemoKind? k)
    {
        var session = App.Session;
        var shopIds = k is { } kind && FirstRunDemos.UsesShopSongs(kind)
            ? FirstRunDemos.ShopPreference(session.Shop, session.ShopOffersForCatalog, session.Settings.HideShop)
            : [];
        return FirstRunDemos.SongPool(session.Catalog?.Songs, shopIds);
    }

    /// <summary>Swaps placeholders for real songs as soon as the catalogue arrives (even with motion off).</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Changed property.</param>
    private void OnSessionChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(App.Session.Catalog) && CatalogueNowAvailable) Rebuild();
    }

    /// <summary>Rebuilds with the current catalogue, keeping the timer state.</summary>
    private void Rebuild()
    {
        Build();
        UpdateTimer();
    }

    /// <summary>Whether a demo exists for the slide (otherwise the static illustration shows).</summary>
    public bool HasDemo => kind is not null;

    #region Build
    /// <summary>Builds the demo for the slide's kind.</summary>
    private void Build()
    {
        // Finish swaps on the rows being discarded before they go.
        CompleteSwaps();
        root.Children.Clear();
        slots.Clear();
        slotSetters.Clear();
        pulseRings.Clear();
        pulseFills.Clear();
        advance = null;
        activeInterval = FirstRunDemoTiming.Interval;
        step = 0;
        swaps = 0;
        lastSwapFaded = false;
        kind = FirstRunDemos.KindFor(SlideId);
        if (kind is not { } k) return;
        songs = SongPoolFor(k);
        AutomationProperties.SetAutomationId(this, $"fst.first-run.demo.{SlideId}");
        artLoads?.Cancel();
        artLoads = new CancellationTokenSource();
        if (FirstRunDemos.RotationKindFor(SlideId) is { } rotating)
        {
            BuildRotating(rotating);
            PublishStatus();
            return;
        }
        switch (k)
        {
            case FirstRunDemoKind.SongRows:
            case FirstRunDemoKind.Chips:
            case FirstRunDemoKind.Metadata:
            case FirstRunDemoKind.ShopPulse:
            case FirstRunDemoKind.NewPulse:
            case FirstRunDemoKind.LeavingPulse:
                BuildSongRows(k);
                break;
            case FirstRunDemoKind.Sort:
                BuildSort();
                break;
            case FirstRunDemoKind.Filter:
                BuildFilter();
                break;
            case FirstRunDemoKind.Navigation:
                BuildNavigation();
                break;
            case FirstRunDemoKind.Chart:
                BuildChart();
                break;
            case FirstRunDemoKind.Leaderboard:
            case FirstRunDemoKind.YourRank:
                BuildLeaderboard(k == FirstRunDemoKind.YourRank);
                break;
            case FirstRunDemoKind.ActionButton:
                BuildActionButton();
                break;
            case FirstRunDemoKind.Tiles:
                BuildTiles();
                break;
            case FirstRunDemoKind.Rivals:
                BuildRivals();
                break;
            default:
                BuildShopTiles();
                break;
        }
        advance = null;
        PublishStatus();
    }

    /// <summary>Builds one of the twelve web-rotating demos.</summary>
    /// <param name="rotating">Rotating demo kind.</param>
    private void BuildRotating(FirstRunDemoRotationKind rotating)
    {
        switch (rotating)
        {
            case FirstRunDemoRotationKind.SongsSongList:
                BuildSongRows(FirstRunDemoKind.SongRows, rotate: true);
                break;
            case FirstRunDemoRotationKind.SongsIcons:
                BuildSongRows(FirstRunDemoKind.Chips, rotate: true);
                break;
            case FirstRunDemoRotationKind.SongsMetadata:
                BuildSongRows(FirstRunDemoKind.Metadata, rotate: true);
                break;
            case FirstRunDemoRotationKind.StatisticsTopSongs:
                BuildTopSongs();
                break;
            case FirstRunDemoRotationKind.SongInfoBarSelect:
                BuildBarSelect();
                break;
            case FirstRunDemoRotationKind.SuggestionsCategoryCard:
                BuildSuggestionCard();
                break;
            case FirstRunDemoRotationKind.LeaderboardsExperimentalMetrics:
                BuildExperimentalMetrics();
                break;
            case FirstRunDemoRotationKind.CompeteHub:
                BuildCompeteHub();
                break;
            case FirstRunDemoRotationKind.CompeteRivals:
            case FirstRunDemoRotationKind.RivalsOverview:
                BuildRivalWindows();
                break;
            case FirstRunDemoRotationKind.RivalsInstruments:
                BuildInstrumentRivals();
                break;
            default:
                BuildRivalDetail();
                break;
        }
    }

    /// <summary>Song rows; rotating variants use web swap selection. Chips, metadata pills or a Shop pulse decorate them by kind.</summary>
    /// <param name="k">Kind.</param>
    /// <param name="rotate">Whether the web rotates this slide's data.</param>
    /// <param name="rowCount">Visible row count.</param>
    private void BuildSongRows(FirstRunDemoKind k, bool rotate = false, int rowCount = FirstRunDemos.RowCount)
    {
        var rotation = new FirstRunRowRotation<FirstRunDemoSong>(songs, rowCount);
        for (var i = 0; i < rowCount; i++)
        {
            var row = SongRow(out var setter);
            var pulse = k switch
            {
                FirstRunDemoKind.ShopPulse => SongRowShopPulse.InShop,
                FirstRunDemoKind.NewPulse => SongRowShopPulse.New,
                FirstRunDemoKind.LeavingPulse => SongRowShopPulse.Leaving,
                _ => null,
            };
            var trailing = (StackPanel)((Grid)row.Child).Children[2];
            if (k == FirstRunDemoKind.Chips)
            {
                foreach (var (instrument, n) in new[] { Instrument.Lead, Instrument.Bass, Instrument.Drums }.Select((x, n) => (x, n)))
                    trailing.Children.Add(Chip(instrument, SongInstrumentStatus.NoScore));
            }
            var index = i;
            Action<int> set = poolIndex =>
            {
                setter(poolIndex);
                var song = songs[poolIndex % songs.Count];
                if (k == FirstRunDemoKind.Chips)
                {
                    trailing.Children.Clear();
                    var states = FirstRunDemoScorePattern.States(song.Row.Title, 3);
                    foreach (var (instrument, n) in new[] { Instrument.Lead, Instrument.Bass, Instrument.Drums }.Select((x, n) => (x, n)))
                    {
                        var status = states[n] switch
                        {
                            FirstRunDemoScorePattern.State.FullCombo => SongInstrumentStatus.FullCombo,
                            FirstRunDemoScorePattern.State.Scored => SongInstrumentStatus.Scored,
                            _ => SongInstrumentStatus.NoScore,
                        };
                        trailing.Children.Add(Chip(instrument, status));
                    }
                }
                if (k == FirstRunDemoKind.Metadata)
                {
                    trailing.Children.Clear();
                    var metadata = FirstRunDemos.MetaData[poolIndex % FirstRunDemos.MetaData.Count];
                    var layout = FirstRunDemos.MetadataLayouts[(poolIndex + index) % FirstRunDemos.MetadataLayouts.Count];
                    foreach (var pill in FirstRunDemos.MetadataPillsFor(metadata, layout)) trailing.Children.Add(Pill(pill));
                }
            };
            set(i);
            var host = new Grid();
            host.Children.Add(row);
            if (pulse is not null && i == 1)
            {
                var ring = new ShopPulseRing { Live = active };
                pulseRings.Add(ring);
                ring.Apply(pulse);
                host.Children.Add(ring);
                if (k == FirstRunDemoKind.LeavingPulse) trailing.Children.Add(LeavingPill());
            }
            AddSlot(host, set);
        }
        if (!rotate) return;
        advance = _ =>
        {
            var indices = rotation.NextSwap();
            if (indices.Count == 0) return;
            rotation.Replace(indices);
            foreach (var rowIndex in indices)
            {
                var poolIndex = SongPoolIndex(rotation.Rows[rowIndex]);
                FadeSwap(rowIndex, poolIndex);
            }
        };
    }

    /// <summary>Sort: a label and rows whose order flips each step.</summary>
    private void BuildSort()
    {
        var label = Pill("Title ↑");
        root.Children.Add(label);
        var ordered = songs.Take(FirstRunDemos.RowCount).OrderBy(s => s.Row.Title, StringComparer.CurrentCultureIgnoreCase).ToList();
        var rows = new List<Action<int>>();
        for (var i = 0; i < ordered.Count; i++)
        {
            var row = SongRow(out var setter);
            AddSlot(row, setter);
            rows.Add(setter);
        }
        void Apply(bool ascending)
        {
            ((TextBlock)label.Child).Text = ascending ? "Title ↑" : "Title ↓";
            for (var i = 0; i < ordered.Count; i++)
            {
                var song = ordered[ascending ? i : ordered.Count - 1 - i];
                rows[i](songs.ToList().IndexOf(song));
            }
        }
        Apply(true);
        advance = s => FadeAll(() => Apply(s % 2 == 1));
    }

    /// <summary>Filter: a chip naming the active filter and rows that change with it.</summary>
    private void BuildFilter()
    {
        var chip = Pill(FirstRunDemos.FilterChips[0]);
        root.Children.Add(chip);
        BuildSongRows(FirstRunDemoKind.SongRows);
    }

    /// <summary>Navigation: a letter strip whose highlight moves, over song rows.</summary>
    private void BuildNavigation()
    {
        var strip = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 6, HorizontalAlignment = HorizontalAlignment.Center };
        var cells = Letters.Select(l =>
        {
            var cell = new Border { Width = 30, Height = 30, CornerRadius = new CornerRadius(15), Child = Text(l, 13, true, HorizontalAlignment.Center) };
            strip.Children.Add(cell);
            return cell;
        }).ToList();
        root.Children.Add(strip);
        BuildSongRows(FirstRunDemoKind.SongRows);
        void Highlight(int index)
        {
            for (var i = 0; i < cells.Count; i++)
                cells[i].Background = i == index ? Resource("FSTAccentPurpleBrush", Color.FromArgb(0xFF, 0x7C, 0x3A, 0xED)) : Card();
        }
        Highlight(1);
    }

    /// <summary>Chart: score-history bars whose selection moves right each step.</summary>
    private void BuildChart()
    {
        var bars = new Grid { Height = 150, ColumnSpacing = 8 };
        var rects = new List<Rectangle>();
        for (var i = 0; i < FirstRunDemos.Bars.Count; i++)
        {
            bars.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var bar = new Rectangle { RadiusX = 4, RadiusY = 4, VerticalAlignment = VerticalAlignment.Bottom, Height = 150 * FirstRunDemos.Bars[i] };
            Grid.SetColumn(bar, i);
            bars.Children.Add(bar);
            rects.Add(bar);
        }
        root.Children.Add(bars);
        var caption = Text("", 13, true, HorizontalAlignment.Center);
        root.Children.Add(caption);
        void Select(int index)
        {
            for (var i = 0; i < rects.Count; i++)
                rects[i].Fill = i == index ? new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0xD7, 0x00)) : new SolidColorBrush(Color.FromArgb(0xFF, 0x7C, 0x3A, 0xED));
            caption.Text = $"Season {8 + index} · {(int)(FirstRunDemos.Bars[index] * 100)}% · {FirstRunDemos.Players[index % FirstRunDemos.Players.Count].Value}";
        }
        Select(rects.Count - 1);
        advance = s => Select(s % rects.Count);
    }

    /// <summary>Leaderboard rows (and a highlighted "you" row); swaps one row per step.</summary>
    /// <param name="yourRank">Whether to add the selected player's row.</param>
    private void BuildLeaderboard(bool yourRank)
    {
        for (var i = 0; i < FirstRunDemos.RowCount; i++)
        {
            var row = TextRow(out var setter);
            setter(FirstRunDemos.Players[i]);
            AddSlot(row, p => setter(FirstRunDemos.Players[p % FirstRunDemos.Players.Count]));
        }
        if (yourRank)
        {
            var you = TextRow(out var setYou);
            you.BorderBrush = new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0xD7, 0x00));
            you.BorderThickness = new Thickness(2);
            setYou(new FirstRunDemoRow("#1,204 · You", "97.2%", "352,410"));
            root.Children.Add(you);
        }
        advance = s =>
        {
            var (rowIndex, poolIndex) = FirstRunDemos.Swap(s, slots.Count, FirstRunDemos.Players.Count);
            FadeSwap(rowIndex, poolIndex);
        };
    }

    /// <summary>A Song Detail action button in its status colour (Item Shop breathes like the real button).</summary>
    private void BuildActionButton()
    {
        var id = SlideId ?? "";
        var paths = id.Contains("paths", StringComparison.Ordinal);
        var button = new Grid { Height = 44, MinWidth = 200, CornerRadius = new CornerRadius(22), HorizontalAlignment = HorizontalAlignment.Center };
        if (!paths)
        {
            var fill = new ShopPulseFill { Live = active };
            pulseFills.Add(fill);
            fill.Apply(id.Contains("leaving", StringComparison.Ordinal) ? ShopHighlight.LeavingTomorrow
                : id.Contains("new", StringComparison.Ordinal) ? ShopHighlight.New : null, breathe: true);
            button.Children.Add(fill);
        }
        else
        {
            button.Background = Card();
            button.BorderBrush = new SolidColorBrush(Color.FromArgb(0x40, 0xFF, 0xFF, 0xFF));
            button.BorderThickness = new Thickness(1);
        }
        var label = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, HorizontalAlignment = HorizontalAlignment.Center, Padding = new Thickness(20, 0, 20, 0) };
        label.Children.Add(new FontIcon { Glyph = paths ? "" : "", FontSize = 16, Foreground = new SolidColorBrush(Colors.White), VerticalAlignment = VerticalAlignment.Center });
        label.Children.Add(Text(paths ? "View Paths" : "Item Shop", 15, true));
        button.Children.Add(label);
        // The song header the button sits under on Song Detail; the button's own breathe is the motion.
        var header = SongRow(out var setHeader);
        setHeader(0);
        root.Children.Add(header);
        root.Children.Add(button);
    }

    /// <summary>Statistic tiles; one tile's value refreshes per step.</summary>
    private void BuildTiles()
    {
        var grid = new Grid { RowSpacing = 6, ColumnSpacing = 6 };
        for (var c = 0; c < 3; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.RowDefinitions.Add(new RowDefinition());
        grid.RowDefinitions.Add(new RowDefinition());
        for (var i = 0; i < FirstRunDemos.Tiles.Count; i++)
        {
            var value = Text("", 18, true);
            var label = Text("", 12, false);
            var tile = new Border { Background = Card(), CornerRadius = new CornerRadius(8), Padding = new Thickness(10, 8, 10, 8) };
            tile.Child = new StackPanel { Spacing = 2, Children = { value, label } };
            Grid.SetRow(tile, i / 3);
            Grid.SetColumn(tile, i % 3);
            grid.Children.Add(tile);
            var index = i;
            Action<int> set = n =>
            {
                var t = FirstRunDemos.Tiles[(index + n) % FirstRunDemos.Tiles.Count];
                (value.Text, label.Text) = (t.Value, t.Title);
            };
            set(0);
            slots.Add(tile);
            slotSetters.Add(set);
        }
        root.Children.Add(grid);
        advance = s => FadeSwap(s % slots.Count, s + 1);
    }

    /// <summary>Head-to-head rows: you vs a rival, with who leads; the rival swaps per step.</summary>
    private void BuildRivals()
    {
        for (var i = 0; i < FirstRunDemos.RowCount; i++)
        {
            var row = TextRow(out var setter);
            var index = i;
            Action<int> set = n =>
            {
                var rival = FirstRunDemos.Players[(n + index) % FirstRunDemos.Players.Count];
                var name = rival.Title[(rival.Title.IndexOf('·') + 2)..];
                var ahead = (n + index) % 2 == 0;
                setter(new FirstRunDemoRow(name, ahead ? "You lead by 3,120" : "Behind by 1,845", ahead ? "▲" : "▼"));
            };
            set(0);
            AddSlot(row, set);
        }
        advance = s => FadeSwap(s % slots.Count, s + 1);
    }

    /// <summary>Item Shop tiles: art with a title scrim; New pulses gold, Leaving red.</summary>
    private void BuildShopTiles()
    {
        var grid = new Grid { ColumnSpacing = 8 };
        for (var i = 0; i < 3; i++)
        {
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var art = new Image { Stretch = Stretch.UniformToFill };
            var title = Text("", 12, true);
            var titleBar = RedactedBar(70, 10);
            var tile = new Grid { Height = 120, CornerRadius = new CornerRadius(8), Background = Placeholder(i) };
            tile.Children.Add(art);
            tile.Children.Add(new Border
            {
                VerticalAlignment = VerticalAlignment.Bottom, Padding = new Thickness(8, 6, 8, 6), Child = new Grid { Children = { title, titleBar } },
                Background = new SolidColorBrush(Color.FromArgb(0xB3, 0, 0, 0)),
            });
            var ring = new ShopPulseRing { Live = active };
            pulseRings.Add(ring);
            ring.Apply(i == 0 ? SongRowShopPulse.New : i == 2 ? SongRowShopPulse.Leaving : null);
            tile.Children.Add(ring);
            Grid.SetColumn(tile, i);
            grid.Children.Add(tile);
            var seed = i;
            Action<int> set = n =>
            {
                var song = songs[n % songs.Count];
                title.Text = song.Row.Title;
                ShowRedacted(song.IsPlaceholder, [title], [titleBar]);
                tile.Background = song.IsPlaceholder ? Muted() : Placeholder(seed);
                LoadArt(art, song.Art, 160);
            };
            set(i);
            slots.Add(tile);
            slotSetters.Add(set);
        }
        root.Children.Add(grid);
        advance = s =>
        {
            var (rowIndex, poolIndex) = FirstRunDemos.Swap(s, slots.Count, songs.Count);
            FadeSwap(rowIndex, poolIndex);
        };
    }
    #endregion

    #region Pieces
    /// <summary>A song row: art, title, detail, trailing panel.</summary>
    /// <param name="setter">Receives a pool index.</param>
    /// <returns>Row card.</returns>
    private Border SongRow(out Action<int> setter)
    {
        var art = new Image { Stretch = Stretch.UniformToFill };
        var artHost = new Border { Width = 36, Height = 36, CornerRadius = new CornerRadius(6), Child = art };
        var title = Text("", 14, true);
        var detail = Text("", 12, false);
        var titleBar = RedactedBar(140, 12);
        var detailBar = RedactedBar(90, 9);
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Children = { title, detail, titleBar, detailBar } };
        Grid.SetColumn(text, 1);
        var trailing = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 4, VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(trailing, 2);
        grid.Children.Add(artHost);
        grid.Children.Add(text);
        grid.Children.Add(trailing);
        setter = index =>
        {
            var song = songs[index % songs.Count];
            (title.Text, detail.Text) = (song.Row.Title, song.Row.Detail);
            ShowRedacted(song.IsPlaceholder, [title, detail], [titleBar, detailBar]);
            artHost.Background = song.IsPlaceholder ? Muted() : Placeholder(index);
            LoadArt(art, song.Art, 36);
        };
        return RowCard(grid);
    }

    /// <summary>
    /// A muted bar standing in for a placeholder song's text (Fluent's loading-skeleton look; WinUI has no redaction
    /// primitive).
    /// </summary>
    /// <param name="width">Bar width in epx.</param>
    /// <param name="height">Bar height in epx.</param>
    /// <returns>Bar, collapsed until shown.</returns>
    private static Border RedactedBar(double width, double height) => new()
    {
        Width = width, Height = height, CornerRadius = new CornerRadius(3), Margin = new Thickness(0, 3, 0, 3),
        HorizontalAlignment = HorizontalAlignment.Left, Background = Muted(), Visibility = Visibility.Collapsed,
    };

    /// <summary>Shows a placeholder's redacted bars instead of its text, or the text of a real song.</summary>
    /// <param name="placeholder">Whether the song is a placeholder.</param>
    /// <param name="text">Text blocks.</param>
    /// <param name="bars">Redacted bars.</param>
    private static void ShowRedacted(bool placeholder, TextBlock[] text, Border[] bars)
    {
        foreach (var t in text) t.Visibility = placeholder ? Visibility.Collapsed : Visibility.Visible;
        foreach (var b in bars) b.Visibility = placeholder ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>Muted fill for placeholder art and text bars.</summary>
    /// <returns>Brush.</returns>
    private static SolidColorBrush Muted() => new(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF));

    /// <summary>
    /// A one-line song mention inside a card (Suggestions, Rival detail): the title followed by <paramref name="suffix"/>,
    /// or a redacted bar before it for a placeholder, so loading rows never read as an untitled song.
    /// </summary>
    /// <param name="song">Song or placeholder.</param>
    /// <param name="suffix">Trailing text such as " · 98%".</param>
    /// <returns>Line element.</returns>
    private static FrameworkElement SongLine(FirstRunDemoSong song, string suffix)
    {
        if (!song.IsPlaceholder) return Text(song.Row.Title + suffix, 12, false);
        var bar = RedactedBar(90, 9);
        bar.Visibility = Visibility.Visible;
        bar.VerticalAlignment = VerticalAlignment.Center;
        bar.Margin = new Thickness(0, 3, 4, 3);
        return new StackPanel { Orientation = Orientation.Horizontal, Children = { bar, Text(suffix, 12, false) } };
    }

    /// <summary>A text row: title, detail and a trailing value.</summary>
    /// <param name="setter">Receives a row.</param>
    /// <returns>Row card.</returns>
    private static Border TextRow(out Action<FirstRunDemoRow> setter)
    {
        var title = Text("", 14, true);
        var detail = Text("", 12, false);
        var value = Text("", 14, true);
        var grid = new Grid { ColumnSpacing = 10 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new StackPanel { VerticalAlignment = VerticalAlignment.Center, Children = { title, detail } });
        value.VerticalAlignment = VerticalAlignment.Center;
        Grid.SetColumn(value, 1);
        grid.Children.Add(value);
        setter = row => (title.Text, detail.Text, value.Text) = (row.Title, row.Detail, row.Value);
        return RowCard(grid);
    }

    /// <summary>Card chrome for a row.</summary>
    /// <param name="content">Row content.</param>
    /// <returns>Card.</returns>
    private static Border RowCard(UIElement content) => new()
    {
        Background = Card(), CornerRadius = new CornerRadius(8), Padding = new Thickness(10, 6, 10, 6), MinHeight = 48,
        BorderBrush = new SolidColorBrush(Color.FromArgb(0x14, 0xFF, 0xFF, 0xFF)), BorderThickness = new Thickness(1), Child = content,
    };

    /// <summary>A status chip (instrument icon in a status ring).</summary>
    /// <param name="instrument">Chart.</param>
    /// <param name="status">Status.</param>
    /// <returns>Chip.</returns>
    private static Border Chip(Instrument instrument, SongInstrumentStatus status) => new()
    {
        Width = 28, Height = 28, CornerRadius = new CornerRadius(14), BorderThickness = new Thickness(2),
        BorderBrush = new SolidColorBrush(status switch
        {
            SongInstrumentStatus.FullCombo => Color.FromArgb(0xFF, 0xFF, 0xD7, 0x00),
            SongInstrumentStatus.Scored => Color.FromArgb(0xFF, 0x2E, 0xCC, 0x71),
            _ => Color.FromArgb(0xFF, 0xEF, 0x44, 0x44),
        }),
        Child = new InstrumentIcon { File = instrument.IconFile(), Label = instrument.Label(), Width = 18, Height = 18 },
    };

    /// <summary>A small rounded label.</summary>
    /// <param name="text">Text.</param>
    /// <returns>Pill.</returns>
    private static Border Pill(string text) => new()
    {
        Background = new SolidColorBrush(Color.FromArgb(0x33, 0xFF, 0xFF, 0xFF)), CornerRadius = new CornerRadius(10),
        Padding = new Thickness(8, 2, 8, 2), HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center,
        Child = Text(text, 12, true),
    };

    /// <summary>The red Leaving Tomorrow pill.</summary>
    /// <returns>Pill.</returns>
    private static Border LeavingPill()
    {
        var pill = Pill("Leaving Tomorrow");
        pill.Background = new SolidColorBrush(Color.FromArgb(0xFF, 0xEF, 0x44, 0x44));
        return pill;
    }

    /// <summary>White demo text (large text sizes are fitted to the frame by the demo's measure pass).</summary>
    /// <param name="text">Text.</param>
    /// <param name="size">Font size.</param>
    /// <param name="bold">Semibold.</param>
    /// <param name="alignment">Horizontal alignment.</param>
    /// <returns>Text block.</returns>
    private static TextBlock Text(string text, double size, bool bold, HorizontalAlignment alignment = HorizontalAlignment.Left) => new()
    {
        Text = text, FontSize = size, Foreground = new SolidColorBrush(Colors.White), TextTrimming = TextTrimming.CharacterEllipsis,
        FontWeight = bold ? Microsoft.UI.Text.FontWeights.SemiBold : Microsoft.UI.Text.FontWeights.Normal,
        HorizontalAlignment = alignment, VerticalAlignment = VerticalAlignment.Center,
    };

    /// <summary>Card surface.</summary>
    /// <returns>Brush.</returns>
    private static Brush Card() => Resource("FSTCardSurfaceBrush", Color.FromArgb(0xC7, 0x12, 0x18, 0x26));

    /// <summary>An app brush, or a fallback colour.</summary>
    /// <param name="key">Resource key.</param>
    /// <param name="fallback">Fallback.</param>
    /// <returns>Brush.</returns>
    private static Brush Resource(string key, Color fallback) =>
        Application.Current.Resources.TryGetValue(key, out var value) && value is Brush brush ? brush : new SolidColorBrush(fallback);

    /// <summary>Brand gradient behind a real song's art (or instead of it with Save Data).</summary>
    /// <param name="seed">Variation.</param>
    /// <returns>Brush.</returns>
    private static LinearGradientBrush Placeholder(int seed) => new()
    {
        StartPoint = new Windows.Foundation.Point(0, 0),
        EndPoint = new Windows.Foundation.Point(1, 1),
        GradientStops =
        {
            new GradientStop { Color = Color.FromArgb(0xFF, 0x2A, 0x1A, 0x5E), Offset = 0 },
            new GradientStop { Color = seed % 2 == 0 ? Color.FromArgb(0xFF, 0x0E, 0x6B, 0x8A) : Color.FromArgb(0xFF, 0x8A, 0x1E, 0x5A), Offset = 1 },
        },
    };

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

    /// <summary>Registers a swappable slot.</summary>
    /// <param name="element">Slot element.</param>
    /// <param name="setter">Content setter taking a pool index.</param>
    private void AddSlot(FrameworkElement element, Action<int> setter)
    {
        root.Children.Add(element);
        slots.Add(element);
        slotSetters.Add(setter);
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

    /// <summary>Builds a rival row projection.</summary>
    /// <param name="rival">Rival.</param>
    /// <returns>Text row.</returns>
    private static FirstRunDemoRow RivalRow(FirstRunDemoRival rival) =>
        new(rival.DisplayName, $"{rival.SharedSongCount} shared · {rival.AheadCount}/{rival.BehindCount}", rival.AvgSignedDelta >= 0 ? $"▲ {rival.AvgSignedDelta}" : $"▼ {Math.Abs(rival.AvgSignedDelta)}");

    /// <summary>Builds a titled rival group with a setter.</summary>
    /// <param name="title">Group title.</param>
    /// <param name="initial">Initial rivals.</param>
    /// <returns>Group and setter.</returns>
    private static (Border Group, Action<IReadOnlyList<FirstRunDemoRival>> Set) RivalGroup(string title, IReadOnlyList<FirstRunDemoRival> initial)
    {
        var stack = new StackPanel { Spacing = 4 };
        var border = RowCard(stack);
        void Set(IReadOnlyList<FirstRunDemoRival> rows)
        {
            stack.Children.Clear();
            stack.Children.Add(Text(title, 13, true));
            foreach (var rival in rows) stack.Children.Add(Text($"{rival.DisplayName} · {rival.SharedSongCount} songs", 12, false));
        }
        Set(initial);
        return (border, Set);
    }
    #endregion

    #region Motion
    /// <summary>Re-evaluates the timer when motion settings, window visibility or window activation change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e) => UpdateTimer();

    /// <summary>Runs the step timer only for the visible foreground slide; motion-off swaps are instant.</summary>
    private void UpdateTimer()
    {
        // Shop pulses breathe only on the visible slide (iOS #28): FlipView keeps neighbours realized off-screen.
        foreach (var ring in pulseRings) ring.Live = active;
        foreach (var fill in pulseFills) fill.Live = active;
        var run = RotationState == FirstRunDemoRotationState.Running;
        if (!run)
        {
            timer?.Stop();
            CompleteSwaps();
            PublishStatus();
            return;
        }
        if (timer is null)
        {
            timer = DispatcherQueue.CreateTimer();
            timer.Interval = FirstRunDemos.Cycle;
            timer.Tick += (_, _) =>
            {
                advance?.Invoke(step++);
                PublishStatus();
            };
        }
        timer.Interval = activeInterval;
        if (!timer.IsRunning) timer.Start();
        PublishStatus();
    }

    /// <summary>The rotation gate: only <see cref="FirstRunDemoRotationState.Running"/> runs the swap clock.</summary>
    private FirstRunDemoRotationState RotationState =>
        FirstRunDemoRotationStatus.State(advance is not null, active, IsLoaded, Motion.Paused, Motion.Foreground);

    /// <summary>Publishes the data and rotation state as the raw-view peer's ItemStatus for UI tests.</summary>
    private void PublishStatus()
    {
        if (kind is null) return;
        AutomationProperties.SetItemStatus(this, FirstRunDemoRotationStatus.Format(FirstRunDemos.DataStatus(songs), RotationState, swaps, lastSwapFaded));
    }

    /// <summary>Records one drawn data swap (a tick whose pool can't replace rows draws none).</summary>
    /// <param name="faded">Whether it fades, else it is instant.</param>
    private void CountSwap(bool faded)
    {
        swaps++;
        lastSwapFaded = faded;
    }

    /// <summary>Fades one slot out, swaps its content at the midpoint and fades it back (web fade-out → swap → fade-in).</summary>
    /// <param name="slot">Slot index.</param>
    /// <param name="poolIndex">New content.</param>
    private void FadeSwap(int slot, int poolIndex)
    {
        if (slot >= slots.Count) return;
        Fade(slots[slot], () => slotSetters[slot](poolIndex));
    }

    /// <summary>Fades every slot out, applies a change and fades back.</summary>
    /// <param name="change">Change applied while hidden.</param>
    private void FadeAll(Action change)
    {
        for (var i = 0; i < slots.Count; i++) Fade(slots[i], i == 0 ? change : null);
    }

    /// <summary>Compositor fade-out, content swap, fade-in matching the web timing.</summary>
    /// <remarks>
    /// The vertical nudge animates the visual's <c>Translation</c>, never <c>Offset</c>: XAML layout owns a hand-out
    /// visual's Offset, and resetting it to zero stacked every swapped row on the first one (issue #241).
    /// </remarks>
    /// <param name="element">Element.</param>
    /// <param name="change">Change at the midpoint, if any.</param>
    /// <param name="duration">One fade duration.</param>
    /// <param name="translateY">Optional offset while hidden.</param>
    private void Fade(FrameworkElement element, Action? change, TimeSpan? duration = null, float translateY = 0)
    {
        if (!Motion.Allowed)
        {
            CountSwap(faded: false);
            change?.Invoke();
            ResetVisual(element);
            return;
        }
        var fade = duration ?? FirstRunDemoTiming.FadeOut;
        CountSwap(faded: true);
        var visual = ElementCompositionPreview.GetElementVisual(element);
        if (translateY != 0)
        {
            ElementCompositionPreview.SetIsTranslationEnabled(element, true);
            visual.Properties.InsertVector3("Translation", Vector3.Zero);
        }
        var ease = visual.Compositor.CreateCubicBezierEasingFunction(new Vector2(0.25f, 0.1f), new Vector2(0.25f, 1f));
        var swap = new ActiveSwap { Element = element, Change = change };
        activeSwaps.Add(swap);

        void AnimateOpacity(float from, float to)
        {
            var animation = visual.Compositor.CreateScalarKeyFrameAnimation();
            animation.InsertKeyFrame(0f, from);
            animation.InsertKeyFrame(1f, to, ease);
            animation.Duration = fade;
            visual.StartAnimation("Opacity", animation);
        }

        void AnimateTranslation(float from, float to)
        {
            if (translateY == 0) return;
            var animation = visual.Compositor.CreateVector3KeyFrameAnimation();
            animation.InsertKeyFrame(0f, new Vector3(0, from, 0));
            animation.InsertKeyFrame(1f, new Vector3(0, to, 0), ease);
            animation.Duration = fade;
            visual.StartAnimation("Translation", animation);
        }

        AnimateOpacity(1, 0);
        AnimateTranslation(0, translateY);
        var midpoint = DispatcherQueue.CreateTimer();
        midpoint.Interval = fade;
        midpoint.IsRepeating = false;
        midpoint.Tick += (_, _) =>
        {
            swap.Changed = true;
            change?.Invoke();
            visual.Opacity = 0;
            AnimateOpacity(0, 1);
            AnimateTranslation(translateY, 0);
            var done = DispatcherQueue.CreateTimer();
            done.Interval = fade;
            done.IsRepeating = false;
            done.Tick += (_, _) =>
            {
                ResetVisual(element);
                activeSwaps.Remove(swap);
            };
            swap.Timers.Add(done);
            done.Start();
        };
        swap.Timers.Add(midpoint);
        midpoint.Start();
    }

    /// <summary>Completes any hidden swaps before stopping the timer.</summary>
    private void CompleteSwaps()
    {
        foreach (var swap in activeSwaps.ToList())
        {
            foreach (var timerToStop in swap.Timers) timerToStop.Stop();
            if (!swap.Changed)
            {
                swap.Change?.Invoke();
                swap.Changed = true;
            }
            ResetVisual(swap.Element);
            activeSwaps.Remove(swap);
        }
    }

    /// <summary>Stops a slot's fade and shows it fully opaque at its layout position.</summary>
    /// <param name="element">Slot element.</param>
    private static void ResetVisual(UIElement element)
    {
        var visual = ElementCompositionPreview.GetElementVisual(element);
        visual.StopAnimation("Opacity");
        visual.Opacity = 1;
        if (visual.Properties.TryGetVector3("Translation", out _) == Microsoft.UI.Composition.CompositionGetValueStatus.Succeeded)
        {
            visual.StopAnimation("Translation");
            visual.Properties.InsertVector3("Translation", Vector3.Zero);
        }
    }
    #endregion
}
#endregion
