using Festival.App.Services;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Settings detail row
/// <summary>
/// A chevron row in the wide Settings list (issue #371) that opens its setting's options in the trailing pane. A setting
/// row inside a card looks like the Feedback rows (Body title, caption description, 14 epx chevron); a section row looks
/// like the Licenses row (section-header title, 18 epx chevron). An optional <see cref="Value"/> shows the current choice
/// before the chevron. While its options are open the row takes the muted current-row fill that the split leaderboards use
/// for the open row (<c>FSTCurrentRowBrush</c>), plus a Highlight outline under a contrast theme, and Narrator reads
/// "Selected". The row is 12 epx wider than its text on each side (negative margin), so its text stays aligned with the
/// card or page text while the fill has an inset.
/// </summary>
public sealed partial class SettingsDetailRow
{
    /// <summary>Row title (and accessible name).</summary>
    public static readonly DependencyProperty TitleProperty =
        DependencyProperty.Register(nameof(Title), typeof(string), typeof(SettingsDetailRow), new PropertyMetadata("", OnChanged));

    /// <summary>Description under the title (and help text); empty hides it.</summary>
    public static readonly DependencyProperty DescriptionProperty =
        DependencyProperty.Register(nameof(Description), typeof(string), typeof(SettingsDetailRow), new PropertyMetadata("", OnChanged));

    /// <summary>Current value before the chevron; empty hides it.</summary>
    public static readonly DependencyProperty ValueProperty =
        DependencyProperty.Register(nameof(Value), typeof(string), typeof(SettingsDetailRow), new PropertyMetadata("", OnChanged));

    /// <summary>Whether the row's options are open in the trailing pane.</summary>
    public static readonly DependencyProperty IsCurrentProperty =
        DependencyProperty.Register(nameof(IsCurrent), typeof(bool), typeof(SettingsDetailRow), new PropertyMetadata(false, OnChanged));

    /// <summary>Whether the row stands for a whole page section (Licenses look) rather than a setting inside a card.</summary>
    public static readonly DependencyProperty IsSectionProperty =
        DependencyProperty.Register(nameof(IsSection), typeof(bool), typeof(SettingsDetailRow), new PropertyMetadata(false, OnChanged));

    /// <summary>Creates the row.</summary>
    public SettingsDetailRow()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            ContrastTheme.Changed -= OnColorsChanged;
            ContrastTheme.Changed += OnColorsChanged;
            Apply();
        };
        Unloaded += (_, _) => ContrastTheme.Changed -= OnColorsChanged;
        ActualThemeChanged += (_, _) => Apply();
        Apply();
    }

    /// <summary>Row title.</summary>
    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    /// <summary>Row description.</summary>
    public string Description
    {
        get => (string)GetValue(DescriptionProperty);
        set => SetValue(DescriptionProperty, value);
    }

    /// <summary>Current value text.</summary>
    public string Value
    {
        get => (string)GetValue(ValueProperty);
        set => SetValue(ValueProperty, value);
    }

    /// <summary>Whether the row is open in the trailing pane.</summary>
    public bool IsCurrent
    {
        get => (bool)GetValue(IsCurrentProperty);
        set => SetValue(IsCurrentProperty, value);
    }

    /// <summary>Whether the row is a section row.</summary>
    public bool IsSection
    {
        get => (bool)GetValue(IsSectionProperty);
        set => SetValue(IsSectionProperty, value);
    }

    /// <summary>Re-applies the row after a property change.</summary>
    /// <param name="d">Row.</param>
    /// <param name="e">Change.</param>
    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((SettingsDetailRow)d).Apply();

    /// <summary>System colours changed (contrast theme on/off): re-resolve the code-set brushes on the UI thread.</summary>
    /// <param name="sender">Sender.</param>
    /// <param name="e">Arguments.</param>
    private void OnColorsChanged(object? sender, EventArgs e) => DispatcherQueue?.TryEnqueue(Apply);

    /// <summary>Applies text, metrics, current-row surface and automation properties.</summary>
    private void Apply()
    {
        if (TitleText is null) return;
        var section = IsSection;
        TitleText.Text = Title ?? "";
        TitleText.Style = (Style)Application.Current.Resources[section ? "FSTSectionHeaderStyle" : "BodyTextBlockStyle"];
        TitleText.TextWrapping = TextWrapping.Wrap;
        TitleText.Margin = section ? new Thickness(0, 0, 0, 4) : new Thickness(0);
        DescriptionText.Text = Description ?? "";
        DescriptionText.Visibility = string.IsNullOrEmpty(Description) ? Visibility.Collapsed : Visibility.Visible;
        ValueText.Text = Value ?? "";
        ValueText.Visibility = string.IsNullOrEmpty(Value) ? Visibility.Collapsed : Visibility.Visible;
        Chevron.FontSize = section ? 18 : 14;
        Layout.ColumnSpacing = section ? 16 : 12;
        MinHeight = section ? 0 : 56;
        Margin = new Thickness(-13, 0, -13, 0);
        Padding = section ? new Thickness(12, 3, 16, 3) : new Thickness(12, 7, 16, 7);

        if (IsCurrent)
        {
            Background = ContrastTheme.Brush("FSTCurrentRowBrush");
            BorderBrush = ContrastTheme.Brush("FSTCurrentRowStrokeBrush");
        }
        else
        {
            Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent);
            ClearValue(BorderBrushProperty);
        }

        AutomationProperties.SetName(this, Title ?? "");
        AutomationProperties.SetHelpText(this, Description ?? "");
        var status = string.Join(", ", new[] { Value, IsCurrent ? "Selected" : "" }.Where(s => !string.IsNullOrEmpty(s)));
        AutomationProperties.SetItemStatus(this, status);
    }
}
#endregion
