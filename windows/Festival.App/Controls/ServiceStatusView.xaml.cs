using System.ComponentModel;
using Festival.App.Services;
using Festival.Core.ViewModels;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Service status view
/// <summary>Renders a <see cref="ServiceStatusViewModel"/> and announces each newly shown issue to Narrator.</summary>
public sealed partial class ServiceStatusView : UserControl
{
    /// <summary>Bound status.</summary>
    public static readonly DependencyProperty StatusProperty = DependencyProperty.Register(
        nameof(Status), typeof(ServiceStatusViewModel), typeof(ServiceStatusView), new PropertyMetadata(null, OnStatusChanged));

    /// <summary>Whether the Retry button is shown (global search hides it, issue #299).</summary>
    public static readonly DependencyProperty ShowsRetryProperty = DependencyProperty.Register(
        nameof(ShowsRetry), typeof(bool), typeof(ServiceStatusView), new PropertyMetadata(true));

    /// <summary>Default automation ID root (spec test IDs <c>fst.service-status.title|countdown|retry</c>).</summary>
    public const string DefaultIdPrefix = "fst.service-status";

    /// <summary>Automation ID root.</summary>
    public static readonly DependencyProperty IdPrefixProperty = DependencyProperty.Register(
        nameof(IdPrefix), typeof(string), typeof(ServiceStatusView), new PropertyMetadata(DefaultIdPrefix, OnIdPrefixChanged));

    private string? lastAnnouncement;
    private bool focusRetryWhenShown;

    /// <summary>Creates the view.</summary>
    public ServiceStatusView()
    {
        InitializeComponent();
        ApplyIds();
        Loaded += (_, _) => QueueAnnouncement();
        // Shown later by a collapsed ancestor becoming visible: announce once it has a size.
        SizeChanged += (_, e) =>
        {
            if (e.PreviousSize.Height <= 0) QueueAnnouncement();
            if (focusRetryWhenShown && e.NewSize.Height > 0) DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () => TryFocusRetry());
        };
    }

    /// <summary>
    /// Moves keyboard focus to Retry now, or as soon as this view is laid out, when a failed reload hid the control
    /// that had focus (<see cref="FailedReloadFocus"/>, issue #283).
    /// </summary>
    public void FocusRetryWhenShown()
    {
        focusRetryWhenShown = true;
        DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () => TryFocusRetry());
    }

    /// <summary>Focuses Retry once it is visible and laid out, then stops waiting.</summary>
    /// <returns>Whether Retry took focus.</returns>
    private bool TryFocusRetry()
    {
        if (!focusRetryWhenShown) return false;
        if (Status is not { HasIssue: true })
        {
            focusRetryWhenShown = false;
            return false;
        }
        if (!IsLoaded || ActualHeight <= 0 || RetryButton.Visibility != Visibility.Visible) return false;
        focusRetryWhenShown = false;
        return RetryButton.Focus(FocusState.Programmatic);
    }

    /// <summary>Status to render.</summary>
    public ServiceStatusViewModel? Status
    {
        get => (ServiceStatusViewModel?)GetValue(StatusProperty);
        set => SetValue(StatusProperty, value);
    }

    /// <summary>Whether the Retry button is shown; the status still retries on its own freeze countdown.</summary>
    public bool ShowsRetry
    {
        get => (bool)GetValue(ShowsRetryProperty);
        set => SetValue(ShowsRetryProperty, value);
    }

    /// <summary>
    /// Automation ID root: <c>&lt;IdPrefix&gt;.title</c>, <c>.countdown</c> and <c>.retry</c>. Only the control lab, which
    /// shows several instances at once, changes it; pages keep the spec IDs.
    /// </summary>
    public string IdPrefix
    {
        get => (string)GetValue(IdPrefixProperty);
        set => SetValue(IdPrefixProperty, value);
    }

    private static void OnIdPrefixChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((ServiceStatusView)d).ApplyIds();

    /// <summary>Applies the heading, countdown and Retry automation IDs.</summary>
    private void ApplyIds()
    {
        var prefix = string.IsNullOrEmpty(IdPrefix) ? DefaultIdPrefix : IdPrefix;
        AutomationProperties.SetAutomationId(TitleBlock, prefix + ".title");
        AutomationProperties.SetAutomationId(CountdownBlock, prefix + ".countdown");
        AutomationProperties.SetAutomationId(RetryButton, prefix + ".retry");
    }

    private static void OnStatusChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var view = (ServiceStatusView)d;
        if (e.OldValue is ServiceStatusViewModel old) old.PropertyChanged -= view.OnStatusPropertyChanged;
        if (e.NewValue is ServiceStatusViewModel current) current.PropertyChanged += view.OnStatusPropertyChanged;
        view.Bindings.Update();
        view.QueueAnnouncement();
    }

    private void OnStatusPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is not (nameof(ServiceStatusViewModel.Issue) or nameof(ServiceStatusViewModel.HasIssue))) return;
        if (Status is not { HasIssue: true }) focusRetryWhenShown = false;
        QueueAnnouncement();
    }

    /// <summary>After layout (so collapsed ancestors are known), speaks the issue once while it is visible.</summary>
    private void QueueAnnouncement() => DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, () =>
    {
        if (Status is not { HasIssue: true } status)
        {
            lastAnnouncement = null;
            return;
        }
        var announcement = Announcement.Failure(status.Title, status.Message);
        if (!IsLoaded || ActualHeight <= 0 || announcement.Text == lastAnnouncement) return;
        lastAnnouncement = announcement.Text;
        ScreenReader.Announce(this, announcement);
    });
}
#endregion
