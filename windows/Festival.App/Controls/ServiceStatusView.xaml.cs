using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Service status view
/// <summary>Renders a <see cref="ServiceStatusViewModel"/>.</summary>
public sealed partial class ServiceStatusView : UserControl
{
    /// <summary>Bound status.</summary>
    public static readonly DependencyProperty StatusProperty = DependencyProperty.Register(
        nameof(Status), typeof(ServiceStatusViewModel), typeof(ServiceStatusView), new PropertyMetadata(null, (d, _) => ((ServiceStatusView)d).Bindings.Update()));

    /// <summary>Creates the view.</summary>
    public ServiceStatusView() => InitializeComponent();

    /// <summary>Status to render.</summary>
    public ServiceStatusViewModel? Status
    {
        get => (ServiceStatusViewModel?)GetValue(StatusProperty);
        set => SetValue(StatusProperty, value);
    }
}
#endregion
