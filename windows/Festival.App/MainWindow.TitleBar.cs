using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App;

#region Title bar caption inset
/// <summary>
/// Keeps <c>TitleBar.RightHeader</c> (search, bell, avatar) at the right edge. The WinUI <c>TitleBar</c> template sizes
/// its <c>RightPaddingColumn</c> from <c>AppWindow.TitleBar.RightInset</c>, which is in physical pixels, without dividing
/// by the rasterization scale: at 150% it reserves 324 px for 216 px of caption buttons, leaving ~72 epx of dead space
/// before the minimize button and, below ~720 epx, squeezing the content column to nothing so the header sits right
/// after the pane toggle. The column is corrected whenever the control (or a DPI change) rewrites it; nothing runs
/// while idle.
/// </summary>
public sealed partial class MainWindow
{
    private ColumnDefinition? rightPaddingColumn;

    /// <summary>Hooks the title bar template once it is applied.</summary>
    private void InitializeTitleBarInset()
    {
        AppTitleBar.Loaded += (_, _) => HookRightPadding();
    }

    /// <summary>Finds the template's right padding column and watches it.</summary>
    private void HookRightPadding()
    {
        if (rightPaddingColumn is not null || VisualTreeHelper.GetChildrenCount(AppTitleBar) == 0) return;
        if (VisualTreeHelper.GetChild(AppTitleBar, 0) is not Grid layoutRoot) return;
        rightPaddingColumn = layoutRoot.FindName("RightPaddingColumn") as ColumnDefinition
                             ?? (layoutRoot.ColumnDefinitions.Count > 0 ? layoutRoot.ColumnDefinitions[^1] : null);
        if (rightPaddingColumn is null) return;
        rightPaddingColumn.RegisterPropertyChangedCallback(ColumnDefinition.WidthProperty, (_, _) => CorrectRightPadding());
        AppTitleBar.XamlRoot.Changed += (_, _) => CorrectRightPadding();
        CorrectRightPadding();
    }

    /// <summary>Sets the padding to the caption buttons' width in epx (a no-op when already right).</summary>
    private void CorrectRightPadding()
    {
        if (rightPaddingColumn is null || AppTitleBar.XamlRoot is not { } root) return;
        var wanted = AppWindow.TitleBar.RightInset / root.RasterizationScale;
        if (Math.Abs(rightPaddingColumn.Width.Value - wanted) > 0.5 || !rightPaddingColumn.Width.IsAbsolute)
            rightPaddingColumn.Width = new GridLength(wanted);
    }
}
#endregion
