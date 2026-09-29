using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App;

#region What's New
/// <summary>
/// The native What's New dialog (web <c>ChangelogModal</c>; Apple <c>WhatsNewSheet</c>): shown once per changelog hash
/// after launch, queued behind a first-run carousel like the web, and replayable from Settings → Version.
/// </summary>
public sealed partial class MainWindow
{
    /// <summary>Delay before the launch check, so the first page's carousel claims the dialog slot first (web order).</summary>
    private static readonly TimeSpan WhatsNewSettleDelay = TimeSpan.FromMilliseconds(700);

    private ChangelogSeenStore? whatsNewStore;
    private bool whatsNewPending;
    private bool whatsNewOpen;

    /// <summary>App version shown in the title and stored on dismissal.</summary>
    private static string AppVersion => typeof(App).Assembly.GetName().Version?.ToString(3) ?? "";

    /// <summary>Resolves the launch gate and schedules the check (called once from the constructor).</summary>
    private void InitializeWhatsNew()
    {
        whatsNewStore = new ChangelogSeenStore(new FileBlobStore(ChangelogSeenStore.DefaultPath));
        var mode = WhatsNewGate.Parse(Environment.GetCommandLineArgs().Skip(1).ToArray(), App.LaunchEnvironment, App.HooksEnabled);
        if (mode == WhatsNewMode.Fresh) whatsNewStore.Reset();
        whatsNewPending = WhatsNewGate.IsPending(mode, whatsNewStore.SeenHash(), Changelog.CurrentHash);
        if (!whatsNewPending) return;
        var timer = DispatcherQueue.CreateTimer();
        timer.Interval = WhatsNewSettleDelay;
        timer.IsRepeating = false;
        timer.Tick += (_, _) => ShowPendingWhatsNew();
        timer.Start();
    }

    /// <summary>Presents the owed launch dialog once the window is visible.</summary>
    private void ShowPendingWhatsNew()
    {
        if (!whatsNewPending) return;
        if (!windowVisible || minimized || RootGrid.XamlRoot is null)
        {
            // Try again shortly: never present into a hidden window.
            DispatcherQueue.TryEnqueue(DispatcherQueuePriority.Low, async () =>
            {
                await Task.Delay(WhatsNewSettleDelay);
                ShowPendingWhatsNew();
            });
            return;
        }
        whatsNewPending = false;
        ShowWhatsNew();
    }

    /// <summary>Shows What's New (launch or the Settings replay) and records the dismissal.</summary>
    public void ShowWhatsNew() => _ = ShowWhatsNewAsync();

    /// <summary>Builds and shows the dialog.</summary>
    /// <returns>Task.</returns>
    private async Task ShowWhatsNewAsync()
    {
        if (whatsNewOpen) return;
        whatsNewOpen = true;
        try
        {
            var dialog = new ContentDialog
            {
                XamlRoot = RootGrid.XamlRoot,
                Title = WhatsNewGate.Title(AppVersion),
                Content = WhatsNewContent(Changelog.DisplayEntries()),
                CloseButtonText = "Dismiss",
                DefaultButton = ContentDialogButton.Close,
                RequestedTheme = ElementTheme.Dark,
            };
            AutomationProperties.SetAutomationId(dialog, "fst.whats-new.dialog");
            await ShowDialogAsync(dialog);
            whatsNewStore?.MarkSeen(AppVersion, Changelog.CurrentHash);
        }
        catch (Exception error) when (error is InvalidOperationException or System.Runtime.InteropServices.COMException)
        {
            Services.CrashLog.Write(error, "What's New dialog");
        }
        finally
        {
            whatsNewOpen = false;
        }
    }

    /// <summary>Title Case headings (level 2) with bullet lists, in a scroller capped to the window.</summary>
    /// <param name="entries">Displayable entries.</param>
    /// <returns>Dialog content.</returns>
    private ScrollViewer WhatsNewContent(IReadOnlyList<ChangelogEntry> entries)
    {
        var panel = new StackPanel { Spacing = 20, Padding = new Thickness(0, 0, 16, 0) };
        foreach (var section in entries.SelectMany(e => e.Sections))
        {
            var block = new StackPanel { Spacing = 8 };
            var heading = new TextBlock { Text = section.DisplayTitle, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"] };
            AutomationProperties.SetHeadingLevel(heading, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level2);
            block.Children.Add(heading);
            foreach (var item in section.Items)
            {
                var row = new Grid { ColumnSpacing = 8 };
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                var bullet = new TextBlock { Text = "•" };
                AutomationProperties.SetAccessibilityView(bullet, Microsoft.UI.Xaml.Automation.Peers.AccessibilityView.Raw);
                var text = new TextBlock { Text = item, TextWrapping = TextWrapping.Wrap };
                Grid.SetColumn(text, 1);
                row.Children.Add(bullet);
                row.Children.Add(text);
                block.Children.Add(row);
            }
            panel.Children.Add(block);
        }
        var scroller = new ScrollViewer { Content = panel, MaxHeight = Math.Max(200, RootGrid.ActualHeight - 240) };
        AutomationProperties.SetAutomationId(scroller, "fst.whats-new.list");
        return scroller;
    }
}
#endregion
