using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.System;
using Windows.UI.ViewManagement;

namespace Festival.App;

#region Shell accessibility
/// <summary>
/// Shell keyboard and screen-reader affordances: Ctrl+1…7 / Ctrl+comma section accelerators with tooltips, Ctrl+Shift+P
/// for the profile picker, Alt access keys
/// on pane items, UIA landmarks (main content, search), no stray tab stop on the title bar itself, focus entering the pane
/// on the selected section, and a contrast-theme hook for the artwork backdrop.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>System contrast-theme state (decorative artwork is hidden while a contrast theme is on).</summary>
    private readonly AccessibilitySettings accessibilitySettings = new();

    /// <summary>Registers the section accelerators and landmarks (called once from the constructor).</summary>
    private void InitializeAccessibility()
    {
        // AccessibilitySettings.HighContrastChanged needs a CoreWindow (subscribing throws 0x80070490 in a desktop app);
        // switching contrast themes raises ColorValuesChanged, after which HighContrast is re-read.
        uiSettings.ColorValuesChanged += (_, _) => DispatcherQueue.TryEnqueue(() =>
        {
            ApplyContrastBackground();
            ApplyCaptionColors();
            UpdateBackdropPolicy();
        });
        ApplyContrastBackground();
        uiSettings.TextScaleFactorChanged += (_, _) => DispatcherQueue.TryEnqueue(ApplyTextScale);
        ApplyTextScale();
        for (var digit = 1; digit <= 7; digit++)
        {
            var position = digit;
            RootGrid.KeyboardAccelerators.Add(Accelerator(VirtualKey.Number1 + (position - 1), VirtualKeyModifiers.Control, () => ShowShortcut(position)));
        }
        RootGrid.KeyboardAccelerators.Add(Accelerator((VirtualKey)KeyboardShortcuts.CommaKey, VirtualKeyModifiers.Control, () => Show(AppSection.Settings)));
        RootGrid.KeyboardAccelerators.Add(Accelerator(VirtualKey.P, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, OpenProfilePicker));

        // The TitleBar control is focusable by default, which adds an empty Tab stop between the page and the title bar buttons.
        AppTitleBar.IsTabStop = false;
        AutomationProperties.SetLandmarkType(FrameHost, AutomationLandmarkType.Main);
        AutomationProperties.SetName(FrameHost, "Page content");
        AutomationProperties.SetLandmarkType(GlobalSearchBox, AutomationLandmarkType.Search);
        ExposeSearchAccelerator();
        ProfileButton.AccessKey = "P";

        // Alt+Left must go back from anywhere, but a focused TextBox handles Left in KeyDown before the window's
        // accelerator sees it; the tunneling PreviewKeyDown runs first.
        RootGrid.PreviewKeyDown += (_, e) =>
        {
            if (e.Key == VirtualKey.Left && e.KeyStatus.IsMenuKeyDown && GoBack()) e.Handled = true;
        };
        Nav.GettingFocus += OnNavGettingFocus;
    }

    /// <summary>
    /// Sends focus that enters the pane from outside it to the selected section. NavigationView only does this for a Tab
    /// key that passes through the NavigationView itself, but Back, the pane toggle, search and profile live in the
    /// separate TitleBar, so Tab from there (and the minimal overlay pane opening) would otherwise land on the first item.
    /// </summary>
    /// <param name="sender">Navigation view.</param>
    /// <param name="args">Focus change.</param>
    private void OnNavGettingFocus(UIElement sender, GettingFocusEventArgs args)
    {
        if (args.NewFocusedElement is not NavigationViewItem { Tag: AppSection target }
            || Nav.SelectedItem is not NavigationViewItem { Tag: AppSection selected } selectedItem)
        {
            return;
        }
        var keyboardMove = args.InputDevice == FocusInputDeviceKind.Keyboard
            && args.Direction is FocusNavigationDirection.Next or FocusNavigationDirection.Previous;
        // Opening the overlay pane focuses its first item programmatically: no direction, and the device is the last input
        // (keyboard) or none. Pointer focus also has no direction, so it is excluded to leave clicks alone.
        var paneOpening = Nav.DisplayMode == NavigationViewDisplayMode.Minimal
            && args.Direction == FocusNavigationDirection.None
            && args.InputDevice is FocusInputDeviceKind.None or FocusInputDeviceKind.Keyboard;
        if (PaneFocus.ShouldRedirect(target, selected, keyboardMove || paneOpening, InsidePaneItem(args.OldFocusedElement))
            && args.TrySetNewFocusedElement(selectedItem))
        {
            args.Handled = true;
        }
    }

    /// <summary>Whether <paramref name="element"/> is a pane item or inside one.</summary>
    /// <param name="element">Previously focused element.</param>
    /// <returns><see langword="true"/> for focus moving within the pane.</returns>
    private static bool InsidePaneItem(DependencyObject? element)
    {
        for (var node = element; node is not null; node = VisualTreeHelper.GetParent(node))
        {
            if (node is NavigationViewItemBase) return true;
        }
        return false;
    }

    /// <summary>
    /// Reports Ctrl+E as the UIA AcceleratorKey of both global-search entry points (the accelerator lives on
    /// <c>RootGrid</c>, so WinUI exposes it on neither). The box's focus target is its inner <c>TextBox</c>, which only
    /// exists once the template is applied, and the box starts collapsed at compact widths.
    /// </summary>
    private void ExposeSearchAccelerator()
    {
        const string ctrlE = "Control+E";
        AutomationProperties.SetAcceleratorKey(GlobalSearchButton, ctrlE);
        AutomationProperties.SetAcceleratorKey(GlobalSearchBox, ctrlE);
        GlobalSearchBox.Loaded += (_, _) =>
        {
            GlobalSearchBox.ApplyTemplate();
            if (FindTextBox(GlobalSearchBox) is { } text) AutomationProperties.SetAcceleratorKey(text, ctrlE);
        };
    }

    /// <summary>Under a contrast theme the backdrop's brand base colour gives way to the theme's window colour.</summary>
    private void ApplyContrastBackground() => Backdrop.Background = accessibilitySettings.HighContrast
        ? new SolidColorBrush(uiSettings.UIElementColor(UIElementType.Window))
        : (Brush)Application.Current.Resources["FSTAppBackgroundBrush"];

    /// <summary>
    /// At large Windows text sizes (≥150%) the title-bar caption text would squeeze the global search box to a sliver; the
    /// caption is dropped there (the window title, taskbar and Alt+Tab still name the app).
    /// </summary>
    private void ApplyTextScale() => AppTitleBar.Title = uiSettings.TextScaleFactor >= 1.5 ? "" : WindowTitles.Brand;

    /// <summary>Opens the <paramref name="position"/>-th visible pane section (Ctrl+digit).</summary>
    /// <param name="position">1-based pane position.</param>
    private void ShowShortcut(int position)
    {
        var shortcut = KeyboardShortcuts.For(Shell.Sections).FirstOrDefault(s => s.Digit == position);
        if (shortcut.ToolTip is not null) Show(shortcut.Section);
    }

    /// <summary>Applies tooltips, accelerator names and access keys to the current pane items (after each rebuild).</summary>
    private void ApplySectionShortcuts()
    {
        var items = Nav.MenuItems.OfType<NavigationViewItem>().ToList();
        if (Nav.SettingsItem is NavigationViewItem settings) items.Add(settings);
        var shortcuts = KeyboardShortcuts.For(Shell.Sections);
        foreach (var item in items)
        {
            if (item.Tag is not AppSection section) continue;
            var shortcut = shortcuts.FirstOrDefault(s => s.Section == section);
            if (shortcut.ToolTip is null) continue;
            ToolTipService.SetToolTip(item, shortcut.ToolTip);
            AutomationProperties.SetAcceleratorKey(item, shortcut.Digit is { } d ? $"Control+{d}" : "Control+Comma");
            if (item.AccessKey.Length == 0)
            {
                item.AccessKeyInvoked += (_, e) =>
                {
                    e.Handled = true;
                    Show(section);
                };
            }
            item.AccessKey = shortcut.AccessKey;
        }
    }
}
#endregion
