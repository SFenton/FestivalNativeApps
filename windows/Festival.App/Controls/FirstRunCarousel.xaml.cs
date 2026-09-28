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
