using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Festival.Core.ViewModels;

#region Center
/// <summary>
/// App-wide first-run arbiter: evaluates a page's unseen gate-passing slides, owns the single active carousel
/// (web <c>activeCarouselKey</c>) and persists seen-state when a carousel closes. One per session, UI thread only.
/// </summary>
/// <param name="store">Seen-state persistence.</param>
/// <param name="mode">Launch mode (Debug defaults to <see cref="FirstRunMode.Off"/>).</param>
/// <param name="time">Clock for <c>seenAt</c>.</param>
public sealed class FirstRunCenter(FirstRunSeenStore store, FirstRunMode mode = FirstRunMode.Normal, TimeProvider? time = null)
{
    private readonly TimeProvider clock = time ?? TimeProvider.System;
    private readonly HashSet<FirstRunPageKey> closedThisSession = [];

    /// <summary>Launch mode.</summary>
    public FirstRunMode Mode { get; } = mode;

    /// <summary>The carousel currently shown, if any.</summary>
    public FirstRunCarouselViewModel? Active { get; private set; }

    /// <summary>Seen-state persistence.</summary>
    public FirstRunSeenStore Store { get; } = store;

    /// <summary>
    /// Gate facts for a page. The web Shop page passes <c>{hasPlayer: false, shopHighlightEnabled: true}</c>
    /// regardless of settings (<c>ShopPage.tsx:141</c>).
    /// </summary>
    /// <param name="page">Page.</param>
    /// <param name="settings">Current settings.</param>
    /// <returns>Context.</returns>
    public FirstRunGateContext Context(FirstRunPageKey page, AppSettings settings) => page == FirstRunPageKey.Shop
        ? new FirstRunGateContext(HasPlayer: false, ShopHighlightEnabled: true, AlwaysShow: Mode == FirstRunMode.Force)
        : new FirstRunGateContext(
            HasPlayer: settings.SelectedPlayer is not null,
            ShopHighlightEnabled: settings.ShopHighlightEnabled,
            ExperimentalRanksEnabled: settings.ExperimentalRanks,
            AlwaysShow: Mode == FirstRunMode.Force);

    /// <summary>Slides a page visit would show now (nothing while <see cref="FirstRunMode.Off"/>).</summary>
    /// <param name="page">Page.</param>
    /// <param name="settings">Current settings.</param>
    /// <returns>Unseen gate-passing slides.</returns>
    public IReadOnlyList<FirstRunSlide> PendingSlides(FirstRunPageKey page, AppSettings settings) =>
        Mode == FirstRunMode.Off ? [] : FirstRunSlideEvaluator.UnseenSlides(FirstRunCatalog.Slides(page), Context(page, settings), Store.Load());

    /// <summary>Claims the single carousel slot for a page visit.</summary>
    /// <param name="page">Visible page.</param>
    /// <param name="settings">Current settings.</param>
    /// <returns>The carousel to present, or <see langword="null"/> when nothing is pending or another carousel is showing.</returns>
    public FirstRunCarouselViewModel? TryBegin(FirstRunPageKey page, AppSettings settings)
    {
        // A page's carousel shows at most once per session: slides the user closed without viewing come back on the next
        // launch, not on the next settings change or navigation (Settings replay is unaffected).
        if (Active is not null || closedThisSession.Contains(page)) return null;
        var slides = PendingSlides(page, settings);
        if (slides.Count == 0) return null;
        return Active = new FirstRunCarouselViewModel(this, page, slides, isReplay: false);
    }

    /// <summary>Settings "Show": resets the page and shows every slide, ignoring gates and seen-state (web <c>getAllSlides</c>).</summary>
    /// <param name="page">Page to replay.</param>
    /// <returns>The replay carousel, or <see langword="null"/> while another carousel is showing.</returns>
    public FirstRunCarouselViewModel? BeginReplay(FirstRunPageKey page)
    {
        if (Active is not null) return null;
        var slides = FirstRunSlideEvaluator.AllSlides(FirstRunCatalog.Slides(page));
        Store.ResetPage(slides.Select(s => s.Id));
        return Active = new FirstRunCarouselViewModel(this, page, slides, isReplay: true);
    }

    /// <summary>
    /// Marks the slides the user actually viewed as seen and frees the slot (Done, Esc or a click outside alike). Slides
    /// the user never paged to stay unseen and come back on the next visit (operator batch 6.7).
    /// </summary>
    /// <param name="carousel">Closing carousel.</param>
    internal void Complete(FirstRunCarouselViewModel carousel)
    {
        Store.MarkSeen(carousel.ViewedSlides, clock.GetUtcNow());
        closedThisSession.Add(carousel.Page);
        if (ReferenceEquals(Active, carousel)) Active = null;
    }
}
#endregion

#region Carousel
/// <summary>One carousel: paging, position announcement and completion.</summary>
public sealed partial class FirstRunCarouselViewModel : ObservableObject
{
    private readonly FirstRunCenter center;
    private readonly SortedSet<int> viewed = [0];

    /// <summary>Creates a carousel.</summary>
    /// <param name="center">Owning center.</param>
    /// <param name="page">Page.</param>
    /// <param name="slides">Slides to show (never empty).</param>
    /// <param name="isReplay">Settings replay rather than a first visit.</param>
    internal FirstRunCarouselViewModel(FirstRunCenter center, FirstRunPageKey page, IReadOnlyList<FirstRunSlide> slides, bool isReplay)
    {
        this.center = center;
        Page = page;
        Slides = [.. slides];
        IsReplay = isReplay;
    }

    /// <summary>Page.</summary>
    public FirstRunPageKey Page { get; }

    /// <summary>Slides in display order (concrete list for XAML binding).</summary>
    public List<FirstRunSlide> Slides { get; }

    /// <summary>Whether this is a Settings replay.</summary>
    public bool IsReplay { get; }

    /// <summary>Whether the carousel has been completed.</summary>
    public bool IsCompleted { get; private set; }

    /// <summary>Dialog title.</summary>
    public string Title => Page.Label();

    /// <summary>Current slide index.</summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(Current), nameof(PositionText), nameof(PositionAnnouncement), nameof(IsFirst), nameof(IsLast), nameof(NextLabel))]
    [NotifyCanExecuteChangedFor(nameof(PreviousCommand))]
    private int index;

    /// <summary>Current slide.</summary>
    public FirstRunSlide Current => Slides[Index];

    /// <summary>Narrator position, e.g. "Slide 2 of 5" (spoken only; the dialog shows pips, like the web).</summary>
    public string PositionText => $"Slide {Index + 1} of {Slides.Count}";

    /// <summary>Spoken when the slide changes from the dialog buttons or pips, e.g. "Sort Songs, slide 2 of 5".</summary>
    public string PositionAnnouncement => $"{Current.Title}, {PositionText.ToLowerInvariant()}";

    /// <summary>Whether the first slide is shown.</summary>
    public bool IsFirst => Index == 0;

    /// <summary>Whether the carousel has a single slide (the dialog then offers only Done).</summary>
    public bool IsSingle => Slides.Count == 1;

    /// <summary>Slides shown so far, in display order: the ones completion marks seen.</summary>
    public IReadOnlyList<FirstRunSlide> ViewedSlides => [.. viewed.Select(i => Slides[i])];

    /// <summary>Records each slide the user reaches.</summary>
    /// <param name="value">New index.</param>
    partial void OnIndexChanged(int value) => viewed.Add(value);

    /// <summary>Whether the last slide is shown.</summary>
    public bool IsLast => Index == Slides.Count - 1;

    /// <summary>Primary button text.</summary>
    public string NextLabel => IsLast ? "Done" : "Next";

    /// <summary>
    /// Dialog Close button text: the standard Close (issue #23) whenever Next/Back page the carousel; a one-slide guide
    /// shows only its full-width Done, which already closes it.
    /// </summary>
    public string CloseLabel => IsSingle ? "" : ModalCommands.Close;

    /// <summary>
    /// Dialog Secondary (Back) button text: present on every slide of a multi-slide guide and only disabled on the first
    /// (<see cref="PreviousCommand"/>), so ContentDialog never re-lays out its command columns under the pointer
    /// (issue #241); a one-slide guide has no Back.
    /// </summary>
    public string BackLabel => IsSingle ? "" : "Back";

    /// <summary>Selects a slide, clamped to range.</summary>
    /// <param name="value">Requested index.</param>
    public void GoTo(int value) => Index = Math.Clamp(value, 0, Slides.Count - 1);

    /// <summary>Advances; on the last slide completes.</summary>
    /// <returns><see langword="true"/> when the carousel completed and should close.</returns>
    public bool Next()
    {
        if (!IsLast)
        {
            Index++;
            return false;
        }
        Complete();
        return true;
    }

    /// <summary>Goes back one slide.</summary>
    [RelayCommand(CanExecute = nameof(CanGoBack))]
    private void Previous() => GoTo(Index - 1);

    /// <summary>Whether Back is available.</summary>
    /// <returns><see langword="true"/> after the first slide.</returns>
    private bool CanGoBack() => !IsFirst;

    /// <summary>Closes (Done, Esc, a click outside): marks the viewed slides seen once.</summary>
    public void Complete()
    {
        if (IsCompleted) return;
        IsCompleted = true;
        center.Complete(this);
    }
}
#endregion
