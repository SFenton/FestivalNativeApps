using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App;

#region Title bar caption inset, colours and drag regions
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
    private bool dragRegionRefreshQueued;

    /// <summary>Hooks the title bar template once it is applied and colours the caption buttons.</summary>
    private void InitializeTitleBarInset()
    {
        AppTitleBar.Loaded += (_, _) => HookRightPadding();
        ApplyCaptionColors();
        // Issue #271: the title-bar elements move or resize after the TitleBar's own refresh points (see below).
        RootGrid.SizeChanged += (_, _) => QueueDragRegionRefresh();
        TitleBarRightHeader.SizeChanged += (_, _) => QueueDragRegionRefresh();
        GlobalSearchBox.SizeChanged += (_, _) => QueueDragRegionRefresh();
        AppTitleBar.RegisterPropertyChangedCallback(TitleBar.TitleProperty, (_, _) => QueueDragRegionRefresh());
    }

    /// <summary>
    /// Recomputes the title bar's passthrough (clickable) regions once the current layout settles. The WinUI
    /// <c>TitleBar</c> measures them only on its own size, content and property changes (<c>AutoRefreshDragRegions</c>
    /// is off: it walks the tree on every layout pass), but the search box/button swap and box width
    /// (<c>ApplySearchWidth</c>), the bell appearing with a player and the caption dropped at large text sizes all
    /// move title-bar elements a layout pass later. Without this, part of the Search button (compact), or the whole
    /// search box after resizing up from compact, stays a drag region and a press moves the window instead of
    /// activating it (WinUI TitleBar spec: "Call RecomputeDragRegions() in code-behind after making dynamic changes").
    /// Coalesced: one recompute per dispatcher turn, so a drag-resize does not queue one per size step.
    /// </summary>
    private void QueueDragRegionRefresh()
    {
        if (dragRegionRefreshQueued) return;
        dragRegionRefreshQueued = DispatcherQueue.TryEnqueue(Microsoft.UI.Dispatching.DispatcherQueuePriority.Low, () =>
        {
            dragRegionRefreshQueued = false;
            AppTitleBar.RecomputeDragRegions();
        });
    }

    /// <summary>
    /// The caption buttons sit on the dimmed artwork rather than Mica, so their glyphs are white (70% when the window is
    /// inactive, instead of the system's faint gray) over transparent backgrounds with Fluent subtle hover/pressed fills.
    /// Contrast themes get the system caption colours back.
    /// </summary>
    private void ApplyCaptionColors()
    {
        var bar = AppWindow.TitleBar;
        if (accessibilitySettings.HighContrast)
        {
            bar.ButtonBackgroundColor = bar.ButtonInactiveBackgroundColor = bar.ButtonForegroundColor = bar.ButtonHoverForegroundColor =
                bar.ButtonPressedForegroundColor = bar.ButtonInactiveForegroundColor = bar.ButtonHoverBackgroundColor =
                bar.ButtonPressedBackgroundColor = null;
            return;
        }
        bar.ButtonBackgroundColor = bar.ButtonInactiveBackgroundColor = Microsoft.UI.Colors.Transparent;
        bar.ButtonForegroundColor = bar.ButtonHoverForegroundColor = bar.ButtonPressedForegroundColor = Microsoft.UI.Colors.White;
        bar.ButtonInactiveForegroundColor = Windows.UI.Color.FromArgb(0xB3, 0xFF, 0xFF, 0xFF);
        bar.ButtonHoverBackgroundColor = Windows.UI.Color.FromArgb(0x1A, 0xFF, 0xFF, 0xFF);
        bar.ButtonPressedBackgroundColor = Windows.UI.Color.FromArgb(0x0F, 0xFF, 0xFF, 0xFF);
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
        {
            rightPaddingColumn.Width = new GridLength(wanted);
            QueueDragRegionRefresh();
        }
    }
}
#endregion
