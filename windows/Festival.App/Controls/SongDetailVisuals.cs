using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.Text;

namespace Festival.App.Controls;

#region Song detail visuals
/// <summary>
/// x:Bind helpers for the selected player's rows (web <c>InstrumentCard</c> <c>playerEntryRow</c> + <c>LeaderboardEntry</c>
/// <c>isPlayer</c>): a purple highlight (<c>purpleHighlight</c> fill, <c>purpleHighlightBorder</c> stroke) with the rank and
/// name in bold. The score-history list's personal-best row uses the same treatment.
/// </summary>
public static class SongDetailVisuals
{
    private static readonly SolidColorBrush HighlightFill = new(Color.FromArgb(0xBF, 0x4B, 0x0F, 0x63));
    private static readonly SolidColorBrush HighlightStroke = new(Color.FromArgb(0x80, 0x7C, 0x3A, 0xED));
    private static readonly SolidColorBrush Clear = new(Color.FromArgb(0, 0, 0, 0));

    /// <summary>Row fill.</summary>
    /// <param name="player">Selected player's row.</param>
    /// <returns>Brush.</returns>
    public static Brush Fill(bool player) => player ? HighlightFill : Clear;

    /// <summary>Score-history row fill: purple for the personal best, else the card surface.</summary>
    /// <param name="best">Personal-best row.</param>
    /// <returns>Brush.</returns>
    public static Brush RowFill(bool best) => best ? HighlightFill : (Brush)Microsoft.UI.Xaml.Application.Current.Resources["FSTCardSurfaceBrush"];

    /// <summary>Score-history row stroke: purple for the personal best, else the card stroke.</summary>
    /// <param name="best">Personal-best row.</param>
    /// <returns>Brush.</returns>
    public static Brush RowStroke(bool best) => best ? HighlightStroke : (Brush)Microsoft.UI.Xaml.Application.Current.Resources["FSTCardStrokeBrush"];

    /// <summary>Row stroke.</summary>
    /// <param name="player">Selected player's row.</param>
    /// <returns>Brush.</returns>
    public static Brush Stroke(bool player) => player ? HighlightStroke : Clear;

    /// <summary>Bold for the selected player's rank and name.</summary>
    /// <param name="player">Selected player's row.</param>
    /// <returns>Weight.</returns>
    public static FontWeight Weight(bool player) => player ? new FontWeight(700) : new FontWeight(400);
}
#endregion
