using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Carousel dialog
/// <summary>
/// First-run carousel presented in the shared <see cref="FestivalDialog"/> (a modal onboarding sequence; TeachingTip is
/// for single anchored tips). Primary = Next/Done before Secondary = Back, then the standard Close (issue #23); a
/// one-slide guide shows only a full-width Done (operator batch 6.7: no Skip, no disabled Back). Done, Close, Esc and a
/// click outside the dialog all close it and mark only
/// the slides actually viewed as seen. The FlipView's hover arrows are hidden (the buttons and pips page it).
/// </summary>
public sealed partial class FirstRunCarousel : UserControl
{
    /// <summary>Creates the carousel content.</summary>
    /// <param name="carousel">Carousel model.</param>
    public FirstRunCarousel(FirstRunCarouselViewModel carousel)
    {
        Carousel = carousel;
        InitializeComponent();
        PropertyChangedEventHandler announce = (_, e) =>
        {
            if (e.PropertyName == nameof(FirstRunCarouselViewModel.Index) && IsLoaded)
                Services.ScreenReader.Announce(this, new Festival.Core.ViewModels.Announcement(carousel.PositionAnnouncement, Festival.Core.ViewModels.AnnouncementKind.Completed));
        };
        Loaded += (_, _) =>
        {
            carousel.PropertyChanged += announce;
            HideFlipViewArrows();
            FitSlidesHeight();
            // Containers realize after load; activate the first slide's demo once they exist.
            DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
            {
                UpdateActiveDemo();
                // The pips already use system colour pairs under a contrast theme (issue #232); WinUI's automatic text
                // backplate otherwise boxes the selected glyph inside its Highlight fill (issue #239).
                DialogChrome.WithoutBackplate(Pips);
            });
        };
        Unloaded += (_, _) => carousel.PropertyChanged -= announce;
    }

    #region Text-scale fit
    /// <summary>Design height of the slide pane at 100% text (illustration, spacing, title and description).</summary>
    private const double DesignSlidesHeight = 370;

    /// <summary>Height of the demo/illustration area in the item template.</summary>
    private const double IllustrationHeight = 210;

    /// <summary>Item template StackPanel spacing.</summary>
    private const double ItemSpacing = 12;

    /// <summary>Item text width: the 440 content width less the template's 4 + 4 horizontal padding.</summary>
    private const double TextWidth = 432;

    /// <summary>
    /// Grows the FlipView (a fixed-height control: it cannot size to its items) to the tallest slide's title and
    /// description at the current text scale, so text scaling up to 200% never clips copy (issue #232). Sized once for
    /// the whole set so the dialog does not jump while paging; the ContentDialog's own scroller covers short windows.
    /// </summary>
    private void FitSlidesHeight()
    {
        var subtitle = (Style)Application.Current.Resources["SubtitleTextBlockStyle"];
        var tallest = 0d;
        foreach (var slide in Carousel.Slides)
        {
            var text = Measure(new TextBlock { Text = slide.Title, Style = subtitle, TextWrapping = TextWrapping.Wrap })
                + ItemSpacing
                + Measure(new TextBlock { Text = slide.Description, TextWrapping = TextWrapping.Wrap });
            tallest = Math.Max(tallest, text);
        }
        Slides.Height = SlidesHeight(tallest);
    }

    /// <summary>FlipView height for the tallest slide text.</summary>
    /// <param name="tallestText">Tallest measured title + spacing + description height.</param>
    /// <returns>At least <see cref="DesignSlidesHeight"/>.</returns>
    internal static double SlidesHeight(double tallestText) => Math.Max(DesignSlidesHeight, Math.Ceiling(IllustrationHeight + ItemSpacing + tallestText));

    /// <summary>Desired height of an off-tree text block at the item text width.</summary>
    /// <param name="block">Text block.</param>
    /// <returns>Height in effective pixels.</returns>
    private static double Measure(TextBlock block)
    {
        block.Measure(new Windows.Foundation.Size(TextWidth, double.PositiveInfinity));
        return block.DesiredSize.Height;
    }
    #endregion

    /// <summary>
    /// Hides the FlipView's previous/next hover arrows (operator batch 6.7): FlipView toggles their visibility from code on
    /// pointer moves, so they are made transparent and click-through instead of collapsed.
    /// </summary>
    private void HideFlipViewArrows()
    {
        foreach (var button in Descendants(Slides).OfType<Button>())
        {
            if (button.Name is not ("PreviousButtonHorizontal" or "NextButtonHorizontal" or "PreviousButtonVertical" or "NextButtonVertical")) continue;
            button.Opacity = 0;
            button.IsHitTestVisible = false;
        }
    }

    /// <summary>Whether a slide has no live demo (the static illustration shows instead).</summary>
    /// <param name="slideId">Slide ID.</param>
    /// <returns>Collapsed when a demo exists.</returns>
    public static Visibility NoDemo(string slideId) => FirstRunDemos.KindFor(slideId) is null ? Visibility.Visible : Visibility.Collapsed;

    /// <summary>Runs only the visible slide's demo (off-screen FlipView pages hold still).</summary>
    /// <param name="sender">FlipView.</param>
    /// <param name="e">Unused.</param>
    private void OnSlideChanged(object sender, SelectionChangedEventArgs e) => UpdateActiveDemo();

    /// <summary>Marks each realized slide's demo active when its slide is selected.</summary>
    private void UpdateActiveDemo()
    {
        for (var i = 0; i < Slides.Items.Count; i++)
        {
            if (Slides.ContainerFromIndex(i) is not DependencyObject container) continue;
            foreach (var demo in Descendants(container).OfType<FirstRunDemo>()) demo.Active = i == Slides.SelectedIndex;
        }
    }

    /// <summary>Visual-tree descendants.</summary>
    /// <param name="parent">Root.</param>
    /// <returns>Descendants, depth first.</returns>
    private static IEnumerable<DependencyObject> Descendants(DependencyObject parent)
    {
        for (var i = 0; i < Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(parent, i);
            yield return child;
            foreach (var nested in Descendants(child)) yield return nested;
        }
    }

    /// <summary>Carousel model.</summary>
    public FirstRunCarouselViewModel Carousel { get; }

    /// <summary>Whether pips are shown.</summary>
    public bool MultipleSlides => Carousel.Slides.Count > 1;

    /// <summary>Builds the dialog around a carousel; completion happens once, however it closes.</summary>
    /// <param name="carousel">Carousel model.</param>
    /// <param name="root">Window XAML root.</param>
    /// <returns>Dialog to show.</returns>
    public static ContentDialog CreateDialog(FirstRunCarouselViewModel carousel, XamlRoot root)
    {
        var dialog = FestivalDialog.Create(
            root,
            carousel.Title,
            new FirstRunCarousel(carousel),
            "fst.first-run.dialog",
            closeText: carousel.CloseLabel,
            primaryText: carousel.NextLabel,
            secondaryText: carousel.IsSingle ? "" : "Back",
            defaultButton: ContentDialogButton.Primary);
        dialog.IsSecondaryButtonEnabled = !carousel.IsFirst;
        PropertyChangedEventHandler sync = (_, e) =>
        {
            if (e.PropertyName != nameof(FirstRunCarouselViewModel.Index)) return;
            dialog.PrimaryButtonText = carousel.NextLabel;
            dialog.IsSecondaryButtonEnabled = !carousel.IsFirst;
        };
        carousel.PropertyChanged += sync;
        dialog.PrimaryButtonClick += (_, args) => args.Cancel = !carousel.Next();
        dialog.SecondaryButtonClick += (_, args) =>
        {
            args.Cancel = true;
            carousel.PreviousCommand.Execute(null);
        };
        dialog.Closed += (_, _) =>
        {
            carousel.PropertyChanged -= sync;
            carousel.Complete();
        };
        return dialog;
    }
}
#endregion
