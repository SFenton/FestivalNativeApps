using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Song header text
/// <summary>Where a <see cref="SongHeaderText"/> sits.</summary>
public enum SongHeaderTextVariant
{
    /// <summary>In-page header: the title is the level-1 heading and both lines wrap at large text (song-header R3).</summary>
    Page,

    /// <summary>Pinned bar copy: no heading, one marqueeing line at every text size (song-header R4).</summary>
    Bar,
}

/// <summary>
/// The one song title + artist column of every Windows song header (pattern <c>song-header</c> R1; web
/// <c>SongInfoHeader</c>'s text column, Apple <c>SongHeaderText</c>/<c>SongBarTitle</c>, Android <c>SongHeader</c>): two
/// <see cref="MarqueeText"/> lines that fill the column on one line each and scroll only on overflow (R2), ellipsize
/// with motion off and, in the <see cref="SongHeaderTextVariant.Page"/> variant, wrap at large Windows text sizes (R3).
/// When both lines overflow they scroll the same distance (the wider line plus the gap) in lockstep, like the web's
/// <c>useMarqueeSync</c> (<see cref="Festival.Core.Domain.MarqueeSync"/>); a lone overflowing line keeps its own distance.
/// The <see cref="SongHeaderTextVariant.Bar"/> variant is the compact pinned bar copy (R4). Empty lines collapse. Pages
/// keep their art, board line and actions outside it. A panel, so it adds no automation node: the title and artist
/// stay direct static-text children of the header (or its button).
/// </summary>
public sealed partial class SongHeaderText : StackPanel
{
    private readonly MarqueeText titleLine = new();
    private readonly MarqueeText artistLine = new();

    #region Dependency properties
    /// <summary>Song title.</summary>
    public static readonly DependencyProperty TitleProperty = RegisterText(nameof(Title), (h, v) => h.titleLine.Text = v);

    /// <summary>Artist line (artist · year · length).</summary>
    public static readonly DependencyProperty ArtistProperty = RegisterText(nameof(Artist), (h, v) => h.artistLine.Text = v);

    /// <summary>Automation ID of the title line.</summary>
    public static readonly DependencyProperty TitleAutomationIdProperty = RegisterText(nameof(TitleAutomationId),
        (h, v) => AutomationProperties.SetAutomationId(h.titleLine, v));

    /// <summary>Automation ID of the artist line.</summary>
    public static readonly DependencyProperty ArtistAutomationIdProperty = RegisterText(nameof(ArtistAutomationId),
        (h, v) => AutomationProperties.SetAutomationId(h.artistLine, v));

    /// <summary>Title type style; <see langword="null"/> uses the variant's (<c>FSTPageTitleStyle</c>, bar <c>FSTMarqueeTitleStyle</c>).</summary>
    public static readonly DependencyProperty TitleStyleProperty = DependencyProperty.Register(
        nameof(TitleStyle), typeof(Style), typeof(SongHeaderText), new PropertyMetadata(null, (d, _) => ((SongHeaderText)d).ApplyVariant()));

    /// <summary>Artist type style; <see langword="null"/> uses the variant's (<c>FSTMarqueeSecondaryStyle</c>, bar <c>FSTMarqueeCaptionStyle</c>).</summary>
    public static readonly DependencyProperty ArtistStyleProperty = DependencyProperty.Register(
        nameof(ArtistStyle), typeof(Style), typeof(SongHeaderText), new PropertyMetadata(null, (d, _) => ((SongHeaderText)d).ApplyVariant()));

    /// <summary>In-page header or pinned bar copy.</summary>
    public static readonly DependencyProperty VariantProperty = DependencyProperty.Register(
        nameof(Variant), typeof(SongHeaderTextVariant), typeof(SongHeaderText),
        new PropertyMetadata(SongHeaderTextVariant.Page, (d, _) => ((SongHeaderText)d).ApplyVariant()));
    #endregion

    /// <summary>Creates the column.</summary>
    public SongHeaderText()
    {
        Children.Add(titleLine);
        Children.Add(artistLine);
        titleLine.OverflowWidthChanged += (_, _) => SyncLines();
        artistLine.OverflowWidthChanged += (_, _) => SyncLines();
        ApplyVariant();
        UpdateVisibility();
    }

    #region Properties
    /// <inheritdoc cref="TitleProperty" />
    public string Title { get => (string?)GetValue(TitleProperty) ?? ""; set => SetValue(TitleProperty, value ?? ""); }

    /// <inheritdoc cref="ArtistProperty" />
    public string Artist { get => (string?)GetValue(ArtistProperty) ?? ""; set => SetValue(ArtistProperty, value ?? ""); }

    /// <inheritdoc cref="TitleAutomationIdProperty" />
    public string TitleAutomationId { get => (string?)GetValue(TitleAutomationIdProperty) ?? ""; set => SetValue(TitleAutomationIdProperty, value ?? ""); }

    /// <inheritdoc cref="ArtistAutomationIdProperty" />
    public string ArtistAutomationId { get => (string?)GetValue(ArtistAutomationIdProperty) ?? ""; set => SetValue(ArtistAutomationIdProperty, value ?? ""); }

    /// <inheritdoc cref="TitleStyleProperty" />
    public Style? TitleStyle { get => (Style?)GetValue(TitleStyleProperty); set => SetValue(TitleStyleProperty, value); }

    /// <inheritdoc cref="ArtistStyleProperty" />
    public Style? ArtistStyle { get => (Style?)GetValue(ArtistStyleProperty); set => SetValue(ArtistStyleProperty, value); }

    /// <inheritdoc cref="VariantProperty" />
    public SongHeaderTextVariant Variant { get => (SongHeaderTextVariant)GetValue(VariantProperty); set => SetValue(VariantProperty, value); }
    #endregion

    /// <summary>Registers a string property (default empty: a null automation ID would throw) that pushes to a line.</summary>
    /// <param name="name">Property name.</param>
    /// <param name="apply">Applies the new value.</param>
    /// <returns>Dependency property.</returns>
    private static DependencyProperty RegisterText(string name, Action<SongHeaderText, string> apply) =>
        DependencyProperty.Register(name, typeof(string), typeof(SongHeaderText), new PropertyMetadata("", (d, e) =>
        {
            var header = (SongHeaderText)d;
            apply(header, e.NewValue as string ?? "");
            header.UpdateVisibility();
        }));

    /// <summary>Applies the variant's type styles, heading and large-text behavior.</summary>
    private void ApplyVariant()
    {
        var page = Variant == SongHeaderTextVariant.Page;
        titleLine.TextStyle = TitleStyle ?? Resource(page ? "FSTPageTitleStyle" : "FSTMarqueeTitleStyle");
        artistLine.TextStyle = ArtistStyle ?? Resource(page ? "FSTMarqueeSecondaryStyle" : "FSTMarqueeCaptionStyle");
        titleLine.WrapsAtLargeText = artistLine.WrapsAtLargeText = page;
        AutomationProperties.SetHeadingLevel(titleLine, page ? AutomationHeadingLevel.Level1 : AutomationHeadingLevel.None);
    }

    /// <summary>Collapses empty lines so a missing artist (or song) leaves no gap.</summary>
    private void UpdateVisibility()
    {
        titleLine.Visibility = Title.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        artistLine.Visibility = Artist.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        SyncLines();
    }

    /// <summary>
    /// Gives both lines the shared distance when both overflow (song-header R2, web <c>useMarqueeSync</c>), else none.
    /// Both are set in one pass, so playing lines restart together from the shared epoch.
    /// </summary>
    private void SyncLines()
    {
        static double Width(MarqueeText line) => line.Visibility == Visibility.Visible ? line.OverflowWidth : 0;
        var distance = Festival.Core.Domain.MarqueeSync.Distance(new[] { Width(titleLine), Width(artistLine) }, MarqueeText.Gap);
        titleLine.SyncDistance = distance;
        artistLine.SyncDistance = distance;
    }

    /// <summary>Looks up an app style.</summary>
    /// <param name="key">Resource key.</param>
    /// <returns>The style, or <see langword="null"/> when missing.</returns>
    private static Style? Resource(string key) =>
        Application.Current?.Resources.TryGetValue(key, out var value) == true ? value as Style : null;
}
#endregion
