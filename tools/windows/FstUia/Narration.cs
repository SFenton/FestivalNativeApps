// Narrator model for the device-lab driver: the phrase Narrator speaks for an element and its scan-mode reading order,
// built from the same UI Automation properties Narrator reads. Narrator itself cannot be scripted (no API, its ETW
// provider carries no text) and needs an unlocked interactive console, so these steps are the automated stand-in
// (issue #271); the operator script in .agents/testing/windows.md remains the live check.

using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace FstUia;

internal sealed partial class Driver
{
    #region Narrator model

    /// <summary>
    /// Control types Narrator reads as one item: their descendants are spoken as part of the item's name, so the scan
    /// walk does not stop inside a named one.
    /// </summary>
    private static readonly HashSet<ControlType> NarratorLeafTypes =
    [
        ControlType.Button, ControlType.SplitButton, ControlType.Hyperlink, ControlType.MenuItem, ControlType.ListItem,
        ControlType.ComboBox, ControlType.CheckBox, ControlType.RadioButton, ControlType.TabItem, ControlType.TreeItem,
        ControlType.DataItem, ControlType.Edit, ControlType.Slider, ControlType.ProgressBar, ControlType.Text, ControlType.Image,
    ];

    /// <summary>
    /// Narrator's phrase for an element at default verbosity: name, localized role, then state (unavailable, expand/
    /// collapse, toggle, selected), value, item status, help text and shortcut, comma-separated in that order.
    /// </summary>
    /// <param name="e">Element.</param>
    /// <returns>The phrase, e.g. <c>Instrument: Lead, button, collapsed, Ctrl+E</c>.</returns>
    internal static string NarratorPhrase(AutomationElement e)
    {
        var p = e.Properties;
        var parts = new List<string>();
        void Add(Func<string?> read)
        {
            try
            {
                if (read() is { Length: > 0 } part) parts.Add(part);
            }
            catch (Exception)
            {
                // Unsupported property or pattern on this provider: Narrator skips it too.
            }
        }
        Add(() => p.Name.ValueOrDefault);
        Add(() => p.LocalizedControlType.ValueOrDefault);
        Add(() => p.IsEnabled.ValueOrDefault ? null : "unavailable");
        Add(() => e.Patterns.ExpandCollapse.PatternOrDefault?.ExpandCollapseState.ValueOrDefault switch
        {
            ExpandCollapseState.Collapsed => "collapsed",
            ExpandCollapseState.Expanded or ExpandCollapseState.PartiallyExpanded => "expanded",
            _ => null,
        });
        Add(() => e.Patterns.Toggle.PatternOrDefault?.ToggleState.ValueOrDefault switch
        {
            ToggleState.On => "on",
            ToggleState.Off => "off",
            ToggleState.Indeterminate => "mixed",
            _ => null,
        });
        Add(() => e.Patterns.SelectionItem.PatternOrDefault?.IsSelected.ValueOrDefault == true ? "selected" : null);
        Add(() => e.Patterns.Value.PatternOrDefault?.Value.ValueOrDefault is { Length: > 0 } value && value != p.Name.ValueOrDefault ? value : null);
        Add(() => p.ItemStatus.ValueOrDefault);
        Add(() => p.HelpText.ValueOrDefault);
        Add(() => p.AcceleratorKey.ValueOrDefault);
        return string.Join(", ", parts);
    }

    /// <summary>
    /// Narrator's scan-mode reading order under <paramref name="root"/>: a pre-order walk of the UIA control view that
    /// skips off-screen elements and unnamed containers, and stops at a named item that Narrator reads whole
    /// (<see cref="NarratorLeafTypes"/>). A named group or pane is read on entry, then its content.
    /// </summary>
    /// <param name="root">Walk root (the window, or a region such as the title bar).</param>
    /// <returns>Elements in reading order.</returns>
    private List<AutomationElement> NarratorOrder(AutomationElement root)
    {
        var walker = automation.TreeWalkerFactory.GetControlViewWalker();
        var order = new List<AutomationElement>();
        void Visit(AutomationElement element, int depth)
        {
            var p = element.Properties;
            if (p.IsOffscreen.ValueOrDefault) return;
            var named = !string.IsNullOrEmpty(p.Name.ValueOrDefault);
            ControlType type;
            try
            {
                type = p.ControlType.ValueOrDefault;
            }
            catch (NotSupportedException)
            {
                type = ControlType.Custom;
            }
            if (named && depth > 0) order.Add(element);
            if (named && depth > 0 && NarratorLeafTypes.Contains(type)) return;
            if (depth >= 40) return;
            for (var child = walker.GetFirstChild(element); child is not null; child = walker.GetNextSibling(child))
            {
                Visit(child, depth + 1);
            }
        }
        Visit(root, 0);
        return order;
    }

    /// <summary>A stable key for an element (its UIA RuntimeId) to locate it in a walk.</summary>
    /// <param name="e">Element.</param>
    /// <returns>Dot-joined runtime id.</returns>
    private static string RuntimeKey(AutomationElement e) => string.Join(".", e.Properties.RuntimeId.ValueOrDefault ?? []);

    /// <summary>
    /// <c>narrate:&lt;selector&gt;</c>: records the Narrator reading order under the element in the response's
    /// <c>narration</c> array: index, AutomationId and phrase.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a <c>selector</c>.</param>
    private void Narrate(Window window, JsonObject step)
    {
        var root = Find(window, step);
        response["narration"] ??= new JsonArray();
        var items = new JsonArray();
        var index = 0;
        foreach (var element in NarratorOrder(root))
        {
            var phrase = NarratorPhrase(element);
            items.Add(new JsonObject { ["index"] = index, ["id"] = element.Properties.AutomationId.ValueOrDefault ?? "", ["phrase"] = phrase });
            Log($"narrate[{index++}]: {phrase}");
        }
        response["narration"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["width_epx"] = WidthEpx(window), ["items"] = items });
    }

    /// <summary>
    /// <c>assertread:&lt;selector&gt;|&lt;phrase&gt;</c>: waits (default 5 s) until Narrator's phrase for the element
    /// (<see cref="NarratorPhrase"/>) equals the text, or matches it as a .NET regex when it starts with <c>~</c>.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a <c>selector</c>, <c>text</c> and an optional timeout.</param>
    /// <exception cref="InvalidOperationException">The phrase still differs at the timeout.</exception>
    private void AssertRead(Window window, JsonObject step)
    {
        var expected = (string)step["text"]!;
        var regex = expected.StartsWith('~') ? new Regex(expected[1..], RegexOptions.Singleline) : null;
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (true)
        {
            var phrase = NarratorPhrase(Find(window, step));
            if (regex?.IsMatch(phrase) ?? phrase == expected)
            {
                response["read"] ??= new JsonArray();
                response["read"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["phrase"] = phrase });
                return;
            }
            if (DateTime.UtcNow > until)
                throw new InvalidOperationException($"Narrator reads {(string)step["arg"]!} as \"{phrase}\", expected \"{expected}\"");
            Thread.Sleep(200);
        }
    }

    /// <summary>
    /// <c>assertorder:&lt;selector&gt;|&lt;selector&gt;[|…]</c>: fails unless the on-screen elements come in that order in
    /// Narrator's scan-mode reading order of the window (<see cref="NarratorOrder"/>); records the positions in
    /// <c>orders</c>.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a <c>selectors</c> array.</param>
    /// <exception cref="InvalidOperationException">An element is missing from the reading order or out of order.</exception>
    private void AssertOrder(Window window, JsonObject step)
    {
        var selectors = step["selectors"]!.AsArray();
        var keys = new List<(string Label, string Key)>();
        foreach (var selector in selectors)
        {
            var single = new JsonObject { ["selector"] = selector!.DeepClone(), ["timeout"] = step["timeout"]?.DeepClone() };
            keys.Add((Condition(single).Label, RuntimeKey(Find(window, single))));
        }
        var order = NarratorOrder(window).Select(RuntimeKey).ToList();
        var positions = new JsonArray();
        var previous = -1;
        foreach (var (label, key) in keys)
        {
            var position = order.IndexOf(key);
            if (position < 0) throw new InvalidOperationException($"{label} is not in Narrator's reading order (unnamed, off screen or inside a read-whole item)");
            if (position <= previous)
                throw new InvalidOperationException($"{label} is read at position {position}, before the previous target at {previous} ({(string)step["arg"]!})");
            positions.Add(new JsonObject { ["selector"] = label, ["position"] = position });
            previous = position;
        }
        response["orders"] ??= new JsonArray();
        response["orders"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["width_epx"] = WidthEpx(window), ["positions"] = positions });
    }

    #endregion
}
