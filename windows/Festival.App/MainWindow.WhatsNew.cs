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

    /// <summary>
    /// How this copy was installed: only a Store-signed package shows the release notes; unpackaged and sideloaded builds
    /// show the tester notes. Resolved synchronously, so the Settings replay never shows a pending channel.
    /// </summary>
    private InstallChannel whatsNewChannel = InstallChannel.Store;

    /// <summary>Whether the visible page's first-run check has run: What's New waits for it so a carousel goes first.</summary>
    private bool firstRunEvaluated;

    /// <summary>Launch-check timer, held in a field: a local timer was collected before it fired, so the launch dialog never showed.</summary>
    private DispatcherQueueTimer? whatsNewTimer;

    /// <summary>App version shown in the title and stored on dismissal.</summary>
    private static string AppVersion => Festival.Core.Domain.AppVersionInfo.Display(typeof(App).Assembly);

    /// <summary>Resolves the launch gate and schedules the check (called once from the constructor).</summary>
    private void InitializeWhatsNew()
    {
        whatsNewStore = new ChangelogSeenStore(new FileBlobStore(ChangelogSeenStore.DefaultPath));
        var args = Environment.GetCommandLineArgs().Skip(1).ToArray();
        whatsNewChannel = InstallChannels.Resolve(args, App.LaunchEnvironment, App.HooksEnabled,
            () => Windows.ApplicationModel.Package.Current.SignatureKind.ToString());
        var mode = WhatsNewGate.Parse(args, App.LaunchEnvironment, App.HooksEnabled);
        if (mode == WhatsNewMode.Fresh) whatsNewStore.Reset();
        whatsNewPending = WhatsNewGate.IsPending(mode, whatsNewStore.SeenHash(), Changelog.CurrentHash);
        if (!whatsNewPending) return;
        whatsNewTimer = DispatcherQueue.CreateTimer();
        whatsNewTimer.Interval = WhatsNewSettleDelay;
        whatsNewTimer.IsRepeating = false;
        whatsNewTimer.Tick += (_, _) =>
        {
            whatsNewTimer = null;
            ShowPendingWhatsNew();
        };
        whatsNewTimer.Start();
    }

    /// <summary>Presents the owed launch dialog once the window is visible.</summary>
    private void ShowPendingWhatsNew()
    {
        if (!whatsNewPending) return;
        // The first page's carousel claims the dialog slot first (web order): wait until its check has run, however long
        // the launch took, as well as for a visible window.
        if (!windowVisible || minimized || RootGrid.XamlRoot is null || (firstRun is not null && !firstRunEvaluated))
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
            // Dismiss spans the command row, centred like the web's full-width button (operator batch 6.14).
            var dialog = Controls.FestivalDialog.Create(
                RootGrid.XamlRoot,
                WhatsNewGate.Title(AppVersion),
                WhatsNewContent(Changelog.DisplayBlocks(whatsNewChannel)),
                "fst.whats-new.dialog",
                closeText: "Dismiss");
            await Controls.FestivalDialog.ShowAsync(dialog);
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

    /// <summary>
    /// Version headings (level 2), each with its notes under category headings (level 3, web changelog order, "Other"
    /// last; none when nothing is categorized), in a scroller capped to the window.
    /// </summary>
    /// <param name="blocks">Displayable blocks.</param>
    /// <returns>Dialog content.</returns>
    private ScrollViewer WhatsNewContent(IReadOnlyList<WhatsNewBlock> blocks)
    {
        var panel = new StackPanel { Spacing = 24, Padding = new Thickness(0, 0, 16, 0) };
        foreach (var entry in blocks)
        {
            var block = new StackPanel { Spacing = 12 };
            var heading = new TextBlock { Text = entry.Title, Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"], TextWrapping = TextWrapping.Wrap };
            AutomationProperties.SetHeadingLevel(heading, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level2);
            block.Children.Add(heading);
            foreach (var group in entry.Groups)
            {
                var section = new StackPanel { Spacing = 8 };
                if (entry.Headed)
                {
                    var category = new TextBlock { Text = group.DisplayTitle, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"], TextWrapping = TextWrapping.Wrap };
                    AutomationProperties.SetHeadingLevel(category, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level3);
                    section.Children.Add(category);
                }
                foreach (var item in group.Items)
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
                    section.Children.Add(row);
                }
                block.Children.Add(section);
            }
            panel.Children.Add(block);
        }
        var scroller = new ScrollViewer { Content = panel, MaxHeight = Math.Max(200, RootGrid.ActualHeight - 240) };
        AutomationProperties.SetAutomationId(scroller, "fst.whats-new.list");
        return scroller;
    }
}
#endregion
