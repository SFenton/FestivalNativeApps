using System.Runtime.CompilerServices;
using Festival.App.Services;
using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;

namespace Festival.App.Controls;

#region Card grid layout
/// <summary>
/// Adaptive card grid for <see cref="ItemsRepeater"/>: as many equal-width columns as fit
/// <see cref="MinColumnWidth"/> (one at compact widths), each row as tall as its tallest card. Unlike
/// <see cref="UniformGridLayout"/>, which sizes every item from the first, cards of different heights
/// (spotlight rows, failures, three- and four-member band rows) never clip. Non-virtualizing: the Leaderboards
/// overview has at most twelve cards and Song Detail at most one per instrument and band size. With
/// <see cref="MaxColumns"/> 1 and <see cref="MinColumnWidth"/> 0 it is a plain non-virtualizing stack, used for the
/// top-ten rows inside cached pages' cards: a virtualizing <see cref="StackLayout"/> drops off-screen rows while the
/// page is away and re-estimates their heights on Back, which moved the page (#276). Player Profile stacks its instrument
/// sections and band groups the same way: re-estimating them near the page end pulled the scroll back (#533). Short lists nested in scrolled cards and rows (band members, profile percentiles, Rival Detail previews) stack with it too, so their repeaters don't re-measure on every scroll frame as a virtualizing layout does (#668; the horizontal twin is <see cref="NonVirtualizingRowLayout"/>). With
/// <see cref="UsesWideColumns"/> its instrument sections flow into pattern <c>wide-columns</c>' two row-major columns in
/// wide windows (#653). Side by side, every card's <see cref="CardHeader"/> is padded so its title and its card surface
/// start on the row's shared lines when one header is taller, such as a combo board's icon row or a subtitle
/// (section-headers R14, #657). A change in the column count glides each card from its old place to its new one (pattern
/// <c>reflow-motion</c>, #669).
/// </summary>
public sealed partial class LeaderboardsCardGridLayout : NonVirtualizingLayout
{
    /// <summary>Smallest column width in effective pixels.</summary>
    public double MinColumnWidth { get; set; } = 360;

    /// <summary>
    /// Multiplies <see cref="MinColumnWidth"/> by the Windows text size (issue #207), so cards whose rows grow with text
    /// get fewer, wider columns instead of squeezing names out.
    /// </summary>
    public bool ScaleWithText { get; set; }

    /// <summary>Largest number of columns.</summary>
    public int MaxColumns { get; set; } = 4;

    /// <summary>Gap between cards.</summary>
    public double Spacing { get; set; } = 16;

    /// <summary>
    /// Takes the column count from pattern <c>wide-columns</c> (<see cref="WideColumnsHost"/>: two in a wide window at
    /// standard text sizes when both keep 320 epx, else one) instead of <see cref="MinColumnWidth"/> and
    /// <see cref="MaxColumns"/>. The host invalidates the layout when the text size changes; window resizes re-measure it.
    /// </summary>
    public bool UsesWideColumns { get; set; }

    /// <summary>Columns of the last measure, so arrange places cards in the widths they were measured at.</summary>
    private int measuredColumns = 1;

    /// <inheritdoc />
    protected override Size MeasureOverride(NonVirtualizingLayoutContext context, Size availableSize)
    {
        var children = context.Children;
        var width = double.IsInfinity(availableSize.Width) ? MinColumnWidth : availableSize.Width;
        var columns = measuredColumns = Columns(children, width);
        var columnWidth = ColumnWidth(width, columns);
        var childSize = new Size(columnWidth, double.PositiveInfinity);
        for (var i = 0; i < children.Count; i++) children[i].Measure(childSize);
        AlignHeaders(children, columns, childSize);
        double height = 0, rowHeight = 0;
        for (var i = 0; i < children.Count; i++)
        {
            rowHeight = Math.Max(rowHeight, children[i].DesiredSize.Height);
            if (i % columns == columns - 1 || i == children.Count - 1)
            {
                height += rowHeight + (height > 0 ? Spacing : 0);
                rowHeight = 0;
            }
        }
        return new Size(width, height);
    }

    /// <inheritdoc />
    protected override Size ArrangeOverride(NonVirtualizingLayoutContext context, Size finalSize)
    {
        var children = context.Children;
        var columns = UsesWideColumns ? measuredColumns : Columns(children, finalSize.Width);
        var columnWidth = ColumnWidth(finalSize.Width, columns);
        // Pattern reflow-motion (#669): a column change glides each card from where it was drawn to its new place.
        var tracks = UsesWideColumns || MaxColumns > 1;
        var reflows = tracks && arrangedColumns > 0 && columns != arrangedColumns && Motion.Allowed;
        var moved = 0;
        double y = 0;
        for (var start = 0; start < children.Count; start += columns)
        {
            var end = Math.Min(start + columns, children.Count);
            double rowHeight = 0;
            for (var i = start; i < end; i++) rowHeight = Math.Max(rowHeight, children[i].DesiredSize.Height);
            for (var i = start; i < end; i++)
            {
                var slot = new Point((i - start) * (columnWidth + Spacing), y);
                children[i].Arrange(new Rect(slot.X, slot.Y, columnWidth, rowHeight));
                if (!tracks) continue;
                // A cached page re-entering the tree (not loaded yet) shows its cards in place: nothing replays on Back.
                if (reflows && children[i] is FrameworkElement { IsLoaded: true } && Placed.TryGetValue(children[i], out var was)
                    && ReflowMotion.Move(children[i], new Point(was.At.X - slot.X, was.At.Y - slot.Y))) moved++;
                Placed.AddOrUpdate(children[i], new Placement(slot));
            }
            y += rowHeight + Spacing;
        }
        if (tracks && columns != arrangedColumns && arrangedColumns > 0) ReflowMotion.Trace("card-grid", moved, 0, reflows);
        if (tracks) arrangedColumns = columns;
        return finalSize;
    }

    /// <summary>Columns of the last arrange (0 before the first), so a column change can be told from a resize.</summary>
    private int arrangedColumns;

    /// <summary>Where each card was last arranged (pattern reflow-motion).</summary>
    private static readonly ConditionalWeakTable<UIElement, Placement> Placed = new();

    /// <summary>A card's last arranged top-left.</summary>
    /// <param name="At">Top-left in the repeater.</param>
    private sealed record Placement(Point At);

    /// <summary>Columns that fit the width.</summary>
    /// <param name="children">Realized cards (any one locates the window for <see cref="UsesWideColumns"/>).</param>
    /// <param name="width">Available width.</param>
    /// <returns>1…<see cref="MaxColumns"/>, or the wide-columns count.</returns>
    private int Columns(IReadOnlyList<UIElement> children, double width) => UsesWideColumns
        ? WideColumnsHost.Count(children.Count > 0 ? children[0] : null, width, Spacing)
        : Math.Clamp((int)Math.Floor((width + Spacing) / (EffectiveMinColumnWidth + Spacing)), 1, Math.Max(1, MaxColumns));

    /// <summary>Minimum column width after text scaling.</summary>
    private double EffectiveMinColumnWidth => ScaleWithText ? MinColumnWidth * TextScaleLayout.Factor : MinColumnWidth;

    /// <summary>Equal column width.</summary>
    /// <param name="width">Available width.</param>
    /// <param name="columns">Column count.</param>
    /// <returns>Width per column.</returns>
    private double ColumnWidth(double width, int columns) => Math.Max(0, (width - (columns - 1) * Spacing) / columns);

    #region Header alignment
    /// <summary>Each card's <see cref="CardHeader"/> (or none), found once per realized card.</summary>
    private static readonly ConditionalWeakTable<UIElement, HeaderSlot> Headers = new();

    /// <summary>A cached header lookup; <see cref="Header"/> is null for a card without one.</summary>
    private sealed class HeaderSlot
    {
        public CardHeader? Header;
    }

    /// <summary>
    /// Pads every card header in a multi-column row so the titles share a line and the card surfaces share a line
    /// (section-headers R14, issue #657), then measures the changed cards again; one column removes any alignment space.
    /// </summary>
    /// <param name="children">The measured cards.</param>
    /// <param name="columns">Cards per row.</param>
    /// <param name="childSize">The size the cards were measured with.</param>
    private static void AlignHeaders(IReadOnlyList<UIElement> children, int columns, Size childSize)
    {
        var headers = new CardHeader?[children.Count];
        var sizes = new CardHeaderSize?[children.Count];
        for (var i = 0; i < children.Count; i++)
        {
            // One column never looks for headers (Settings stacks hundreds of rows), it only resets ones it aligned.
            headers[i] = columns > 1 ? HeaderOf(children[i])
                : Headers.TryGetValue(children[i], out var slot) ? slot.Header : null;
            // A collapsed header isn't measured, so its last size is stale: it neither sets nor takes the row's lines.
            sizes[i] = headers[i] is { Visibility: Visibility.Visible } h ? h.NaturalSize : null;
        }
        var insets = CardRowAlignment.Insets(sizes, columns);
        for (var i = 0; i < children.Count; i++)
            if (headers[i]?.AlignToRow(insets[i]) == true) children[i].Measure(childSize);
    }

    /// <summary>The card's header: the first <see cref="CardHeader"/> within a few levels of the card root.</summary>
    /// <param name="card">A measured card (its template is applied).</param>
    /// <returns>The header, or null.</returns>
    private static CardHeader? HeaderOf(UIElement card)
    {
        if (Headers.TryGetValue(card, out var cached)) return cached.Header;
        var header = Find(card, 5);
        // A card whose template isn't applied yet has no tree to search: look again on its next measure.
        if (header is not null || VisualTreeHelper.GetChildrenCount(card) > 0) Headers.AddOrUpdate(card, new HeaderSlot { Header = header });
        return header;
    }

    /// <summary>Breadth-first search for a header, stopping at <paramref name="depth"/> levels so rows aren't walked.</summary>
    /// <param name="root">Where to start.</param>
    /// <param name="depth">Levels below <paramref name="root"/> to search.</param>
    /// <returns>The first header, or null.</returns>
    private static CardHeader? Find(DependencyObject root, int depth)
    {
        var level = new List<DependencyObject> { root };
        for (var d = 0; d <= depth && level.Count > 0; d++)
        {
            var next = new List<DependencyObject>();
            foreach (var node in level)
            {
                if (node is CardHeader header) return header;
                for (var i = 0; i < VisualTreeHelper.GetChildrenCount(node); i++) next.Add(VisualTreeHelper.GetChild(node, i));
            }
            level = next;
        }
        return null;
    }
    #endregion
}
#endregion
