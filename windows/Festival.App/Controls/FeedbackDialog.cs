using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
using Windows.Storage.FileProperties;

namespace Festival.App.Controls;

#region Feedback dialog
/// <summary>
/// Settings → Report an Issue / Request a Feature (issue #78; <c>.agents/controls/feedback-form/windows.md</c>): a Fluent
/// <see cref="ContentDialog"/> with Submit and Cancel, headed text boxes whose guidance stays visible as their
/// <see cref="TextBox.Description"/>, and Attach Media through the system file picker. Attached media show above the
/// button and open in the default app (no in-app viewer). Cancel, Esc or an outside click on a form with input shows an
/// inline discard confirmation (a ContentDialog cannot open a second one); discarding cancels an upload.
/// </summary>
public sealed class FeedbackDialog
{
    private const string Root = "fst.settings.feedback";
    private readonly FeedbackFormViewModel form;
    private readonly ContentDialog dialog;
    private readonly InfoBar discardBar;
    private readonly InfoBar errorBar;
    private readonly StackPanel editor;
    private readonly TextBox title;
    private readonly TextBox description;
    private readonly TextBox? repro;
    private readonly TextBox? expected;
    private readonly VariableSizedWrapGrid tiles;
    private readonly TextBlock notice;
    private readonly Button attach;
    private readonly StackPanel progress;
    private readonly StackPanel sent;
    private readonly TextBlock sentText;
    private readonly TextBlock sending;
    private readonly Button keepEditing;
    private readonly XamlRoot root;
    private readonly ScrollViewer scroller;
    private bool allowClose;

    /// <summary>Builds the dialog.</summary>
    /// <param name="root">Window XAML root.</param>
    /// <param name="kind">Bug or Feature.</param>
    private FeedbackDialog(XamlRoot root, FeedbackKind kind)
    {
        this.root = root;
        var api = App.Session.Api;
        form = new FeedbackFormViewModel(
            kind,
            (submission, token) => Task.Run(() => api.SubmitFeedbackAsync(submission, OpenAttachment, token), token),
            (jobId, token) => Task.Run(() => api.GetFeedbackStatusAsync(jobId, token), token),
            AppVersionInfo.Display(typeof(App).Assembly),
            $"{RuntimeInformation.OSDescription} ({RuntimeInformation.OSArchitecture})");
        var id = $"{Root}.{kind.AutomationSuffix()}";

        discardBar = new InfoBar
        {
            Severity = InfoBarSeverity.Warning,
            IsClosable = false,
            Title = $"Discard this {kind.Noun()}?",
            Message = "Your text and attachments will be lost.",
        };
        var discard = new Button { Content = "Discard", Style = Resource<Style>("AccentButtonStyle") };
        AutomationProperties.SetAutomationId(discard, $"{Root}.discard");
        discard.Click += (_, _) => Discard();
        keepEditing = new Button { Content = "Keep Editing" };
        AutomationProperties.SetAutomationId(keepEditing, $"{Root}.keep-editing");
        keepEditing.Click += (_, _) =>
        {
            form.KeepEditing();
            title!.Focus(FocusState.Programmatic);
        };
        discardBar.Content = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, Margin = new Thickness(0, 0, 0, 12), Children = { discard, keepEditing } };
        AutomationProperties.SetAutomationId(discardBar, $"{Root}.discard-confirm");
        AutomationProperties.SetLiveSetting(discardBar, AutomationLiveSetting.Assertive);

        errorBar = new InfoBar { Severity = InfoBarSeverity.Error, IsClosable = false, Title = "Not sent" };
        AutomationProperties.SetAutomationId(errorBar, $"{Root}.error");
        AutomationProperties.SetLiveSetting(errorBar, AutomationLiveSetting.Assertive);

        title = Field(FeedbackCopy.Title, form.TitleHelp, $"{Root}.title", multiline: false, form.Title, text => form.Title = text);
        title.MaxLength = FeedbackLimits.MaxTitleLength;
        // Caret after the "[Bug] " / "[Feature] " prefix so typing continues the title.
        title.Loaded += (_, _) => title.Select(title.Text.Length, 0);
        description = Field(FeedbackCopy.Description, form.DescriptionHelp, $"{Root}.description", multiline: true, "",
            text => form.Description = text);
        editor = new StackPanel { Spacing = 16, Children = { title, description } };
        if (form.HasBugFields)
        {
            repro = Field(FeedbackCopy.Repro, FeedbackCopy.ReproHelp, $"{Root}.repro", multiline: true, "", text => form.ReproSteps = text);
            expected = Field(FeedbackCopy.Expected, FeedbackCopy.ExpectedHelp, $"{Root}.expected", multiline: true, "",
                text => form.ExpectedBehavior = text);
            editor.Children.Add(repro);
            editor.Children.Add(expected);
        }

        var mediaHeader = new TextBlock { Text = "Media", Style = Resource<Style>("BodyStrongTextBlockStyle") };
        AutomationProperties.SetHeadingLevel(mediaHeader, AutomationHeadingLevel.Level3);
        var mediaHelp = new TextBlock
        {
            Text = FeedbackCopy.AttachHelp,
            TextWrapping = TextWrapping.Wrap,
            Style = Resource<Style>("CaptionTextBlockStyle"),
            Foreground = Resource<Brush>("FSTSecondaryTextBrush"),
        };
        tiles = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = 108, ItemHeight = 108 };
        AutomationProperties.SetName(tiles, "Attached media");
        AutomationProperties.SetAutomationId(tiles, $"{Root}.attachments");
        notice = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Style = Resource<Style>("CaptionTextBlockStyle"),
            Foreground = Resource<Brush>("SystemFillColorCautionBrush"),
        };
        AutomationProperties.SetLiveSetting(notice, AutomationLiveSetting.Polite);
        attach = new Button
        {
            Content = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 8,
                Children = { new FontIcon { Glyph = "\uE723", FontSize = 16 }, new TextBlock { Text = FeedbackCopy.Attach } },
            },
            MinHeight = 40,
        };
        AutomationProperties.SetName(attach, FeedbackCopy.Attach);
        AutomationProperties.SetAutomationId(attach, $"{Root}.attach");
        attach.Click += async (_, _) => await PickAsync();
        editor.Children.Add(new StackPanel { Spacing = 8, Children = { mediaHeader, mediaHelp, tiles, notice, attach } });

        var bar = new ProgressBar { IsIndeterminate = true };
        AutomationProperties.SetAccessibilityView(bar, AccessibilityView.Raw);
        sending = new TextBlock { Text = form.SendingText, TextWrapping = TextWrapping.Wrap };
        AutomationProperties.SetLiveSetting(sending, AutomationLiveSetting.Polite);
        progress = new StackPanel { Spacing = 8, Children = { bar, sending } };
        AutomationProperties.SetAutomationId(progress, $"{Root}.progress");

        sentText = new TextBlock { TextWrapping = TextWrapping.Wrap, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
        AutomationProperties.SetLiveSetting(sentText, AutomationLiveSetting.Assertive);
        AutomationProperties.SetAutomationId(sentText, $"{Root}.sent");
        sent = new StackPanel
        {
            Spacing = 8,
            Children =
            {
                new StackPanel
                {
                    Orientation = Orientation.Horizontal,
                    Spacing = 12,
                    Children =
                    {
                        new FontIcon
                        {
                            Glyph = "\uE73E", FontSize = 24,
                            Foreground = Resource<Brush>("SystemFillColorSuccessBrush"),
                        },
                        sentText,
                    },
                },
            },
        };

        // Progress sits above the fields so it is on screen wherever the form was scrolled when Submit was pressed.
        var body = new StackPanel { Spacing = 16, Padding = new Thickness(0, 0, 16, 0), Children = { discardBar, errorBar, progress, editor, sent } };
        // ContentDialog's own ContentScrollViewer never scrolls vertically, so a long form needs its own scroller.
        scroller = new ScrollViewer { Content = body, Margin = new Thickness(0, 0, -16, 0) };
        AutomationProperties.SetAutomationId(scroller, $"{Root}.scroller");
        FitScroller();
        root.Changed += OnRootChanged;
        dialog = FestivalDialog.Create(root, form.FormTitle, scroller, $"{id}.dialog", closeText: form.CloseText,
            primaryText: form.PrimaryText, defaultButton: ContentDialogButton.None, closeAutomationId: $"{Root}.cancel");
        dialog.Resources["ContentDialogMaxWidth"] = 640.0;
        dialog.PrimaryButtonStyle = Resource<Style>("AccentButtonStyle");
        dialog.Closing += OnClosing;
        form.PropertyChanged += OnFormChanged;
        form.Attachments.CollectionChanged += (_, _) => RenderTiles();
        Render();
    }

    /// <summary>Opens the form and waits until it closes.</summary>
    /// <param name="root">Window XAML root.</param>
    /// <param name="kind">Bug or Feature.</param>
    /// <returns>Completes when the dialog closes.</returns>
    public static async Task ShowAsync(XamlRoot root, FeedbackKind kind)
    {
        var view = new FeedbackDialog(root, kind);
        try
        {
            await FestivalDialog.ShowAsync(view.dialog);
        }
        finally
        {
            root.Changed -= view.OnRootChanged;
        }
    }

    /// <summary>Caps the form's scroller to the window, leaving room for the dialog title and buttons.</summary>
    private void FitScroller() => scroller.MaxHeight = Math.Max(200, root.Size.Height - 240);

    /// <summary>Re-fits the scroller when the window resizes.</summary>
    /// <param name="sender">XAML root.</param>
    /// <param name="args">Change arguments.</param>
    private void OnRootChanged(XamlRoot sender, XamlRootChangedEventArgs args) => FitScroller();

    /// <summary>A headed text box whose guidance stays visible below it while typing.</summary>
    /// <param name="header">Label.</param>
    /// <param name="help">Guidance.</param>
    /// <param name="automationId">UI Automation ID.</param>
    /// <param name="multiline">Whether Enter adds a line.</param>
    /// <param name="text">Initial text.</param>
    /// <param name="changed">Receives edits.</param>
    /// <returns>Text box.</returns>
    private static TextBox Field(string header, string help, string automationId, bool multiline, string text, Action<string> changed)
    {
        var box = new TextBox
        {
            Header = header,
            // A string Description renders as a single unwrapped line and clips in narrow windows or at large text sizes.
            Description = new TextBlock { Text = help, TextWrapping = TextWrapping.WrapWholeWords },
            Text = text,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            AcceptsReturn = multiline,
            TextWrapping = multiline ? TextWrapping.Wrap : TextWrapping.NoWrap,
            MinHeight = multiline ? 96 : 0,
            MaxLength = multiline ? FeedbackLimits.MaxTextLength : 0,
        };
        if (multiline) ScrollViewer.SetVerticalScrollBarVisibility(box, ScrollBarVisibility.Auto);
        AutomationProperties.SetName(box, header);
        AutomationProperties.SetHelpText(box, help);
        AutomationProperties.SetAutomationId(box, automationId);
        box.TextChanged += (_, _) => changed(box.Text);
        return box;
    }

    /// <summary>Submit runs in place; Cancel/Esc/outside click close only when nothing would be lost.</summary>
    /// <param name="sender">Dialog.</param>
    /// <param name="args">Closing arguments.</param>
    private void OnClosing(ContentDialog sender, ContentDialogClosingEventArgs args)
    {
        if (allowClose) return;
        if (args.Result == ContentDialogResult.Primary)
        {
            args.Cancel = true;
            _ = form.SubmitAsync();
            return;
        }
        if (form.RequestClose())
        {
            form.PropertyChanged -= OnFormChanged;
            return;
        }
        args.Cancel = true;
        // The confirmation bar opens in this pass; show it and focus its safe choice once it is laid out.
        sender.DispatcherQueue.TryEnqueue(() =>
        {
            discardBar.StartBringIntoView();
            keepEditing.Focus(FocusState.Programmatic);
        });
    }

    /// <summary>Discard confirmed: cancels any upload and closes.</summary>
    private void Discard()
    {
        form.ConfirmDiscard();
        form.PropertyChanged -= OnFormChanged;
        allowClose = true;
        dialog.Hide();
    }

    /// <summary>Re-renders on model changes.</summary>
    /// <param name="sender">Model.</param>
    /// <param name="e">Changed property.</param>
    private void OnFormChanged(object? sender, PropertyChangedEventArgs e)
    {
        Render();
        if (e.PropertyName == nameof(FeedbackFormViewModel.Error) && form.HasError)
            dialog.DispatcherQueue.TryEnqueue(() => errorBar.StartBringIntoView());
        else if (e.PropertyName == nameof(FeedbackFormViewModel.IsSubmitting) && form.IsSubmitting)
            dialog.DispatcherQueue.TryEnqueue(() => scroller.ChangeView(null, 0, null));
    }

    /// <summary>Applies the model to the controls.</summary>
    private void Render()
    {
        discardBar.IsOpen = form.ConfirmingDiscard;
        errorBar.IsOpen = form.HasError;
        errorBar.Message = form.Error ?? "";
        var editable = form.IsEditing;
        foreach (var box in new[] { title, description, repro, expected })
            if (box is not null) box.IsReadOnly = !editable;
        attach.IsEnabled = editable && form.Attachments.Count < FeedbackLimits.MaxAttachments;
        notice.Text = form.Notice ?? "";
        notice.Visibility = form.HasNotice ? Visibility.Visible : Visibility.Collapsed;
        editor.Visibility = form.IsSent ? Visibility.Collapsed : Visibility.Visible;
        progress.Visibility = form.IsSubmitting ? Visibility.Visible : Visibility.Collapsed;
        sent.Visibility = form.IsSent ? Visibility.Visible : Visibility.Collapsed;
        sentText.Text = form.SuccessMessage;
        sending.Text = form.SendingText;
        dialog.PrimaryButtonText = form.PrimaryText;
        dialog.CloseButtonText = form.CloseText;
        dialog.IsPrimaryButtonEnabled = editable;
        foreach (var tile in tiles.Children.OfType<Grid>())
            if (tile.Children.OfType<Button>().LastOrDefault() is { } remove) remove.IsEnabled = editable;
    }

    /// <summary>Rebuilds the attachment tiles (thumbnail button that opens the file, plus a remove button).</summary>
    private void RenderTiles()
    {
        tiles.Children.Clear();
        foreach (var attachment in form.Attachments) tiles.Children.Add(Tile(attachment));
        Render();
    }

    /// <summary>One attachment tile.</summary>
    /// <param name="attachment">Attachment.</param>
    /// <returns>Tile.</returns>
    private UIElement Tile(FeedbackAttachment attachment)
    {
        var face = new Grid { Width = 96, Height = 96, CornerRadius = new CornerRadius(8), Background = Resource<Brush>("CardBackgroundFillColorSecondaryBrush") };
        var image = new Image { Stretch = Stretch.UniformToFill };
        face.Children.Add(new FontIcon { Glyph = attachment.IsVideo ? "\uE714" : "\uEB9F", FontSize = 28, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center });
        face.Children.Add(image);
        if (attachment.IsVideo)
        {
            face.Children.Add(new Border
            {
                Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0x99, 0, 0, 0)),
                CornerRadius = new CornerRadius(12),
                Width = 24,
                Height = 24,
                Margin = new Thickness(6),
                HorizontalAlignment = HorizontalAlignment.Left,
                VerticalAlignment = VerticalAlignment.Bottom,
                Child = new FontIcon { Glyph = "\uE768", FontSize = 12, Foreground = new SolidColorBrush(Microsoft.UI.Colors.White) },
            });
        }
        _ = LoadThumbnailAsync(attachment, image);
        var open = new Button { Content = face, Padding = new Thickness(0), Width = 96, Height = 96, CornerRadius = new CornerRadius(8) };
        AutomationProperties.SetName(open, attachment.AccessibilityLabel);
        AutomationProperties.SetHelpText(open, "Opens in the default app.");
        AutomationProperties.SetAutomationId(open, $"{Root}.attachment");
        ToolTipService.SetToolTip(open, attachment.Name);
        open.Click += async (_, _) => await OpenAsync(attachment);

        var remove = new Button
        {
            Content = new Border
            {
                Width = 24,
                Height = 24,
                CornerRadius = new CornerRadius(12),
                Background = new SolidColorBrush(Windows.UI.Color.FromArgb(0xCC, 0x20, 0x20, 0x20)),
                Child = new FontIcon { Glyph = "\uE711", FontSize = 10, Foreground = new SolidColorBrush(Microsoft.UI.Colors.White) },
            },
            Width = 40,
            Height = 40,
            Padding = new Thickness(0),
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(20),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, -10, -10, 0),
        };
        AutomationProperties.SetName(remove, $"Remove {attachment.Name}");
        AutomationProperties.SetAutomationId(remove, $"{Root}.attachment.remove");
        ToolTipService.SetToolTip(remove, "Remove");
        remove.Click += (_, _) =>
        {
            form.RemoveAttachment(attachment.Id);
            attach.Focus(FocusState.Programmatic);
        };
        return new Grid { Width = 96, Height = 96, Children = { open, remove } };
    }

    /// <summary>Shell thumbnail for an image or video (no decoding or playback in-app); keeps the glyph on failure.</summary>
    /// <param name="attachment">Attachment.</param>
    /// <param name="image">Target.</param>
    /// <returns>Completes when loaded or failed.</returns>
    private static async Task LoadThumbnailAsync(FeedbackAttachment attachment, Image image)
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(attachment.Id);
            using var thumbnail = await file.GetThumbnailAsync(ThumbnailMode.SingleItem, 192, ThumbnailOptions.ResizeThumbnail);
            if (thumbnail is null || thumbnail.Type != ThumbnailType.Image) return;
            var bitmap = new BitmapImage { DecodePixelWidth = 192 };
            await bitmap.SetSourceAsync(thumbnail);
            image.Source = bitmap;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or COMException or ArgumentException)
        {
        }
    }

    /// <summary>Opens the attachment in its default app, falling back to the shell.</summary>
    /// <param name="attachment">Attachment.</param>
    /// <returns>Completes after the hand-off.</returns>
    private static async Task OpenAsync(FeedbackAttachment attachment)
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(attachment.Id);
            if (await Windows.System.Launcher.LaunchFileAsync(file)) return;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or COMException or ArgumentException)
        {
        }
        try
        {
            Process.Start(new ProcessStartInfo(attachment.Id) { UseShellExecute = true })?.Dispose();
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException or FileNotFoundException)
        {
        }
    }

    /// <summary>Attach Media: the system file picker filtered to images and videos, starting in Pictures.</summary>
    /// <returns>Completes after the pick.</returns>
    private async Task PickAsync()
    {
        if (MainWindow.Instance is not { } window || !form.IsEditing) return;
        var picker = new Microsoft.Windows.Storage.Pickers.FileOpenPicker(window.AppWindow.Id)
        {
            SuggestedStartLocation = Microsoft.Windows.Storage.Pickers.PickerLocationId.PicturesLibrary,
            ViewMode = Microsoft.Windows.Storage.Pickers.PickerViewMode.Thumbnail,
        };
        foreach (var extension in FeedbackMedia.Extensions) picker.FileTypeFilter.Add(extension);
        IReadOnlyList<Microsoft.Windows.Storage.Pickers.PickFileResult>? picked;
        try
        {
            picked = await picker.PickMultipleFilesAsync();
        }
        catch (COMException)
        {
            return;
        }
        if (picked is not { Count: > 0 }) return;
        form.AddAttachments(picked.Select(result => Describe(result.Path)));
        attach.Focus(FocusState.Programmatic);
    }

    /// <summary>Attachment for a picked path (size from the file system when readable).</summary>
    /// <param name="path">File path.</param>
    /// <returns>Attachment.</returns>
    private static FeedbackAttachment Describe(string path)
    {
        long? size;
        try
        {
            size = new FileInfo(path).Length;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            size = null;
        }
        return new FeedbackAttachment(path, Path.GetFileName(path), FeedbackMedia.MimeType(path), size);
    }

    /// <summary>Opens a picked file for upload (read-only, shared so another app may keep it open).</summary>
    /// <param name="attachment">Attachment.</param>
    /// <returns>Stream the multipart body owns.</returns>
    private static Stream OpenAttachment(FeedbackAttachment attachment) =>
        new FileStream(attachment.Id, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 81920, useAsync: true);

    /// <summary>App or theme resource, or <see langword="null"/> (the control's default) when missing.</summary>
    /// <typeparam name="T">Resource type.</typeparam>
    /// <param name="key">Resource key.</param>
    /// <returns>Resource or <see langword="null"/>.</returns>
    private static T? Resource<T>(string key) where T : class =>
        Application.Current.Resources.TryGetValue(key, out var value) ? value as T : null;
}
#endregion
