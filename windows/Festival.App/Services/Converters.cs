using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;

namespace Festival.App.Services;

#region Converters
/// <summary>Maps <see langword="true"/> to <see cref="Visibility.Collapsed"/>.</summary>
public sealed partial class InverseVisibilityConverter : IValueConverter
{
    /// <inheritdoc />
    public object Convert(object value, Type targetType, object parameter, string language) =>
        value is true ? Visibility.Collapsed : Visibility.Visible;

    /// <inheritdoc />
    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        value is Visibility.Collapsed;
}
#endregion
