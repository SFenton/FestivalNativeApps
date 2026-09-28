using System.ComponentModel;
using Festival.App.Services;
using Festival.Core.ViewModels;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Service status view
/// <summary>Renders a <see cref="ServiceStatusViewModel"/> and announces each newly shown issue to Narrator.</summary>
public sealed partial class ServiceStatusView : UserControl
{
    /// <summary>Bound status.</summary>
    public static readonly DependencyProperty StatusProperty = DependencyProperty.Register(
        nameof(Status), typeof(ServiceStatusViewModel), typeof(ServiceStatusView), new PropertyMetadata(null, OnStatusChanged));

    private string? lastAnnouncement;

    /// <summary>Creates the view.</summary>
    public ServiceStatusView()
    {
        InitializeComponent();
        Loaded += (_, _) => QueueAnnouncement();
        // Shown later by a collapsed ancestor becoming visible: announce once it has a size.
        SizeChanged += (_, e) =>
        {
            if (e.PreviousSize.Height <= 0) QueueAnnouncement();
        };
    }

    /// <summary>Status to render.</summary>
    public ServiceStatusViewModel? Status
    {
        get => (ServiceStatusViewModel?)GetValue(StatusProperty);
        set => SetValue(StatusProperty, value);
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
        if (e.PropertyName is nameof(ServiceStatusViewModel.Issue) or nameof(ServiceStatusViewModel.HasIssue)) QueueAnnouncement();
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
