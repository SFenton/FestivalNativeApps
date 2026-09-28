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

/// <summary>Executes launch/window/resize/shot/tree/drive/close requests.</summary>
/// <param name="automation">Shared UIA3 automation instance.</param>
/// <param name="response">Response object (steps append to <c>log</c>).</param>
internal sealed class Driver(UIA3Automation automation, JsonObject response)
{
    #region Dispatch

    /// <summary>Runs the request's <c>command</c>.</summary>
    /// <param name="request">Request JSON.</param>
    /// <returns>Command result JSON.</returns>
    public JsonNode Execute(JsonObject request)
    {
        var command = (string?)request["command"] ?? throw new ArgumentException("missing command");
        return command switch
        {
            "launch" => Launch(request),
            "window" => Describe(FindWindow(request)),
            "resize" => Resize(FindWindow(request), request["op"]!.AsObject()),
            "shot" => Shot(FindWindow(request), (string)request["out"]!, (string?)request["mode"] ?? "print"),
            "tree" => Tree(FindWindow(request), (string?)request["out"], (int?)request["depth"] ?? 40),
            "drive" => Drive(FindWindow(request), request["steps"]!.AsArray()),
            "close" => Close(request),
            _ => throw new ArgumentException($"unknown command {command}"),
        };
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
        using var bitmap = mode == "screen" ? ScreenCapture(window, bounds) : Native.PrintWindow(hwnd, bounds);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
        bitmap.Save(output, ImageFormat.Png);
        var result = Describe(window).AsObject();
        result["out"] = output;
        result["size"] = new JsonArray(bitmap.Width, bitmap.Height);
        return result;
    }

    private static Bitmap ScreenCapture(Window window, Rectangle bounds)
    {
        window.SetForeground();
        Thread.Sleep(300);
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

    private static string Line(AutomationElement e)
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
               (flags.Count > 0 ? $" [{string.Join(",", flags)}]" : "") +
               (patterns.Count > 0 ? $" patterns={string.Join(",", patterns)}" : "");
    }

    #endregion

    #region Drive

    private JsonNode Drive(Window window, JsonArray steps)
    {
        var log = new JsonArray();
        response["log"] = log;
        foreach (var node in steps)
        {
            var step = node!.AsObject();
            var verb = (string)step["verb"]!;
            var arg = (string?)step["arg"] ?? "";
            RunStep(window, verb, arg, step);
            log.Add(JsonValue.Create($"ok {verb}:{arg}"));
        }
        return Describe(window);
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
                window.SetForeground();
                Keyboard.Type(arg);
                break;
            case "key":
                window.SetForeground();
                var keys = step["vk"]!.AsArray().Select(k => (VirtualKeyShort)(int)k!).ToArray();
                Keyboard.TypeSimultaneously(keys);
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
            default:
                throw new ArgumentException($"unknown step {verb}");
        }
        Thread.Sleep(150);
    }

    private void Click(Window window, JsonObject step, MouseButton button)
    {
        var selector = step["selector"]!.AsObject();
        Point point;
        if ((string)selector["kind"]! == "xy")
        {
            var bounds = Native.VisibleBounds(window.Properties.NativeWindowHandle.Value);
            point = new Point(bounds.X + (int)selector["x"]!, bounds.Y + (int)selector["y"]!);
        }
        else
        {
            point = Find(window, step).GetClickablePoint();
        }
        window.SetForeground();
        Mouse.Click(point, button);
    }

    private AutomationElement Find(Window window, JsonObject step)
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
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (true)
        {
            var found = window.FindFirstDescendant(condition);
            if (found is not null && !found.Properties.IsOffscreen.ValueOrDefault) return found;
            if (DateTime.UtcNow > until) throw new InvalidOperationException($"no on-screen element {kind}={value}");
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
