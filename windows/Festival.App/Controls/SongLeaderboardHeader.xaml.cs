using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Song leaderboard header
/// <summary>
/// The one song-first header of a song leaderboard (web <c>SongInfoHeader</c>): the solo board names its instrument on
/// the board line, the band board its band size (issue #317). Pages keep the song's static cover as the shell backdrop
/// (<c>IBackdropPage</c>); this control only draws the header's own art tile, through the shared artwork caches.
/// </summary>
public sealed partial class SongLeaderboardHeader : UserControl
{
    /// <summary>Art tile size at the wide layout (epx); the compact window layout uses 56 epx.</summary>
    public const double ArtSize = 80;

    private CancellationTokenSource artLoad = new();

    #region Dependency properties
    /// <summary>Song title (the level-1 heading).</summary>
    public static readonly DependencyProperty TitleProperty = Register(nameof(Title), (h, _) => h.UpdateVisibility());

    /// <summary>Artist line.</summary>
    public static readonly DependencyProperty ArtistProperty = Register(nameof(Artist), (h, _) => h.UpdateVisibility());

    /// <summary>Board line: instrument name or band size.</summary>
    public static readonly DependencyProperty BoardLabelProperty = Register(nameof(BoardLabel), null);

    /// <summary>Instrument icon file for the board line; empty for a board without an icon (band sizes).</summary>
    public static readonly DependencyProperty BoardIconFileProperty = Register(nameof(BoardIconFile), (h, _) => h.UpdateVisibility());

    /// <summary>Entry-total line; empty hides it.</summary>
    public static readonly DependencyProperty TotalTextProperty = Register(nameof(TotalText), (h, _) => h.UpdateVisibility());

    /// <summary>Song <c>albumArt</c> for the art tile.</summary>
    public static readonly DependencyProperty ArtUrlProperty = Register(nameof(ArtUrl), (h, _) => h.LoadArt());

    /// <summary>Automation ID of the title heading (e.g. <c>fst.song-leaderboard.title</c>).</summary>
    public static readonly DependencyProperty TitleAutomationIdProperty = Register(nameof(TitleAutomationId), null);

    /// <summary>Automation ID of the board line.</summary>
    public static readonly DependencyProperty BoardAutomationIdProperty = Register(nameof(BoardAutomationId), null);

    /// <summary>Automation ID of the entry-total line.</summary>
    public static readonly DependencyProperty TotalAutomationIdProperty = Register(nameof(TotalAutomationId), null);
    #endregion

    /// <summary>Creates the header.</summary>
    public SongLeaderboardHeader()
    {
        InitializeComponent();
        UpdateVisibility();
        Loaded += (_, _) => LoadArt();
        Unloaded += (_, _) => artLoad.Cancel();
    }

    #region Properties
    /// <inheritdoc cref="TitleProperty" />
    public string Title { get => (string?)GetValue(TitleProperty) ?? ""; set => SetValue(TitleProperty, value ?? ""); }

    /// <inheritdoc cref="ArtistProperty" />
    public string Artist { get => (string?)GetValue(ArtistProperty) ?? ""; set => SetValue(ArtistProperty, value ?? ""); }

    /// <inheritdoc cref="BoardLabelProperty" />
    public string BoardLabel { get => (string?)GetValue(BoardLabelProperty) ?? ""; set => SetValue(BoardLabelProperty, value ?? ""); }

    /// <inheritdoc cref="BoardIconFileProperty" />
    public string BoardIconFile { get => (string?)GetValue(BoardIconFileProperty) ?? ""; set => SetValue(BoardIconFileProperty, value ?? ""); }

    /// <inheritdoc cref="TotalTextProperty" />
    public string TotalText { get => (string?)GetValue(TotalTextProperty) ?? ""; set => SetValue(TotalTextProperty, value ?? ""); }

    /// <inheritdoc cref="ArtUrlProperty" />
    public string ArtUrl { get => (string?)GetValue(ArtUrlProperty) ?? ""; set => SetValue(ArtUrlProperty, value ?? ""); }

    /// <inheritdoc cref="TitleAutomationIdProperty" />
    public string TitleAutomationId { get => (string?)GetValue(TitleAutomationIdProperty) ?? ""; set => SetValue(TitleAutomationIdProperty, value ?? ""); }

    /// <inheritdoc cref="BoardAutomationIdProperty" />
    public string BoardAutomationId { get => (string?)GetValue(BoardAutomationIdProperty) ?? ""; set => SetValue(BoardAutomationIdProperty, value ?? ""); }

    /// <inheritdoc cref="TotalAutomationIdProperty" />
    public string TotalAutomationId { get => (string?)GetValue(TotalAutomationIdProperty) ?? ""; set => SetValue(TotalAutomationIdProperty, value ?? ""); }
    #endregion

    /// <summary>Registers a string property defaulting to empty (a null automation ID would throw).</summary>
    /// <param name="name">Property name.</param>
    /// <param name="changed">Change handler, if any.</param>
    /// <returns>Dependency property.</returns>
    private static DependencyProperty Register(string name, Action<SongLeaderboardHeader, DependencyPropertyChangedEventArgs>? changed) =>
        DependencyProperty.Register(name, typeof(string), typeof(SongLeaderboardHeader),
            new PropertyMetadata("", changed is null ? null : (d, e) => changed((SongLeaderboardHeader)d, e)));

    /// <summary>
    /// Collapses empty lines, so a board without icon or total leaves no gap; an unresolved song (no title) also hides the
    /// art tile, leaving only the board line above the failure state.
    /// </summary>
    private void UpdateVisibility()
    {
        TitleBlock.Visibility = Title.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        ArtHost.Visibility = TitleBlock.Visibility;
        ArtistBlock.Visibility = Artist.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        BoardIcon.Visibility = BoardIconFile.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
        TotalBlock.Visibility = TotalText.Length > 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>
    /// Loads the art tile at display size from the shared bounded caches; Save Data and <c>--no-art</c> keep the plain
    /// tile (decorative art stops for Low Data, AGENTS.md).
    /// </summary>
    private async void LoadArt()
    {
        artLoad.Cancel();
        artLoad = new CancellationTokenSource();
        var token = artLoad.Token;
        if (ArtUrl.Length == 0 || !IsLoaded || App.Session.Settings.SaveData || App.Options.NoArt)
        {
            if (ArtUrl.Length == 0) Art.Source = null;
            return;
        }
        var pixels = (int)Math.Ceiling(ArtSize * (XamlRoot?.RasterizationScale ?? 1));
        var image = await ArtworkImages.LoadAsync(ArtUrl, pixels, token);
        if (!token.IsCancellationRequested) Art.Source = image;
    }
}
#endregion
