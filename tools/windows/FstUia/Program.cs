// Device-lab UI Automation driver for the Windows app.
//
// tools/windows/uiwin.py writes one JSON request, runs this executable inside the
// interactive desktop session (directly, or through a one-shot scheduled task when
// called from SSH session 0) and reads one JSON response. All desktop access is
// serialized by uiwin.py's host "desktop" lock; this program never takes locks.

using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization.Metadata;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Conditions;
using FlaUI.Core.Input;
using FlaUI.Core.WindowsAPI;
using FlaUI.UIA3;

namespace FstUia;

/// <summary>Entry point: <c>FstUia.exe --request req.json --response resp.json</c>.</summary>
public static class Program
{
    #region Entry

    /// <summary>Executes one request and writes its response.</summary>
    /// <param name="args">Command-line arguments.</param>
    /// <returns>0 on success, 1 on a handled failure, 2 on usage error.</returns>
    public static int Main(string[] args)
    {
        string? requestPath = null, responsePath = null;
        for (var i = 0; i + 1 < args.Length; i += 2)
        {
            if (args[i] == "--request") requestPath = args[i + 1];
            if (args[i] == "--response") responsePath = args[i + 1];
        }
        if (requestPath is null || responsePath is null) return 2;

        var response = new JsonObject { ["session"] = Process.GetCurrentProcess().SessionId };
        var code = 0;
        try
        {
            var request = JsonNode.Parse(File.ReadAllText(requestPath))!.AsObject();
            using var automation = new UIA3Automation();
            var driver = new Driver(automation, response);
            response["result"] = driver.Execute(request);
            response["ok"] = true;
        }
        catch (Exception error)
        {
            response["ok"] = false;
            response["error"] = error.Message;
            response["detail"] = error.ToString();
            code = 1;
        }
        string text;
        try
        {
            text = response.ToJsonString(new JsonSerializerOptions
            {
                WriteIndented = true,
                TypeInfoResolver = new DefaultJsonTypeInfoResolver(),
            });
        }
        catch (Exception error)
        {
            // Never leave the caller waiting: report serialization failures too.
            text = new JsonObject { ["ok"] = false, ["error"] = "response serialization: " + error.Message }.ToJsonString();
            code = 1;
        }
        var temp = responsePath + ".tmp";
        File.WriteAllText(temp, text);
        File.Move(temp, responsePath, overwrite: true);
        return code;
    }

    #endregion
}

/// <summary>Executes launch/window/resize/shot/tree/drive/front/close requests.</summary>
/// <param name="automation">Shared UIA3 automation instance.</param>
/// <param name="response">Response object (steps append to <c>log</c>).</param>
internal sealed partial class Driver(UIA3Automation automation, JsonObject response)
{
    #region Dispatch

    /// <summary>Other app windows minimized by <c>isolate</c>; restored when the request ends.</summary>
    private readonly List<IntPtr> isolated = [];

    /// <summary>Whether input steps minimize overlapping windows of other same-named processes (other lanes).</summary>
    private bool isolate;

    /// <summary>
    /// Whether keyboard steps post messages to the app (<see cref="PostedInput"/>) instead of sending real input:
    /// the request's <c>post_keys</c>, else automatically while the console session is locked.
    /// </summary>
    private bool postKeys;

    /// <summary>Runs the request's <c>command</c>.</summary>
    /// <param name="request">Request JSON.</param>
    /// <returns>Command result JSON.</returns>
    public JsonNode Execute(JsonObject request)
    {
        var command = (string?)request["command"] ?? throw new ArgumentException("missing command");
        isolate = (bool?)request["isolate"] ?? false;
        postKeys = (bool?)request["post_keys"] ?? PostedInput.IsSessionLocked();
        try
        {
            return command switch
            {
                "launch" => Launch(request),
                "window" => Describe(FindWindow(request)),
                "resize" => Resize(FindWindow(request), request["op"]!.AsObject()),
                "shot" => Shot(FindWindow(request), (string)request["out"]!, (string?)request["mode"] ?? "print"),
                "tree" => Tree(FindWindow(request), (string?)request["out"], (int?)request["depth"] ?? 40),
                "drive" => Drive(FindWindow(request), request["steps"]!.AsArray()),
                "front" => Front(FindWindow(request)),
                "close" => Close(request),
                "sysset" => SysSet(request),
                "scan" => Scan(FindWindow(request), (string)request["out"]!, (string?)request["scanid"] ?? "scan"),
                _ => throw new ArgumentException($"unknown command {command}"),
            };
        }
        finally
        {
            RestoreIsolated();
        }
    }

    #endregion

    #region Foreground

    /// <summary>
    /// Makes the target the foreground window before real input: raises it to the top of the non-topmost band,
    /// optionally minimizes overlapping windows of other same-named processes (other lanes' app instances), activates
    /// it and waits until Windows reports it as foreground. Throws when it is still not foreground and something
    /// overlaps it from above, since clicks, wheel scrolls and keys would otherwise land in another window.
    /// </summary>
    /// <param name="window">Target.</param>
    /// <returns>State after the attempt: <c>foreground</c> and <c>covered_by</c> (windows above that overlap it).</returns>
    private JsonObject EnsureForeground(Window window)
    {
        var hwnd = window.Properties.NativeWindowHandle.Value;
        var pid = window.Properties.ProcessId.Value;
        if (isolate) IsolateFrom(hwnd, pid);
        var foreground = Native.BringToForeground(hwnd, TimeSpan.FromSeconds(3));
        var blockers = Native.WindowsAbove(hwnd, pid);
        if (!foreground && blockers.Count > 0)
        {
            throw new InvalidOperationException("target window is not foreground and is covered by " +
                string.Join(", ", blockers.Select(b => $"\"{b.Title}\" (pid {b.Pid})")) + "; retry with --isolate or close them");
        }
        var covered = new JsonArray();
        foreach (var blocker in blockers) covered.Add(JsonValue.Create($"{blocker.Title} (pid {blocker.Pid})"));
        return new JsonObject { ["foreground"] = foreground, ["covered_by"] = covered };
    }

    /// <summary>Minimizes visible, overlapping top-level windows of other processes with the target's name.</summary>
    /// <param name="hwnd">Target window.</param>
    /// <param name="pid">Target process.</param>
    private void IsolateFrom(IntPtr hwnd, int pid)
    {
        string name;
        try
        {
            using var target = Process.GetProcessById(pid);
            name = target.ProcessName;
        }
        catch (ArgumentException)
        {
            return;
        }
        var bounds = Native.VisibleBounds(hwnd);
        foreach (var other in Process.GetProcessesByName(name))
        {
            using (other)
            {
                if (other.Id == pid) continue;
                foreach (var candidate in Native.TopLevelWindows(other.Id))
                {
                    if (Native.IsIconic(candidate) || !Native.VisibleBounds(candidate).IntersectsWith(bounds)) continue;
                    Native.ShowWindow(candidate, Native.SwMinimize);
                    isolated.Add(candidate);
                    Log($"isolate: minimized pid {other.Id} window 0x{candidate.ToInt64():x}");
                }
            }
        }
    }

    /// <summary>Restores windows minimized by <see cref="IsolateFrom"/> without activating them.</summary>
    private void RestoreIsolated()
    {
        foreach (var hwnd in isolated) Native.ShowWindow(hwnd, Native.SwShowNoActivate);
        if (isolated.Count > 0) Log($"isolate: restored {isolated.Count} window(s)");
        isolated.Clear();
    }

    /// <summary><c>front</c>: foreground the target and report what (if anything) still covers it.</summary>
    /// <param name="window">Target.</param>
    /// <returns>Window description plus foreground state.</returns>
    private JsonNode Front(Window window)
    {
        var state = EnsureForeground(window);
        var result = Describe(window).AsObject();
        result["foreground"] = (bool)state["foreground"]!;
        result["covered_by"] = state["covered_by"]!.DeepClone();
        return result;
    }

    /// <summary>Appends a line to the response log.</summary>
    /// <param name="line">Text.</param>
    private void Log(string line)
    {
        if (response["log"] is not JsonArray log)
        {
            log = [];
            response["log"] = log;
        }
        log.Add(JsonValue.Create(line));
    }

    #endregion

    #region Launch and window lookup

    private JsonNode Launch(JsonObject request)
    {
        var start = new ProcessStartInfo((string)request["exe"]!)
        {
            UseShellExecute = false,
            WorkingDirectory = (string?)request["cwd"] ?? Path.GetDirectoryName((string)request["exe"]!)!,
        };
        foreach (var arg in request["args"]?.AsArray() ?? []) start.ArgumentList.Add((string)arg!);
        foreach (var (key, value) in request["env"]?.AsObject() ?? []) start.Environment[key] = (string?)value;
        var process = Process.Start(start) ?? throw new InvalidOperationException("process did not start");
        var timeout = TimeSpan.FromSeconds((double?)request["timeout"] ?? 30);
        var window = WaitForWindow(process.Id, timeout)
            ?? throw new TimeoutException($"no top-level window for pid {process.Id} within {timeout.TotalSeconds}s");
        var result = Describe(window).AsObject();
        result["pid"] = process.Id;
        return result;
    }

    private Window? WaitForWindow(int pid, TimeSpan timeout)
    {
        var until = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < until)
        {
            var window = TopWindow(pid);
            if (window is not null) return window;
            Thread.Sleep(250);
        }
        return null;
    }

    private Window? TopWindow(int pid)
    {
        var desktop = automation.GetDesktop();
        return desktop.FindAllChildren(cf => cf.ByProcessId(pid))
            .Where(e => !e.Properties.IsOffscreen.ValueOrDefault && e.Properties.BoundingRectangle.ValueOrDefault.Width > 0)
            .OrderByDescending(e => e.BoundingRectangle.Width * e.BoundingRectangle.Height)
            .Select(e => e.AsWindow())
            .FirstOrDefault();
    }

    private Window FindWindow(JsonObject request)
    {
        var pid = (int?)request["pid"];
        if (pid is null && request["process"] is JsonNode name)
        {
            pid = Process.GetProcessesByName((string)name!).Select(p => (int?)p.Id).FirstOrDefault()
                ?? throw new InvalidOperationException($"no process named {name}");
        }
        if (pid is null) throw new ArgumentException("target needs pid or process");
        return WaitForWindow(pid.Value, TimeSpan.FromSeconds(5))
            ?? throw new InvalidOperationException($"no visible window for pid {pid}");
    }

    private static JsonNode Describe(Window window)
    {
        var hwnd = window.Properties.NativeWindowHandle.Value;
        var bounds = Native.VisibleBounds(hwnd);
        var scale = Native.GetDpiForWindow(hwnd) / 96.0;
        var monitor = Native.Monitor(hwnd);
        return new JsonObject
        {
            ["pid"] = window.Properties.ProcessId.Value,
            ["title"] = window.Title,
            ["hwnd"] = hwnd.ToInt64(),
            ["bounds"] = Rect(bounds),
            ["bounds_epx"] = new JsonArray(Math.Round(bounds.Width / scale), Math.Round(bounds.Height / scale)),
            ["scale"] = scale,
            ["state"] = Native.IsZoomed(hwnd) ? "maximized" : Native.IsIconic(hwnd) ? "minimized" : "normal",
            ["monitor"] = Rect(monitor.Bounds),
            ["work_area"] = Rect(monitor.Work),
        };
    }

    private static JsonArray Rect(Rectangle r) => new(r.X, r.Y, r.Width, r.Height);

    #endregion

    #region Resize

    /// <summary>
    /// Applies a resize op: <c>size</c> (width/height in effective pixels, centred in the
    /// work area), <c>snap-left</c>/<c>snap-right</c> (work-area halves), <c>maximize</c>,
    /// <c>fullscreen</c> (whole monitor, covering the taskbar) or <c>restore</c>.
    /// </summary>
    private JsonNode Resize(Window window, JsonObject op)
    {
        var hwnd = window.Properties.NativeWindowHandle.Value;
        var kind = (string)op["kind"]!;
        var monitor = Native.Monitor(hwnd);
        var scale = Native.GetDpiForWindow(hwnd) / 96.0;
        if (kind == "maximize")
        {
            Native.ShowWindow(hwnd, Native.SwMaximize);
        }
        else
        {
            Native.ShowWindow(hwnd, Native.SwRestore);
            Rectangle target;
            var work = monitor.Work;
            switch (kind)
            {
                case "size":
                    var w = (int)Math.Round((double)op["width"]! * scale);
                    var h = (int)Math.Round((double)op["height"]! * scale);
                    w = Math.Min(w, work.Width);
                    h = Math.Min(h, work.Height);
                    target = new Rectangle(work.X + (work.Width - w) / 2, work.Y + (work.Height - h) / 2, w, h);
                    break;
                case "snap-left":
                    target = new Rectangle(work.X, work.Y, work.Width / 2, work.Height);
                    break;
                case "snap-right":
                    target = new Rectangle(work.X + work.Width / 2, work.Y, work.Width - work.Width / 2, work.Height);
                    break;
                case "fullscreen":
                    target = monitor.Bounds;
                    break;
                case "restore":
                    target = Native.VisibleBounds(hwnd);
                    break;
                default:
                    throw new ArgumentException($"unknown resize kind {kind}");
            }
            Native.MoveVisible(hwnd, target);
        }
        Thread.Sleep(600);
        return Describe(window);
    }

    #endregion

    #region Screenshot

    private JsonNode Shot(Window window, string output, string mode)
    {
        var hwnd = window.Properties.NativeWindowHandle.Value;
        var bounds = Native.VisibleBounds(hwnd);
        if (mode == "screen")
        {
            EnsureForeground(window);
            Thread.Sleep(300);
        }
        using var bitmap = mode == "screen" ? ScreenCapture(bounds) : Native.PrintWindow(hwnd, bounds);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
        bitmap.Save(output, ImageFormat.Png);
        var result = Describe(window).AsObject();
        result["out"] = output;
        result["size"] = new JsonArray(bitmap.Width, bitmap.Height);
        return result;
    }

    private static Bitmap ScreenCapture(Rectangle bounds)
    {
        var bitmap = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size);
        return bitmap;
    }

    #endregion

    #region Tree

    private JsonNode Tree(Window window, string? output, int depth)
    {
        var text = new StringBuilder();
        var walker = automation.TreeWalkerFactory.GetControlViewWalker();
        var count = 0;
        void Visit(AutomationElement element, int level)
        {
            count++;
            text.Append(' ', level * 2).AppendLine(Line(element));
            if (level >= depth) return;
            for (var child = walker.GetFirstChild(element); child is not null; child = walker.GetNextSibling(child))
            {
                Visit(child, level + 1);
            }
        }
        Visit(window, 0);
        if (output is not null)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
            File.WriteAllText(output, text.ToString());
        }
        return new JsonObject { ["nodes"] = count, ["out"] = output, ["text"] = output is null ? text.ToString() : null };
    }

    internal static string Line(AutomationElement e)
    {
        var p = e.Properties;
        var r = p.BoundingRectangle.ValueOrDefault;
        var flags = new List<string>();
        if (p.IsOffscreen.ValueOrDefault) flags.Add("offscreen");
        if (!p.IsEnabled.ValueOrDefault) flags.Add("disabled");
        if (p.HasKeyboardFocus.ValueOrDefault) flags.Add("focused");
        if (p.IsKeyboardFocusable.ValueOrDefault) flags.Add("focusable");
        var patterns = new List<string>();
        if (e.Patterns.Invoke.IsSupported) patterns.Add("Invoke");
        if (e.Patterns.Toggle.IsSupported) patterns.Add("Toggle");
        if (e.Patterns.SelectionItem.IsSupported) patterns.Add("SelectionItem");
        if (e.Patterns.ExpandCollapse.IsSupported) patterns.Add("ExpandCollapse");
        if (e.Patterns.Value.IsSupported) patterns.Add("Value");
        if (e.Patterns.RangeValue.IsSupported) patterns.Add("RangeValue");
        if (e.Patterns.Scroll.IsSupported) patterns.Add("Scroll");
        return $"{p.ControlType.ValueOrDefault} \"{p.Name.ValueOrDefault}\" id={p.AutomationId.ValueOrDefault} " +
               $"class={p.ClassName.ValueOrDefault} rect={r.X},{r.Y},{r.Width},{r.Height}" +
               (p.HelpText.ValueOrDefault is { Length: > 0 } help ? $" help=\"{help}\"" : "") +
               A11yFlags(e) +
               ToggleText(e) +
               (flags.Count > 0 ? $" [{string.Join(",", flags)}]" : "") +
               (patterns.Count > 0 ? $" patterns={string.Join(",", patterns)}" : "");
    }

    /// <summary>A toggle's state for tree lines (<c> toggle=On|Off|Indeterminate</c>), or empty.</summary>
    /// <param name="e">Element.</param>
    /// <returns>Suffix.</returns>
    private static string ToggleText(AutomationElement e)
    {
        try
        {
            return e.Patterns.Toggle.PatternOrDefault is { } toggle ? $" toggle={toggle.ToggleState.ValueOrDefault}" : "";
        }
        catch (Exception)
        {
            // An element can disappear between the pattern check and the read; the line stays without a state.
            return "";
        }
    }

    #endregion

    #region Drive

    /// <summary>Steps that send real mouse/keyboard input and so need the target in front.</summary>
    private static readonly HashSet<string> InputVerbs = ["click", "rightclick", "hover", "type", "key", "scroll", "tabwalk"];

    /// <summary>Keyboard steps that <see cref="postKeys"/> posts to the window instead (no foreground needed).</summary>
    private static readonly HashSet<string> KeyVerbs = ["type", "key", "tabwalk"];

    private JsonNode Drive(Window window, JsonArray steps)
    {
        if (postKeys) Log("keyboard steps are posted to the window (session locked or post_keys)");
        foreach (var node in steps)
        {
            var step = node!.AsObject();
            var verb = (string)step["verb"]!;
            var arg = (string?)step["arg"] ?? "";
            if (InputVerbs.Contains(verb) && !(postKeys && KeyVerbs.Contains(verb))
                && !(bool)EnsureForeground(window)["foreground"]!)
                Log("warning: target is not foreground (nothing covers it, so input proceeds)");
            RunStep(window, verb, arg, step);
            Log($"ok {verb}:{arg}");
        }
        var result = Describe(window).AsObject();
        foreach (var key in new[] { "focus", "scans" })
        {
            if (response[key] is not JsonArray collected) continue;
            response.Remove(key);
            result[key] = collected;
        }
        return result;
    }

    private void RunStep(Window window, string verb, string arg, JsonObject step)
    {
        switch (verb)
        {
            case "click":
                Click(window, step, MouseButton.Left);
                break;
            case "rightclick":
                Click(window, step, MouseButton.Right);
                break;
            case "hover":
                Mouse.MoveTo(ScreenPoint(window, step));
                break;
            case "invoke":
                var target = Find(window, step);
                if (target.Patterns.Invoke.IsSupported) target.Patterns.Invoke.Pattern.Invoke();
                else target.Click();
                break;
            case "toggle":
                Find(window, step).Patterns.Toggle.Pattern.Toggle();
                break;
            case "select":
                Find(window, step).Patterns.SelectionItem.Pattern.Select();
                break;
            case "expand":
                Find(window, step).Patterns.ExpandCollapse.Pattern.Expand();
                break;
            case "collapse":
                Find(window, step).Patterns.ExpandCollapse.Pattern.Collapse();
                break;
            case "focus":
                Find(window, step).Focus();
                break;
            case "waitfor":
                Find(window, step);
                break;
            case "type":
                if (postKeys) PostedInput.Type(window.Properties.NativeWindowHandle.Value, arg);
                else Keyboard.Type(arg);
                break;
            case "key":
                var keys = step["vk"]!.AsArray().Select(k => (VirtualKeyShort)(int)k!).ToArray();
                if (postKeys) PostedInput.Press(window.Properties.NativeWindowHandle.Value, keys);
                else Keyboard.TypeSimultaneously(keys);
                break;
            case "scroll":
                var amount = (double?)step["amount"] ?? -3;
                if (step["selector"] is not null) Mouse.MoveTo(Find(window, step).GetClickablePoint());
                Mouse.Scroll(amount);
                break;
            case "wait":
                Thread.Sleep(TimeSpan.FromSeconds(double.Parse(arg, System.Globalization.CultureInfo.InvariantCulture)));
                break;
            case "shot":
                Shot(window, arg, (string?)step["mode"] ?? "print");
                break;
            case "tree":
                Tree(window, arg, 40);
                break;
            case "resize":
                Resize(window, step["op"]!.AsObject());
                break;
            case "tabwalk":
                TabWalk(window, step);
                break;
            case "assertfocus":
                AssertFocus(window, step);
                break;
            case "scan":
                ScanStep(window, arg);
                break;
            case "setvalue":
                SetValue(Find(window, step), (string?)step["text"] ?? "");
                break;
            case "waitgone":
                WaitGone(window, step);
                break;
            case "scrollinto":
                ScrollInto(window, step);
                break;
            default:
                throw new ArgumentException($"unknown step {verb}");
        }
        Thread.Sleep(150);
    }

    private void Click(Window window, JsonObject step, MouseButton button) => Mouse.Click(ScreenPoint(window, step), button);

    /// <summary>Writes text through the UIA Value pattern, so no keyboard input is needed (works on a locked console).</summary>
    /// <param name="element">The field, or a container (e.g. an AutoSuggestBox) whose first editable descendant takes the text.</param>
    /// <param name="text">New value; empty clears the field.</param>
    private void SetValue(AutomationElement element, string text)
    {
        var target = element.Patterns.Value.IsSupported
            ? element
            : element.FindFirstDescendant(automation.ConditionFactory.ByControlType(FlaUI.Core.Definitions.ControlType.Edit))
              ?? throw new InvalidOperationException("element has no Value pattern or editable descendant");
        target.Patterns.Value.Pattern.SetValue(text);
    }

    /// <summary>Screen point of a step's selector: window-relative coordinates or the element's clickable point.</summary>
    private Point ScreenPoint(Window window, JsonObject step)
    {
        var selector = step["selector"]!.AsObject();
        if ((string)selector["kind"]! != "xy") return Find(window, step).GetClickablePoint();
        var bounds = Native.VisibleBounds(window.Properties.NativeWindowHandle.Value);
        return new Point(bounds.X + (int)selector["x"]!, bounds.Y + (int)selector["y"]!);
    }

    /// <summary>Waits until no on-screen element matches the step's selector (an absence assertion).</summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a selector and an optional timeout (default 5 s).</param>
    /// <exception cref="InvalidOperationException">A matching element is still on screen at the timeout.</exception>
    private void WaitGone(Window window, JsonObject step)
    {
        var (condition, label) = Condition(step);
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (window.FindAllDescendants(condition).Any(e => !e.Properties.IsOffscreen.ValueOrDefault))
        {
            if (DateTime.UtcNow > until) throw new InvalidOperationException($"element {label} is still on screen");
            Thread.Sleep(200);
        }
    }

    /// <summary>
    /// Brings an element that exists but is scrolled out of view (e.g. below the fold of a flyout's ScrollViewer) on
    /// screen through the UIA ScrollItem pattern, or by paging the nearest scrollable ancestor when the element has no
    /// ScrollItem pattern (e.g. an Expander), so no mouse wheel is needed (works on a locked console).
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a selector and an optional timeout (default 5 s).</param>
    /// <exception cref="InvalidOperationException">No element matches, or it is still off screen at the timeout.</exception>
    private void ScrollInto(Window window, JsonObject step)
    {
        var (condition, label) = Condition(step);
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (true)
        {
            var found = window.FindFirstDescendant(condition);
            if (found is not null)
            {
                if (!found.Properties.IsOffscreen.ValueOrDefault) return;
                if (found.Patterns.ScrollItem.IsSupported) found.Patterns.ScrollItem.Pattern.ScrollIntoView();
                else PageTowards(found);
            }
            if (DateTime.UtcNow > until) throw new InvalidOperationException($"could not scroll {label} on screen");
            Thread.Sleep(200);
        }
    }

    /// <summary>Scrolls the nearest vertically scrollable ancestor one page towards an off-screen element.</summary>
    /// <param name="element">Element to bring closer to its viewport.</param>
    private void PageTowards(AutomationElement element)
    {
        var walker = automation.TreeWalkerFactory.GetControlViewWalker();
        for (var parent = walker.GetParent(element); parent is not null; parent = walker.GetParent(parent))
        {
            if (!parent.Patterns.Scroll.IsSupported || !parent.Patterns.Scroll.Pattern.VerticallyScrollable.ValueOrDefault) continue;
            var target = element.BoundingRectangle;
            var viewport = parent.BoundingRectangle;
            var amount = target.Top >= viewport.Bottom || target.Bottom > viewport.Bottom
                ? FlaUI.Core.Definitions.ScrollAmount.LargeIncrement
                : FlaUI.Core.Definitions.ScrollAmount.LargeDecrement;
            parent.Patterns.Scroll.Pattern.Scroll(FlaUI.Core.Definitions.ScrollAmount.NoAmount, amount);
            return;
        }
    }

    private (ConditionBase Condition, string Label) Condition(JsonObject step)
    {
        var selector = step["selector"]!.AsObject();
        var kind = (string)selector["kind"]!;
        var value = (string)selector["value"]!;
        var cf = automation.ConditionFactory;
        ConditionBase condition = kind switch
        {
            "id" => cf.ByAutomationId(value),
            "name" => cf.ByName(value),
            "class" => cf.ByClassName(value),
            _ => throw new ArgumentException($"selector {kind} cannot locate an element"),
        };
        return (condition, $"{kind}={value}");
    }

    internal AutomationElement Find(Window window, JsonObject step)
    {
        var (condition, label) = Condition(step);
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (true)
        {
            var found = window.FindFirstDescendant(condition);
            if (found is not null && !found.Properties.IsOffscreen.ValueOrDefault) return found;
            if (DateTime.UtcNow > until) throw new InvalidOperationException($"no on-screen element {label}");
            Thread.Sleep(200);
        }
    }

    #endregion

    #region Close

    private JsonNode Close(JsonObject request)
    {
        var window = FindWindow(request);
        var pid = window.Properties.ProcessId.Value;
        window.Close();
        using var process = Process.GetProcessById(pid);
        if (!process.WaitForExit(5000)) process.Kill(entireProcessTree: true);
        return new JsonObject { ["pid"] = pid, ["closed"] = true };
    }

    #endregion
}

/// <summary>User32/DWM interop for window geometry and capture.</summary>
internal static class Native
{
    #region Interop

    public const int SwMaximize = 3;
    public const int SwRestore = 9;
    public const int SwMinimize = 6;
    public const int SwShowNoActivate = 4;
    private const int DwmwaCloaked = 14;
    private const uint GwHwndPrev = 3;
    private const int GwlExStyle = -20;
    private const long WsExTransparent = 0x20;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private static readonly IntPtr HwndTopmost = new(-1);
    private static readonly IntPtr HwndNoTopmost = new(-2);
    private const int DwmwaExtendedFrameBounds = 9;
    private const uint PwRenderFullContent = 2;
    private const uint SwpNoZOrder = 0x0004;
    private const uint SwpNoActivate = 0x0010;
    private const uint MonitorDefaultToNearest = 2;

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MONITORINFO { public int cbSize; public RECT rcMonitor; public RECT rcWork; public uint dwFlags; }

    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] private static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);
    [DllImport("user32.dll")] private static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out RECT value, int size);
    [DllImport("dwmapi.dll", EntryPoint = "DwmGetWindowAttribute")] private static extern int DwmGetWindowAttributeInt(IntPtr hwnd, int attribute, out int value, int size);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool BringWindowToTop(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] private static extern bool AttachThreadInput(uint attach, uint to, bool doAttach);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr hwnd, uint command);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetWindowLongPtrW(IntPtr hwnd, int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr data);
    [DllImport("user32.dll")] private static extern uint SendInput(uint count, INPUT[] inputs, int size);

    private delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr data);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public MOUSEINPUT mi; }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }

    #endregion

    #region Foreground and Z-order

    /// <summary>
    /// Raises and activates a window despite the foreground lock (this driver is a background process): a
    /// topmost/not-topmost bounce puts it above every normal window, then activation is retried with the foreground
    /// thread's input attached and after a zero-length mouse move (which makes this process the last input owner).
    /// </summary>
    /// <returns><see langword="true"/> when it became the foreground window within <paramref name="timeout"/>.</returns>
    public static bool BringToForeground(IntPtr hwnd, TimeSpan timeout)
    {
        if (IsIconic(hwnd)) ShowWindow(hwnd, SwRestore);
        SetWindowPos(hwnd, HwndTopmost, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoActivate);
        SetWindowPos(hwnd, HwndNoTopmost, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoActivate);
        var until = DateTime.UtcNow + timeout;
        for (var attempt = 0; DateTime.UtcNow < until; attempt++)
        {
            if (GetForegroundWindow() == hwnd) return true;
            if (attempt > 0) SendInput(1, [new INPUT { type = 0, mi = new MOUSEINPUT { dwFlags = 0x0001 } }], Marshal.SizeOf<INPUT>());
            var current = GetForegroundWindow();
            var foregroundThread = current == IntPtr.Zero ? 0 : GetWindowThreadProcessId(current, out _);
            var me = GetCurrentThreadId();
            var attached = foregroundThread != 0 && foregroundThread != me && AttachThreadInput(me, foregroundThread, true);
            try
            {
                BringWindowToTop(hwnd);
                SetForegroundWindow(hwnd);
            }
            finally
            {
                if (attached) AttachThreadInput(me, foregroundThread, false);
            }
            for (var i = 0; i < 10 && GetForegroundWindow() != hwnd; i++) Thread.Sleep(50);
        }
        return GetForegroundWindow() == hwnd;
    }

    /// <summary>Visible, uncloaked, non-click-through windows of other processes above the target that overlap it.</summary>
    public static List<(string Title, int Pid)> WindowsAbove(IntPtr hwnd, int ownPid)
    {
        var bounds = VisibleBounds(hwnd);
        var result = new List<(string, int)>();
        var count = 0;
        for (var other = GetWindow(hwnd, GwHwndPrev); other != IntPtr.Zero && count < 4096; other = GetWindow(other, GwHwndPrev), count++)
        {
            if (!IsWindowVisible(other) || IsIconic(other) || IsCloaked(other)) continue;
            if ((GetWindowLongPtrW(other, GwlExStyle).ToInt64() & WsExTransparent) != 0) continue;
            GetWindowThreadProcessId(other, out var pid);
            if (pid == ownPid) continue;
            var overlap = VisibleBounds(other);
            overlap.Intersect(bounds);
            if (overlap.Width <= 0 || overlap.Height <= 0) continue;
            var title = new StringBuilder(256);
            GetWindowTextW(other, title, title.Capacity);
            result.Add((title.ToString(), (int)pid));
        }
        return result;
    }

    /// <summary>Visible, uncloaked top-level windows owned by a process.</summary>
    public static List<IntPtr> TopLevelWindows(int pid)
    {
        var windows = new List<IntPtr>();
        EnumWindows((hwnd, _) =>
        {
            GetWindowThreadProcessId(hwnd, out var owner);
            if (owner == pid && IsWindowVisible(hwnd) && !IsCloaked(hwnd)) windows.Add(hwnd);
            return true;
        }, IntPtr.Zero);
        return windows;
    }

    /// <summary>Whether DWM cloaks the window (another virtual desktop or shell-hidden).</summary>
    private static bool IsCloaked(IntPtr hwnd) =>
        DwmGetWindowAttributeInt(hwnd, DwmwaCloaked, out var cloaked, sizeof(int)) == 0 && cloaked != 0;

    #endregion

    #region Geometry

    private static Rectangle ToRectangle(RECT r) => Rectangle.FromLTRB(r.Left, r.Top, r.Right, r.Bottom);

    /// <summary>Window rectangle including invisible resize borders.</summary>
    public static Rectangle WindowBounds(IntPtr hwnd)
    {
        GetWindowRect(hwnd, out var r);
        return ToRectangle(r);
    }

    /// <summary>Visible frame bounds (DWM extended frame, excluding invisible borders).</summary>
    public static Rectangle VisibleBounds(IntPtr hwnd)
    {
        return DwmGetWindowAttribute(hwnd, DwmwaExtendedFrameBounds, out var r, Marshal.SizeOf<RECT>()) == 0
            ? ToRectangle(r)
            : WindowBounds(hwnd);
    }

    /// <summary>Moves the window so its <em>visible</em> frame equals <paramref name="target"/>.</summary>
    public static void MoveVisible(IntPtr hwnd, Rectangle target)
    {
        var outer = WindowBounds(hwnd);
        var visible = VisibleBounds(hwnd);
        var left = visible.Left - outer.Left;
        var top = visible.Top - outer.Top;
        var right = outer.Right - visible.Right;
        var bottom = outer.Bottom - visible.Bottom;
        SetWindowPos(hwnd, IntPtr.Zero, target.X - left, target.Y - top,
            target.Width + left + right, target.Height + top + bottom, SwpNoZOrder | SwpNoActivate);
    }

    /// <summary>Monitor and work-area rectangles for the window's nearest monitor.</summary>
    public static (Rectangle Bounds, Rectangle Work) Monitor(IntPtr hwnd)
    {
        var info = new MONITORINFO { cbSize = Marshal.SizeOf<MONITORINFO>() };
        GetMonitorInfo(MonitorFromWindow(hwnd, MonitorDefaultToNearest), ref info);
        return (ToRectangle(info.rcMonitor), ToRectangle(info.rcWork));
    }

    /// <summary>Renders the window (even if occluded) and crops to its visible frame.</summary>
    public static Bitmap PrintWindow(IntPtr hwnd, Rectangle visible)
    {
        var outer = WindowBounds(hwnd);
        using var full = new Bitmap(outer.Width, outer.Height, PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(full))
        {
            var hdc = graphics.GetHdc();
            try { PrintWindow(hwnd, hdc, PwRenderFullContent); }
            finally { graphics.ReleaseHdc(hdc); }
        }
        var crop = new Rectangle(visible.X - outer.X, visible.Y - outer.Y, visible.Width, visible.Height);
        crop.Intersect(new Rectangle(0, 0, full.Width, full.Height));
        return full.Clone(crop, PixelFormat.Format32bppArgb);
    }

    #endregion
}
