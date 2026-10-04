// Accessibility commands for the device-lab driver: Axe.Windows rule scans, keyboard
// focus walks and focus assertions (used by tools/windows/uiwin.py scan/focus-order and
// the `tabwalk:`/`assertfocus:` drive steps).

using System.Text.Json.Nodes;
using Axe.Windows.Automation;
using Axe.Windows.Automation.Data;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;

namespace FstUia;

internal sealed partial class Driver
{
    #region Axe.Windows scan

    /// <summary>
    /// <c>scan</c>: runs the Axe.Windows rules against the target window's UIA tree and reports every error with the
    /// failing element (name, control type, AutomationId, class, bounds) and its parent chain.
    /// </summary>
    /// <param name="window">Target window (the scan root).</param>
    /// <param name="output">Directory for the <c>.a11ytest</c> file (saved only when there are errors).</param>
    /// <param name="scanId">Result file name.</param>
    /// <returns><c>errors</c> count and <c>findings</c> (<c>files_skipped</c> when no <c>.a11ytest</c> could be written).</returns>
    private static JsonNode Scan(Window window, string output, string scanId)
    {
        Directory.CreateDirectory(output);
        ScanOutput Run(OutputFileFormat format) => ScannerFactory.CreateScanner(Config.Builder
                .ForProcessId(window.Properties.ProcessId.Value)
                .WithOutputDirectory(output)
                .WithOutputFileFormat(format)
                .Build())
            .Scan(new ScanOptions(scanId, window.Properties.NativeWindowHandle.Value));
        ScanOutput result;
        var filesSkipped = false;
        try
        {
            result = Run(OutputFileFormat.A11yTest);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // The .a11ytest file embeds a screen capture, which fails on the secure (locked) desktop; the rules still run.
            result = Run(OutputFileFormat.None);
            filesSkipped = true;
        }
        var findings = new JsonArray();
        var total = 0;
        var files = new JsonArray();
        foreach (var windowOutput in result.WindowScanOutputs)
        {
            total += windowOutput.ErrorCount;
            if (windowOutput.OutputFile.A11yTest is { } file) files.Add(JsonValue.Create(file));
            foreach (var error in windowOutput.Errors)
            {
                findings.Add(new JsonObject
                {
                    ["rule"] = error.Rule.ID.ToString(),
                    ["description"] = error.Rule.Description,
                    ["how_to_fix"] = error.Rule.HowToFix,
                    ["code"] = error.Rule.ErrorCode.ToString(),
                    ["framework_issue"] = error.Rule.FrameworkIssueLink,
                    ["element"] = ElementSummary(error.Element),
                    ["parents"] = ParentChain(error.Element),
                });
            }
        }
        return new JsonObject { ["errors"] = total, ["findings"] = findings, ["files"] = files, ["files_skipped"] = filesSkipped };
    }

    /// <summary><c>scan:&lt;dir/scan-id&gt;</c> drive step: runs <see cref="Scan"/> and appends the result to <c>scans</c>.</summary>
    /// <param name="window">Target window.</param>
    /// <param name="path">Output directory plus scan id (last path segment).</param>
    private void ScanStep(Window window, string path)
    {
        if (response["scans"] is not JsonArray scans)
        {
            scans = [];
            response["scans"] = scans;
        }
        var result = Scan(window, Path.GetDirectoryName(path)!, Path.GetFileName(path)).AsObject();
        result["scan_id"] = Path.GetFileName(path);
        result["width_epx"] = WidthEpx(window);
        scans.Add(result);
        Log($"scan {Path.GetFileName(path)}: {result["errors"]} error(s)");
    }

    /// <summary>The window's current width in effective pixels.</summary>
    /// <param name="window">Target window.</param>
    /// <returns>Width in epx.</returns>
    private static double WidthEpx(Window window)
    {
        var hwnd = window.Properties.NativeWindowHandle.Value;
        return Math.Round(Native.VisibleBounds(hwnd).Width / (Native.GetDpiForWindow(hwnd) / 96.0));
    }

    /// <summary>Compact element description from an Axe <see cref="ElementInfo"/>.</summary>
    /// <param name="element">Failing element.</param>
    /// <returns>Name/control type/AutomationId/class/bounds.</returns>
    private static JsonObject ElementSummary(ElementInfo? element)
    {
        var summary = new JsonObject();
        if (element?.Properties is null) return summary;
        foreach (var key in new[] { "Name", "ControlType", "LocalizedControlType", "AutomationId", "ClassName", "BoundingRectangle", "FrameworkId", "IsKeyboardFocusable" })
        {
            if (element.Properties.TryGetValue(key, out var value)) summary[key] = value;
        }
        return summary;
    }

    /// <summary>Ancestors of a failing element, nearest first, as <c>ControlType "Name" id=…</c> strings.</summary>
    /// <param name="element">Failing element.</param>
    /// <returns>Up to eight ancestors.</returns>
    private static JsonArray ParentChain(ElementInfo? element)
    {
        var chain = new JsonArray();
        for (var parent = element?.Parent; parent is not null && chain.Count < 8; parent = parent.Parent)
        {
            var p = parent.Properties;
            string Get(string key) => p is not null && p.TryGetValue(key, out var v) ? v : "";
            chain.Add(JsonValue.Create($"{Get("ControlType")} \"{Get("Name")}\" id={Get("AutomationId")} class={Get("ClassName")}"));
        }
        return chain;
    }

    #endregion

    #region Keyboard focus

    /// <summary>
    /// <c>tabwalk:&lt;count&gt;[,shift]</c>: presses Tab (or Shift+Tab) <c>count</c> times and records the focused
    /// element after each press in the response's <c>focus</c> array (and the log). A repeated identical element on
    /// consecutive presses is reported as a possible keyboard trap.
    /// </summary>
    /// <param name="window">Target window (already foreground).</param>
    /// <param name="step">Step with <c>count</c> and optional <c>reverse</c>.</param>
    private void TabWalk(Window window, JsonObject step)
    {
        var count = (int?)step["count"] ?? 20;
        var reverse = (bool?)step["reverse"] ?? false;
        if (response["focus"] is not JsonArray focus)
        {
            focus = [];
            response["focus"] = focus;
        }
        string? previous = null;
        for (var i = 0; i < count; i++)
        {
            if (postKeys) PostedInput.Press(window.Properties.NativeWindowHandle.Value, reverse ? [VirtualKeyShort.SHIFT, VirtualKeyShort.TAB] : [VirtualKeyShort.TAB]);
            else if (reverse) Keyboard.TypeSimultaneously(VirtualKeyShort.SHIFT, VirtualKeyShort.TAB);
            else Keyboard.Type(VirtualKeyShort.TAB);
            Thread.Sleep(180);
            var focused = Focused(window);
            var line = focused is null ? "(none)" : Line(focused);
            var entry = new JsonObject
            {
                ["index"] = focus.Count,
                ["line"] = line,
                ["id"] = focused?.Properties.AutomationId.ValueOrDefault ?? "",
                ["name"] = focused?.Properties.Name.ValueOrDefault ?? "",
                ["type"] = focused is null ? "" : Role(focused),
                ["width_epx"] = WidthEpx(window),
                ["in_window"] = focused is not null && focused.Properties.ProcessId.ValueOrDefault == window.Properties.ProcessId.Value,
            };
            if (line == previous) entry["repeat"] = true;
            focus.Add(entry);
            Log($"focus[{focus.Count - 1}]: {line}");
            previous = line;
        }
    }

    /// <summary>
    /// The focused element: the system focus, or, while keys are posted (locked session, where the system focus is
    /// the lock screen), the element inside the target window that has keyboard focus.
    /// </summary>
    /// <param name="window">Target window.</param>
    /// <returns>Focused element, or <see langword="null"/>.</returns>
    private AutomationElement? Focused(Window window)
    {
        if (!postKeys) return automation.FocusedElement();
        var condition = new FlaUI.Core.Conditions.PropertyCondition(automation.PropertyLibrary.Element.HasKeyboardFocus, true);
        return window.FindFirstDescendant(condition);
    }

    /// <summary><c>assertfocus:&lt;selector&gt;</c>: fails unless the focused element matches the selector.</summary>
    /// <param name="window">Target window.</param>
    /// <param name="step">Step with <c>selector</c> (<c>id=</c>, <c>name=</c> or <c>class=</c>).</param>
    private void AssertFocus(Window window, JsonObject step)
    {
        var selector = step["selector"]!.AsObject();
        var kind = (string)selector["kind"]!;
        var value = (string)selector["value"]!;
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 2);
        while (true)
        {
            var focused = Focused(window);
            var actual = focused is null ? null : kind switch
            {
                "id" => focused.Properties.AutomationId.ValueOrDefault,
                "name" => focused.Properties.Name.ValueOrDefault,
                "class" => focused.Properties.ClassName.ValueOrDefault,
                _ => throw new ArgumentException($"selector {kind} cannot match focus"),
            };
            if (actual == value) return;
            if (DateTime.UtcNow > until)
            {
                throw new InvalidOperationException($"focus is {(focused is null ? "(none)" : Line(focused))}, expected {kind}={value}");
            }
            Thread.Sleep(150);
        }
    }

    #endregion

    #region Tree annotations

    /// <summary>Narrator-relevant properties for tree lines: heading, landmark, live setting, accelerator/access keys, item status, full description.</summary>
    /// <param name="e">Element.</param>
    /// <returns>Space-prefixed annotations, or empty.</returns>
    private static string A11yFlags(AutomationElement e)
    {
        var p = e.Properties;
        var parts = new List<string>();
        try
        {
            if (p.HeadingLevel.TryGetValue(out var heading) && (int)heading is > 80050 and < 80060)
                parts.Add($"heading={(int)heading - 80050}");
            if (p.LandmarkType.TryGetValue(out var landmark) && (int)landmark != 0)
                parts.Add($"landmark={p.LocalizedLandmarkType.ValueOrDefault}");
            if (p.LiveSetting.TryGetValue(out var live) && (int)live != 0) parts.Add($"live={live}");
            if (p.AcceleratorKey.ValueOrDefault is { Length: > 0 } accel) parts.Add($"accel={accel}");
            if (p.AccessKey.ValueOrDefault is { Length: > 0 } access) parts.Add($"access={access}");
            if (p.ItemStatus.ValueOrDefault is { Length: > 0 } status) parts.Add($"status=\"{status}\"");
            if (p.FullDescription.ValueOrDefault is { Length: > 0 } description) parts.Add($"desc=\"{description}\"");
        }
        catch (Exception)
        {
            // Older UIA providers may not expose these properties; the tree line stays without them.
        }
        return parts.Count > 0 ? " " + string.Join(" ", parts) : "";
    }

    #endregion
}
