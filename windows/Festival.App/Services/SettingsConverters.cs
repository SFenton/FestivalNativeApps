using Microsoft.UI.Xaml.Data;

namespace Festival.App.Services;

#region Settings converters
/// <summary>Slider thumb tooltip for the invalid-score leeway, e.g. <c>+1.0%</c>.</summary>
public sealed partial class LeewayThumbConverter : IValueConverter
{
    /// <inheritdoc />
    public object Convert(object value, Type targetType, object parameter, string language) =>
        value is double leeway ? ScoreLeeway.Format(leeway) : "";

    /// <inheritdoc />
    public object ConvertBack(object value, Type targetType, object parameter, string language) =>
        throw new NotSupportedException();
}
#endregion
