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
/// app's own brushes, advancing one step every <see cref="FirstRunDemos.Cycle"/> (a row fades out and back with new
/// content, a highlight moves, an order flips). Only the carousel's visible slide runs (<see cref="Active"/>); it holds
/// still when motion is off or the window is hidden, and stops when unloaded. Decorative for UI Automation: the slide's
/// title and description carry the meaning.
/// </summary>
public sealed partial class FirstRunDemo : UserControl
{
    /// <summary>Slide ID dependency property.</summary>
    public static readonly DependencyProperty SlideIdProperty =
        DependencyProperty.Register(nameof(SlideId), typeof(string), typeof(FirstRunDemo), new PropertyMetadata(null, (d, _) => ((FirstRunDemo)d).Build()));

    private static readonly string[] Letters = ["#", "A", "B", "C", "D", "E", "F"];

    private readonly StackPanel root = new() { Spacing = 6, VerticalAlignment = VerticalAlignment.Center };
    private readonly List<FrameworkElement> slots = [];
    private readonly List<Action<int>> slotSetters = [];
    private IReadOnlyList<FirstRunDemoSong> songs = [];
    private FirstRunDemoKind? kind;
    private DispatcherQueueTimer? timer;
    private CancellationTokenSource? artLoads;
    private Action<int>? advance;
    private int step;
    private bool active;

    /// <summary>Creates the demo.</summary>
    public FirstRunDemo()
    {
        Content = root;
        AutomationProperties.SetAccessibilityView(this, AccessibilityView.Raw);
        Loaded += (_, _) =>
        {
            Motion.Changed += OnMotionChanged;
            App.Session.PropertyChanged += OnSessionChanged;
            if (CatalogueNowAvailable) Build();
            UpdateTimer();
        };
        Unloaded += (_, _) =>
        {
            Motion.Changed -= OnMotionChanged;
            App.Session.PropertyChanged -= OnSessionChanged;
            timer?.Stop();
            artLoads?.Cancel();
        };
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
        root.Children.Clear();
        slots.Clear();
        slotSetters.Clear();
        advance = null;
        step = 0;
        kind = FirstRunDemos.KindFor(SlideId);
        if (kind is not { } k) return;
        songs = SongPoolFor(k);
        artLoads?.Cancel();
        artLoads = new CancellationTokenSource();
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
    }

    /// <summary>Song rows; swaps one row per step. Chips, metadata pills or a Shop pulse decorate them by kind.</summary>
    /// <param name="k">Kind.</param>
    private void BuildSongRows(FirstRunDemoKind k)
    {
        for (var i = 0; i < FirstRunDemos.RowCount; i++)
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
                var statuses = new[] { SongInstrumentStatus.FullCombo, SongInstrumentStatus.Scored, SongInstrumentStatus.NoScore };
                foreach (var (instrument, n) in new[] { Instrument.Lead, Instrument.Bass, Instrument.Drums }.Select((x, n) => (x, n)))
                    trailing.Children.Add(Chip(instrument, statuses[(n + i) % statuses.Length]));
            }
            var index = i;
            Action<int> set = poolIndex =>
            {
                setter(poolIndex);
                if (k == FirstRunDemoKind.Metadata)
                {
                    trailing.Children.Clear();
                    trailing.Children.Add(Pill(FirstRunDemos.MetadataPills[(poolIndex + index) % FirstRunDemos.MetadataPills.Count]));
                }
            };
            set(i);
            var host = new Grid();
            host.Children.Add(row);
            if (pulse is not null && i == 1)
            {
                var ring = new ShopPulseRing();
                ring.Apply(pulse);
                host.Children.Add(ring);
                if (k == FirstRunDemoKind.LeavingPulse) trailing.Children.Add(LeavingPill());
            }
            AddSlot(host, set);
        }
        advance = s =>
        {
            var (rowIndex, poolIndex) = FirstRunDemos.Swap(s, slots.Count, songs.Count);
            FadeSwap(rowIndex, poolIndex);
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
        var swapRows = advance!;
        advance = s =>
        {
            ((TextBlock)chip.Child).Text = FirstRunDemos.FilterChips[(s + 1) % FirstRunDemos.FilterChips.Count];
            swapRows(s);
        };
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
        var swapRows = advance!;
        void Highlight(int index)
        {
            for (var i = 0; i < cells.Count; i++)
                cells[i].Background = i == index ? Resource("FSTAccentPurpleBrush", Color.FromArgb(0xFF, 0x7C, 0x3A, 0xED)) : Card();
        }
        Highlight(1);
        advance = s =>
        {
            Highlight(1 + ((s + 1) % (cells.Count - 1)));
            swapRows(s);
        };
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
            var fill = new ShopPulseFill();
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
            var ring = new ShopPulseRing();
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

    /// <summary>White demo text.</summary>
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
    #endregion

    #region Motion
    /// <summary>Re-evaluates the timer when motion settings or window visibility change.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnMotionChanged(object? sender, EventArgs e) => UpdateTimer();

    /// <summary>Runs the step timer only for the visible slide while motion is allowed.</summary>
    private void UpdateTimer()
    {
        var run = active && IsLoaded && advance is not null && Motion.Allowed && !Motion.Paused;
        if (!run)
        {
            timer?.Stop();
            return;
        }
        if (timer is null)
        {
            timer = DispatcherQueue.CreateTimer();
            timer.Interval = FirstRunDemos.Cycle;
            timer.Tick += (_, _) => advance?.Invoke(step++);
        }
        if (!timer.IsRunning) timer.Start();
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

    /// <summary>Compositor opacity dip over <see cref="FirstRunDemos.Fade"/>, running the change at the bottom.</summary>
    /// <param name="element">Element.</param>
    /// <param name="change">Change at the midpoint, if any.</param>
    private void Fade(FrameworkElement element, Action? change)
    {
        var visual = ElementCompositionPreview.GetElementVisual(element);
        var dip = visual.Compositor.CreateScalarKeyFrameAnimation();
        var ease = visual.Compositor.CreateCubicBezierEasingFunction(new Vector2(0.25f, 0.1f), new Vector2(0.25f, 1f));
        dip.InsertKeyFrame(0f, 1f);
        dip.InsertKeyFrame(0.5f, 0f, ease);
        dip.InsertKeyFrame(1f, 1f, ease);
        dip.Duration = FirstRunDemos.Fade;
        visual.StartAnimation("Opacity", dip);
        if (change is null) return;
        var midpoint = DispatcherQueue.CreateTimer();
        midpoint.Interval = FirstRunDemos.Fade / 2;
        midpoint.IsRepeating = false;
        midpoint.Tick += (_, _) => change();
        midpoint.Start();
    }
    #endregion
}
#endregion
