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
            var title = WhatsNewGate.Title(AppVersion);
            var notes = WhatsNewContent(Changelog.DisplayBlocks(whatsNewChannel), title);
            var dialog = Controls.FestivalDialog.Create(
                RootGrid.XamlRoot,
                title,
                notes,
                "fst.whats-new.dialog",
                closeText: "Dismiss",
                closeAutomationId: "fst.whats-new.dismiss");
            dialog.Opened += (_, _) => notes.Focus(FocusState.Programmatic);
            // Refit while open: a window resized across breakpoints would otherwise clip long notes (FeedbackDialog).
            var root = RootGrid.XamlRoot;
            void Refit(XamlRoot sender, XamlRootChangedEventArgs args) => notes.MaxHeight = WhatsNewNotesHeight(sender.Size.Height);
            root.Changed += Refit;
            try
            {
                await Controls.FestivalDialog.ShowAsync(dialog);
            }
            finally
            {
                root.Changed -= Refit;
            }
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
    /// last; none when nothing is categorized), in a named, focusable scroller capped to the window.
    /// </summary>
    /// <param name="blocks">Displayable blocks.</param>
    /// <param name="title">Dialog title, also the scroller's UI Automation name.</param>
    /// <returns>Dialog content.</returns>
    private ScrollViewer WhatsNewContent(IReadOnlyList<WhatsNewBlock> blocks, string title)
    {
        // Inset so the scroller's focus rectangle and scrollbar don't cover the first and last glyphs.
        var panel = new StackPanel { Spacing = 24, Padding = new Thickness(8, 4, 16, 4) };
        for (var b = 0; b < blocks.Count; b++)
        {
            var entry = blocks[b];
            var block = new StackPanel { Spacing = 12 };
            var heading = new TextBlock { Text = entry.Title, Style = (Style)Application.Current.Resources["SubtitleTextBlockStyle"], TextWrapping = TextWrapping.Wrap };
            AutomationProperties.SetHeadingLevel(heading, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level2);
            AutomationProperties.SetAutomationId(heading, $"fst.whats-new.section.{b}");
            block.Children.Add(heading);
            for (var g = 0; g < entry.Groups.Count; g++)
            {
                var group = entry.Groups[g];
                var section = new StackPanel { Spacing = 8 };
                if (entry.Headed)
                {
                    var category = new TextBlock { Text = group.DisplayTitle, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"], TextWrapping = TextWrapping.Wrap };
                    AutomationProperties.SetHeadingLevel(category, Microsoft.UI.Xaml.Automation.Peers.AutomationHeadingLevel.Level3);
                    AutomationProperties.SetAutomationId(category, $"fst.whats-new.group.{b}.{g}");
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
        // A tab stop that opens focused, so arrow and Page keys scroll long notes (ContentDialog's own scroller is
        // vertically disabled and the notes hold no other focusable element; Licenses and Privacy Policy do the same).
        var scroller = new ScrollViewer { Content = panel, IsTabStop = true, MaxHeight = WhatsNewNotesHeight(RootGrid.ActualHeight) };
        AutomationProperties.SetAutomationId(scroller, "fst.whats-new.list");
        AutomationProperties.SetName(scroller, title);
        return scroller;
    }

    /// <summary>Notes scroller height for a window: its height less the dialog's title and command rows, at least 200.</summary>
    /// <param name="windowHeight">Window content height in epx.</param>
    /// <returns>Maximum height in epx.</returns>
    private static double WhatsNewNotesHeight(double windowHeight) => Math.Max(200, windowHeight - 240);
}
#endregion
