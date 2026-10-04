using Festival.Core.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Automation.Peers;
using Microsoft.UI.Xaml.Controls;

namespace Festival.App.Controls;

#region Service status inline
/// <summary>
/// Shared inline failed-read row (service-status <c>inline</c> state): heading, message, the automatic-retry countdown
/// (spoken as "Trying again automatically in N seconds") and Retry. A named UIA <c>Group</c> (<see cref="IdPrefix"/>,
/// named by the section's fallback title) so tests and Narrator find the row; it raises no announcements.
/// </summary>
public sealed partial class ServiceStatusInline : UserControl
{
    /// <summary>Default automation ID of the row (spec test ID <c>fst.service-status.inline</c>).</summary>
    public const string DefaultIdPrefix = "fst.service-status.inline";

    /// <summary>Bound status.</summary>
    public static readonly DependencyProperty StatusProperty = DependencyProperty.Register(
        nameof(Status), typeof(ServiceStatusViewModel), typeof(ServiceStatusInline), new PropertyMetadata(null, OnStatusChanged));

    /// <summary>Automation ID root.</summary>
    public static readonly DependencyProperty IdPrefixProperty = DependencyProperty.Register(
        nameof(IdPrefix), typeof(string), typeof(ServiceStatusInline), new PropertyMetadata(DefaultIdPrefix, OnIdsChanged));

    /// <summary>Optional heading automation ID override.</summary>
    public static readonly DependencyProperty TitleAutomationIdProperty = DependencyProperty.Register(
        nameof(TitleAutomationId), typeof(string), typeof(ServiceStatusInline), new PropertyMetadata(null, OnIdsChanged));

    /// <summary>Optional Retry automation ID override.</summary>
    public static readonly DependencyProperty RetryAutomationIdProperty = DependencyProperty.Register(
        nameof(RetryAutomationId), typeof(string), typeof(ServiceStatusInline), new PropertyMetadata(null, OnIdsChanged));

    /// <summary>Whether the texts and Retry are centred (a centred empty-state slot such as Song Detail history).</summary>
    public static readonly DependencyProperty IsCenteredProperty = DependencyProperty.Register(
        nameof(IsCentered), typeof(bool), typeof(ServiceStatusInline), new PropertyMetadata(false, OnCenteredChanged));

    /// <summary>Creates the row.</summary>
    public ServiceStatusInline()
    {
        InitializeComponent();
        ApplyIds();
    }

    /// <summary>Status to render.</summary>
    public ServiceStatusViewModel? Status
    {
        get => (ServiceStatusViewModel?)GetValue(StatusProperty);
        set => SetValue(StatusProperty, value);
    }

    /// <summary>
    /// Automation ID root: the row is <c>&lt;IdPrefix&gt;</c>, its heading <c>.title</c>, countdown <c>.countdown</c>
    /// and button <c>.retry</c> unless overridden.
    /// </summary>
    public string IdPrefix
    {
        get => (string)GetValue(IdPrefixProperty);
        set => SetValue(IdPrefixProperty, value);
    }

    /// <summary>Heading automation ID when a page keeps its own (e.g. <c>fst.history.error</c>).</summary>
    public string? TitleAutomationId
    {
        get => (string?)GetValue(TitleAutomationIdProperty);
        set => SetValue(TitleAutomationIdProperty, value);
    }

    /// <summary>Retry automation ID when a page keeps its own (e.g. <c>fst.history.retry</c>).</summary>
    public string? RetryAutomationId
    {
        get => (string?)GetValue(RetryAutomationIdProperty);
        set => SetValue(RetryAutomationIdProperty, value);
    }

    /// <summary>Whether the texts and Retry are centred.</summary>
    public bool IsCentered
    {
        get => (bool)GetValue(IsCenteredProperty);
        set => SetValue(IsCenteredProperty, value);
    }

    /// <inheritdoc />
    protected override AutomationPeer OnCreateAutomationPeer() => new InlinePeer(this);

    private static void OnStatusChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) =>
        ((ServiceStatusInline)d).Bindings.Update();

    private static void OnIdsChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) => ((ServiceStatusInline)d).ApplyIds();

    private static void OnCenteredChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var view = (ServiceStatusInline)d;
        var centered = (bool)e.NewValue;
        var alignment = centered ? TextAlignment.Center : TextAlignment.Left;
        view.TitleBlock.TextAlignment = view.MessageBlock.TextAlignment = view.CountdownBlock.TextAlignment = alignment;
        view.Root.HorizontalAlignment = centered ? HorizontalAlignment.Center : HorizontalAlignment.Stretch;
        view.RetryButton.HorizontalAlignment = centered ? HorizontalAlignment.Center : HorizontalAlignment.Left;
    }

    /// <summary>Applies the row, heading, countdown and Retry automation IDs.</summary>
    private void ApplyIds()
    {
        var prefix = string.IsNullOrEmpty(IdPrefix) ? DefaultIdPrefix : IdPrefix;
        AutomationProperties.SetAutomationId(this, prefix);
        AutomationProperties.SetAutomationId(TitleBlock, TitleAutomationId ?? prefix + ".title");
        AutomationProperties.SetAutomationId(CountdownBlock, prefix + ".countdown");
        AutomationProperties.SetAutomationId(RetryButton, RetryAutomationId ?? prefix + ".retry");
    }

    /// <summary>Group peer named by <c>AutomationProperties.Name</c>, else the section's fallback title.</summary>
    /// <param name="owner">Row.</param>
    private sealed partial class InlinePeer(ServiceStatusInline owner) : FrameworkElementAutomationPeer(owner)
    {
        /// <inheritdoc />
        protected override AutomationControlType GetAutomationControlTypeCore() => AutomationControlType.Group;

        /// <inheritdoc />
        protected override string GetClassNameCore() => nameof(ServiceStatusInline);

        /// <inheritdoc />
        protected override string GetNameCore()
        {
            var name = base.GetNameCore();
            return string.IsNullOrEmpty(name) ? owner.Status?.FallbackTitle ?? "" : name;
        }
    }
}
#endregion
