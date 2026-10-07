using System.Windows.Input;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Pager
/// <summary>First/Previous/page-info/Next/Last paging state for band lists (25 rows per page).</summary>
public sealed partial class BandsPagerViewModel : ObservableObject, IBoardPager
{
    private readonly Func<int, Task> goTo;

    /// <summary>Creates a pager.</summary>
    /// <param name="goTo">Loads a one-based page.</param>
    public BandsPagerViewModel(Func<int, Task> goTo) => this.goTo = goTo;

    /// <summary>Current one-based page.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PageText), nameof(PageAnnouncement), nameof(CanGoBack), nameof(CanGoForward), nameof(IsVisible), nameof(InfoText), nameof(InfoAnnouncement), nameof(IsPaged))]
    [NotifyCanExecuteChangedFor(nameof(FirstCommand), nameof(PreviousCommand), nameof(NextCommand), nameof(LastCommand))]
    private int page = 1;

    /// <summary>Known page count (at least one).</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(PageText), nameof(PageAnnouncement), nameof(CanGoBack), nameof(CanGoForward), nameof(IsVisible), nameof(InfoText), nameof(InfoAnnouncement), nameof(IsPaged))]
    [NotifyCanExecuteChangedFor(nameof(FirstCommand), nameof(PreviousCommand), nameof(NextCommand), nameof(LastCommand))]
    private int pageCount = 1;

    /// <summary><c>1 / 12</c>.</summary>
    public string PageText => $"{BandFormatting.Count(Page)} / {BandFormatting.Count(PageCount)}";

    /// <summary>Spoken page position.</summary>
    public string PageAnnouncement => $"Page {Page} of {PageCount}";

    /// <summary>Whether earlier pages exist.</summary>
    public bool CanGoBack => Page > 1;

    /// <summary>Whether later pages exist.</summary>
    public bool CanGoForward => Page < PageCount;

    /// <summary>Whether paging is worth showing (more than one page).</summary>
    public bool IsVisible => PageCount > 1;

    /// <summary>Goes to page one.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoBack))]
    private Task FirstAsync() => goTo(1);

    /// <summary>Goes back one page.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoBack))]
    private Task PreviousAsync() => goTo(Page - 1);

    /// <summary>Goes forward one page.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoForward))]
    private Task NextAsync() => goTo(Page + 1);

    /// <summary>Goes to the last page.</summary>
    /// <returns>Load task.</returns>
    [RelayCommand(CanExecute = nameof(CanGoForward))]
    private Task LastAsync() => goTo(PageCount);

    /// <inheritdoc />
    public string InfoText => PageText;

    /// <inheritdoc />
    public string InfoAnnouncement => PageAnnouncement;

    /// <inheritdoc />
    public bool IsPaged => IsVisible;

    ICommand IBoardPager.FirstCommand => FirstCommand;

    ICommand IBoardPager.PreviousCommand => PreviousCommand;

    ICommand IBoardPager.NextCommand => NextCommand;

    ICommand IBoardPager.LastCommand => LastCommand;
}
#endregion

#region Rows
/// <summary>An instrument icon inside a band row.</summary>
/// <param name="Instrument">Chart.</param>
public sealed record BandInstrumentIcon(Instrument Instrument)
{
    /// <summary>Bundled icon file.</summary>
    public string File => Instrument.IconFile();

    /// <summary>Accessible label.</summary>
    public string Label => Instrument.Label();
}

/// <summary>One member with instrument icons; the whole row opens the player's profile.</summary>
/// <param name="Member">Wire member.</param>
public sealed record BandMemberRow(BandMember Member)
{
    /// <summary>Readable name.</summary>
    public string Name => Member.ResolvedName;

    /// <summary>Distinct instrument icons (a concrete list for XAML).</summary>
    public List<BandInstrumentIcon> Icons { get; } = [.. Member.ChartedInstruments.Select(i => new BandInstrumentIcon(i))];

    /// <summary>Whether any icon is known.</summary>
    public bool HasIcons => Icons.Count > 0;

    /// <summary><c>No observed instrument</c> hint when there are no icons.</summary>
    public string InstrumentsText => HasIcons ? string.Join(", ", Icons.Select(i => i.Label)) : "No observed instrument";

    /// <summary>Per-song member score (song band leaderboards only), or empty.</summary>
    public string ScoreText => Member.Score is { } score ? BandFormatting.Count(score) : "";

    /// <summary>Whether a per-song member score is shown.</summary>
    public bool HasScore => ScoreText.Length > 0;

    /// <summary>Whether the member sits on the selected player's highlighted band card (text follows the player-row fill).</summary>
    public bool OnPlayerRow { get; init; }

    /// <summary>Player profile route, when the account ID is safe.</summary>
    public AppRoute? Route => Member.HasValidAccount
        ? new AppRoute.Player(Member.AccountId, string.IsNullOrWhiteSpace(Member.DisplayName) ? null : Name) : null;

    /// <summary>Automation ID (<c>fst.band.member.&lt;accountId&gt;</c>).</summary>
    public string AutomationId => "fst.band.member." + Member.AccountId;

    /// <summary>Screen-reader summary.</summary>
    public string Announcement => $"{Name}, {InstrumentsText}";
}

/// <summary>A band card: members with icons, appearances and a link to Band Detail.</summary>
public sealed record PlayerBandCardViewModel
{
    /// <summary>Creates a card from a player-bands row.</summary>
    /// <param name="entry">Wire row.</param>
    public PlayerBandCardViewModel(PlayerBandEntry entry)
    {
        Entry = entry;
        Members = [.. entry.Members.DistinctBy(m => m.AccountId, StringComparer.Ordinal).Select(m => new BandMemberRow(m))];
        BandTypeLabel = BandTypeInfo.TryParse(entry.BandType, out var type) ? type.Label() : "Band";
    }

    /// <summary>Wire row.</summary>
    public PlayerBandEntry Entry { get; }

    /// <summary>Distinct members.</summary>
    public List<BandMemberRow> Members { get; }

    /// <summary>Joined names.</summary>
    public string Title => Entry.MembersLabel;

    /// <summary><c>Duos</c>, <c>Trios</c> or <c>Quads</c>.</summary>
    public string BandTypeLabel { get; }

    /// <summary><c>42 appearances</c>.</summary>
    public string AppearancesText =>
        $"{BandFormatting.Count(Entry.AppearanceCount)} {(Entry.AppearanceCount == 1 ? "appearance" : "appearances")}";

    /// <summary>Band Detail route carrying the type and team key (the safe lookup).</summary>
    public AppRoute Route => new AppRoute.Band(Entry.Key, Entry.BandType, Entry.TeamKey);

    /// <summary>Automation ID (<c>fst.player-bands.row.&lt;key&gt;</c>).</summary>
    public string AutomationId => "fst.player-bands.row." + Entry.Key;

    /// <summary>Screen-reader summary: the whole card is one Narrator stop, so it names each member's instruments.</summary>
    public string Announcement =>
        $"View band: {(Members.Count > 0 ? string.Join("; ", Members.Select(m => m.Announcement)) : Title)}. {BandTypeLabel}, {AppearancesText}";
}

/// <summary>A labelled statistic card, optionally navigable.</summary>
/// <param name="Id">Stable ID suffix.</param>
/// <param name="Label">Title Case label.</param>
/// <param name="Value">Display value.</param>
/// <param name="Route">Destination when the card is a link.</param>
/// <param name="GoldStars">Draw five gold star images instead of the value (average stars of exactly six).</param>
public sealed record BandStatCard(string Id, string Label, string Value, AppRoute? Route = null, bool GoldStars = false)
{
    /// <summary>Whether the value text shows (average stars of exactly six draw gold stars instead).</summary>
    public bool ShowValue => !GoldStars;

    /// <summary>Whether the card navigates.</summary>
    public bool IsLink => Route is not null;

    /// <summary>Automation ID (<c>fst.band.stat.&lt;id&gt;</c>).</summary>
    public string AutomationId => "fst.band.stat." + Id;

    /// <summary>Screen-reader summary.</summary>
    public string Announcement => $"{Label}, {Value}";
}
#endregion
