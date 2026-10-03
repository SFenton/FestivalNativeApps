using Festival.Core.Domain;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Documents;

namespace Festival.App.Controls;

#region Privacy Policy dialog
/// <summary>
/// Settings → Privacy Policy (issue #98): the shared policy (<c>contracts/privacy-policy.json</c>, bundled as
/// <c>Assets\privacy-policy.json</c>) in the standard <see cref="FestivalDialog"/>, titled "Privacy Policy" with its
/// spanning Close (Esc and an outside click also close it). Native, selectable text that follows the Windows text size;
/// section titles are Narrator headings and HTTPS addresses are hyperlinks. No WebView and no network.
/// </summary>
public static class PrivacyPolicyDialog
{
    /// <summary>Reads and parses the bundled policy.</summary>
    /// <returns>Policy (empty when the file cannot be read).</returns>
    public static PrivacyPolicy Load()
    {
        try
        {
            return PrivacyPolicy.Parse(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, "Assets", PrivacyPolicy.AssetFileName)));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return PrivacyPolicy.Parse(null);
        }
    }

    /// <summary>Shows the policy and returns once it closes.</summary>
    /// <param name="root">Window XAML root.</param>
    /// <returns>Task.</returns>
    public static async Task ShowAsync(XamlRoot root)
    {
        var policy = Load();
        var dialog = FestivalDialog.Create(root, policy.Title, Content(policy, root), "fst.privacy-policy.dialog", closeAutomationId: "fst.privacy-policy.close");
        await FestivalDialog.ShowAsync(dialog);
    }

    /// <summary>Effective date, then each section's heading (level 2), paragraphs and bullets, in a scroller capped to the window.</summary>
    /// <param name="policy">Policy.</param>
    /// <param name="root">Window XAML root (height cap).</param>
    /// <returns>Dialog content.</returns>
    private static FrameworkElement Content(PrivacyPolicy policy, XamlRoot root)
    {
        var panel = new StackPanel { Spacing = 20, Padding = new Thickness(8, 6, 16, 6) };
        if (policy.IsEmpty)
        {
            panel.Children.Add(new TextBlock { Text = "The privacy policy could not be loaded.", TextWrapping = TextWrapping.Wrap });
        }
        if (!string.IsNullOrWhiteSpace(policy.EffectiveDateText))
        {
            var date = new TextBlock { Text = policy.EffectiveDateText, Style = (Style)Application.Current.Resources["CaptionTextBlockStyle"], TextWrapping = TextWrapping.Wrap };
            AutomationProperties.SetAutomationId(date, "fst.privacy-policy.effective-date");
            panel.Children.Add(date);
        }
        foreach (var section in policy.Sections)
        {
            var block = new StackPanel { Spacing = 8 };
            AutomationProperties.SetAutomationId(block, $"fst.privacy-policy.section.{section.Id}");
            var heading = new TextBlock { Text = section.Title, Style = (Style)Application.Current.Resources["BodyStrongTextBlockStyle"], TextWrapping = TextWrapping.Wrap };
            AutomationProperties.SetHeadingLevel(heading, AutomationHeadingLevel.Level2);
            block.Children.Add(heading);
            foreach (var body in section.Blocks)
            {
                if (!body.IsBullets)
                {
                    block.Children.Add(Paragraph(body.Text));
                    continue;
                }
                foreach (var item in body.Items)
                {
                    var row = new Grid { ColumnSpacing = 8 };
                    row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                    row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                    var bullet = new TextBlock { Text = "•" };
                    AutomationProperties.SetAccessibilityView(bullet, AccessibilityView.Raw);
                    var text = Paragraph(item);
                    Grid.SetColumn(text, 1);
                    row.Children.Add(bullet);
                    row.Children.Add(text);
                    block.Children.Add(row);
                }
            }
            panel.Children.Add(block);
        }
        var height = root.Size.Height;
        // A tab stop, so the dialog opens focused on the text (arrow/Page keys scroll) rather than its last hyperlink.
        var scroller = new ScrollViewer { Content = panel, IsTabStop = true, MaxHeight = Math.Max(200, (double.IsNaN(height) ? 640 : height) - 240) };
        AutomationProperties.SetAutomationId(scroller, "fst.privacy-policy.content");
        AutomationProperties.SetName(scroller, policy.Title);
        return scroller;
    }

    /// <summary>A wrapped, selectable paragraph whose HTTPS addresses are hyperlinks.</summary>
    /// <param name="text">Text.</param>
    /// <returns>Text block.</returns>
    private static TextBlock Paragraph(string text)
    {
        var block = new TextBlock { TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true };
        foreach (var (run, link) in PrivacyPolicy.Runs(text))
        {
            if (link is null)
            {
                block.Inlines.Add(new Run { Text = run });
                continue;
            }
            var hyperlink = new Hyperlink { NavigateUri = link };
            hyperlink.Inlines.Add(new Run { Text = run });
            block.Inlines.Add(hyperlink);
        }
        return block;
    }
}
#endregion
