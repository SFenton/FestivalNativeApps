using System.ComponentModel;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace Festival.App.Controls;

#region Player percentile row
/// <summary>
/// One row of the player page's percentile table (web <c>PlayerPercentileRow</c>): the shared "Top N%" pill
/// (<see cref="MetadataPills"/>, issue #606: skewed gold outline for the top 1%, gold outline for the top 5%) on the left, the song count on the right and, when the row filters Songs, a trailing chevron. Rows are
/// separated by a hairline like the web's <c>borderBottom</c>.
/// </summary>
public sealed partial class PlayerPercentileRowView : ContentControl
{
    /// <summary>Row model.</summary>
    public static readonly DependencyProperty RowProperty = DependencyProperty.Register(
        nameof(Row), typeof(PlayerPercentileRow), typeof(PlayerPercentileRowView), new PropertyMetadata(null, (d, e) => ((PlayerPercentileRowView)d).OnRowChanged(e)));

    private readonly MetadataPill pillBox = MetadataPills.Create();
    private readonly TextBlock count = new() { FontSize = 14, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center };
    private readonly FontIcon chevron = new() { Glyph = "", FontSize = 12, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(12, 0, 0, 0) };
    private readonly Grid layout = new() { Padding = new Thickness(16, 10, 16, 10), MinHeight = 44 };
    private Button? button;
    private bool? builtLinked;

    /// <summary>Creates the view.</summary>
    public PlayerPercentileRowView()
    {
        IsTabStop = false;
        HorizontalContentAlignment = HorizontalAlignment.Stretch;
        pillBox.HorizontalAlignment = HorizontalAlignment.Left;
        layout.ColumnDefinitions.Add(new ColumnDefinition());
        layout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        layout.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        layout.Children.Add(pillBox);
        layout.Children.Add(count);
        layout.Children.Add(chevron);
        Grid.SetColumn(count, 1);
        Grid.SetColumn(chevron, 2);
        AutomationProperties.SetAccessibilityView(chevron, AccessibilityView.Raw);
        // The row (button or named group) carries "Top N%: count songs"; its texts would make Narrator read it twice.
        AutomationProperties.SetAccessibilityView(pillBox, AccessibilityView.Raw);
        AutomationProperties.SetAccessibilityView(count, AccessibilityView.Raw);
    }

    /// <summary>Row.</summary>
    public PlayerPercentileRow? Row
    {
        get => (PlayerPercentileRow?)GetValue(RowProperty);
        set => SetValue(RowProperty, value);
    }

    /// <summary>Swaps the observed model.</summary>
    /// <param name="e">Change.</param>
    private void OnRowChanged(DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is PlayerPercentileRow old) old.PropertyChanged -= OnRowPropertyChanged;
        if (e.NewValue is PlayerPercentileRow row) row.PropertyChanged += OnRowPropertyChanged;
        builtLinked = null;
        Render();
    }

    /// <summary>Re-renders when the link pauses or resumes.</summary>
    /// <param name="sender">Row.</param>
    /// <param name="e">Change.</param>
    private void OnRowPropertyChanged(object? sender, PropertyChangedEventArgs e) => Render();

    /// <summary>Applies the model.</summary>
    private void Render()
    {
        if (Row is not { } row) return;
        // Web PlayerPercentileTable renders the shared PercentilePill, so the tier comes from the label like everywhere else.
        MetadataPills.ApplyPercentile(pillBox, row.Label, MetadataPillStyle.Tier(SuggestionRowPresentation.TierFor(row.Label)));
        count.Text = row.CountText;
        chevron.Visibility = row.IsLinked ? Visibility.Visible : Visibility.Collapsed;
        if (builtLinked != row.IsLinked)
        {
            builtLinked = row.IsLinked;
            if (button is not null) button.Content = null;
            if (row.IsLinked)
            {
                button = new Button
                {
                    HorizontalAlignment = HorizontalAlignment.Stretch,
                    HorizontalContentAlignment = HorizontalAlignment.Stretch,
                    Padding = new Thickness(0),
                    CornerRadius = new CornerRadius(0),
                    Background = new SolidColorBrush(Microsoft.UI.Colors.Transparent),
                    BorderThickness = new Thickness(0),
                    Content = layout,
                };
                button.Click += (_, _) =>
                {
                    if (Row is { IsLinked: true, Link: { } link }) PlayerProfileView.OwnerOf(this)?.Follow(link);
                };
                Content = button;
            }
            else
            {
                button = null;
                Content = layout;
            }
        }
        FrameworkElement host = (FrameworkElement?)button ?? layout;
        AutomationProperties.SetName(host, row.Announcement);
        AutomationProperties.SetHelpText(host, row.IsLinked ? row.Link!.Hint : "");
        AutomationProperties.SetAutomationId(host, row.AutomationId);
    }
}
#endregion
