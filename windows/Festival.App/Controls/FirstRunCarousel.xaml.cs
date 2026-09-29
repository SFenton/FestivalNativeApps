using System.ComponentModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Carousel dialog
/// <summary>
/// First-run carousel presented in a Fluent <see cref="ContentDialog"/> (a modal onboarding sequence; TeachingTip is
/// for single anchored tips). Primary = Next/Done, Secondary = Back, Close = Skip; Esc and Skip mark every displayed
/// slide seen, like Done.
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
            // Containers realize after load; activate the first slide's demo once they exist.
            DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, UpdateActiveDemo);
        };
        Unloaded += (_, _) => carousel.PropertyChanged -= announce;
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
        var content = new FirstRunCarousel(carousel);
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = carousel.Title,
            Content = content,
            PrimaryButtonText = carousel.NextLabel,
            SecondaryButtonText = "Back",
            CloseButtonText = "Skip",
            DefaultButton = ContentDialogButton.Primary,
            IsSecondaryButtonEnabled = !carousel.IsFirst,
            RequestedTheme = ElementTheme.Dark,
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetAutomationId(dialog, "fst.first-run.dialog");
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
