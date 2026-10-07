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

    /// <summary>Top-to-top distances (epx) recorded by <c>markspan</c>, by name, for <c>assertspan</c>.</summary>
    private readonly Dictionary<string, double> spans = [];

    /// <summary>The two elements each <c>markspan</c> measured, so <c>assertspan</c> rereads their bounds without a tree search.</summary>
    private readonly Dictionary<string, (AutomationElement Top, AutomationElement Other)> spanElements = [];

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
            ?? MinimizedWindow(pid.Value)
            ?? throw new InvalidOperationException($"no visible window for pid {pid}");
    }

    /// <summary>
    /// The app's minimized top-level window (UIA reports it offscreen, so <see cref="TopWindow"/> skips it), letting a
    /// later request restore a window an earlier request minimized (e.g. <c>resize:restored</c>).
    /// </summary>
    /// <param name="pid">App process ID.</param>
    /// <returns>The window, or <see langword="null"/> when none is minimized.</returns>
    private Window? MinimizedWindow(int pid) => automation.GetDesktop().FindAllChildren(cf => cf.ByProcessId(pid))
        .Where(e => e.Properties.NativeWindowHandle.ValueOrDefault is var hwnd && hwnd != IntPtr.Zero && Native.IsIconic(hwnd))
        .Select(e => e.AsWindow())
        .FirstOrDefault();

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
    /// <c>minimize</c>, <c>fullscreen</c> (whole monitor, covering the taskbar) or <c>restore</c>.
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
        else if (kind == "minimize")
        {
            Native.ShowWindow(hwnd, Native.SwMinimize);
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

    /// <summary>A background <c>PrintWindow</c> capture started by <c>film</c> and written by <c>filmstop</c>.</summary>
    private sealed class Film
    {
        /// <summary>Most frames kept (about 15 s at the usual rate).</summary>
        public const int MaxFrames = 300;

        /// <summary>Widest stored frame, in pixels (frames are scaled down to it).</summary>
        public const int MaxWidth = 1280;

        /// <summary>Capture thread.</summary>
        public required Thread Thread { get; init; }

        /// <summary>Output folder.</summary>
        public required string Folder { get; init; }

        /// <summary>Captured JPEG frames with their offsets (ms) from the first one.</summary>
        public List<(double Ms, byte[] Jpeg)> Frames { get; } = [];

        /// <summary>Set to end the capture.</summary>
        public volatile bool Stop;
    }

    private Film? film;

    /// <summary>
    /// <c>film:&lt;dir&gt;</c>: captures the window with <c>PrintWindow</c> as fast as it can (scaled to at most
    /// <see cref="Film.MaxWidth"/> px, JPEG in memory) on a background thread while later steps run, so a short
    /// transition such as a fade is sampled at a real frame rate. <c>filmstop</c> writes the frames.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="folder">Folder the frames are written to on <c>filmstop</c>.</param>
    /// <exception cref="InvalidOperationException">A capture is already running.</exception>
    private void StartFilm(Window window, string folder)
    {
        if (film is not null) throw new InvalidOperationException("film: a capture is already running; filmstop it first");
        var hwnd = window.Properties.NativeWindowHandle.Value;
        var bounds = Native.VisibleBounds(hwnd);
        var encoder = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
        Film? current = null;
        var thread = new Thread(() =>
        {
            using var quality = new EncoderParameters(1);
            quality.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, 88L);
            var clock = Stopwatch.StartNew();
            while (!current!.Stop && current.Frames.Count < Film.MaxFrames)
            {
                var at = clock.Elapsed.TotalMilliseconds;
                try
                {
                    using var full = Native.PrintWindow(hwnd, bounds);
                    var factor = Math.Min(1.0, Film.MaxWidth / (double)full.Width);
                    using var small = new Bitmap(full, (int)(full.Width * factor), (int)(full.Height * factor));
                    using var stream = new MemoryStream();
                    small.Save(stream, encoder, quality);
                    lock (current.Frames) current.Frames.Add((at, stream.ToArray()));
                }
                catch (Exception error) when (error is InvalidOperationException or ExternalException or ArgumentException)
                {
                    break; // the window went away mid-capture: keep the frames so far rather than crash the driver
                }
            }
        }) { IsBackground = true, Name = "film" };
        current = new Film { Thread = thread, Folder = folder };
        film = current;
        thread.Start();
    }

    /// <summary>
    /// <c>filmstop:&lt;dir&gt;</c>: ends the <c>film</c> capture and writes <c>f0000.jpg</c>… plus <c>frames.json</c>
    /// (each frame's offset in ms) to its folder.
    /// </summary>
    /// <param name="folder">Must match the folder <c>film</c> was started with.</param>
    /// <exception cref="InvalidOperationException">No capture is running, or it was started for another folder.</exception>
    private void StopFilm(string folder)
    {
        if (film is not { } current) throw new InvalidOperationException("filmstop: no film capture is running");
        if (!string.Equals(Path.GetFullPath(current.Folder), Path.GetFullPath(folder), StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException($"filmstop: the running capture writes to {current.Folder}, not {folder}");
        current.Stop = true;
        current.Thread.Join();
        film = null;
        Directory.CreateDirectory(folder);
        var offsets = new JsonArray();
        for (var i = 0; i < current.Frames.Count; i++)
        {
            File.WriteAllBytes(Path.Combine(folder, $"f{i:0000}.jpg"), current.Frames[i].Jpeg);
            offsets.Add(Math.Round(current.Frames[i].Ms, 1));
        }
        File.WriteAllText(Path.Combine(folder, "frames.json"), new JsonObject { ["ms"] = offsets }.ToJsonString());
        var seconds = current.Frames.Count > 1 ? current.Frames[^1].Ms / 1000 : 0;
        response["film"] = new JsonObject
        {
            ["dir"] = folder,
            ["frames"] = current.Frames.Count,
            ["fps"] = seconds > 0 ? Math.Round((current.Frames.Count - 1) / seconds, 1) : 0,
        };
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
        if (e.Patterns.SelectionItem.IsSupported)
        {
            patterns.Add("SelectionItem");
            if (e.Patterns.SelectionItem.PatternOrDefault?.IsSelected.ValueOrDefault == true) flags.Add("selected");
        }
        if (e.Patterns.ExpandCollapse.IsSupported) patterns.Add("ExpandCollapse");
        if (e.Patterns.Value.IsSupported) patterns.Add("Value");
        if (e.Patterns.RangeValue.IsSupported) patterns.Add("RangeValue");
        if (e.Patterns.Scroll.IsSupported) patterns.Add("Scroll");
        return $"{Role(e)} \"{p.Name.ValueOrDefault}\" id={p.AutomationId.ValueOrDefault} " +
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

    /// <summary>
    /// The element's control type name. FlaUI throws <see cref="NotSupportedException"/> for control type ids newer
    /// than its enum (e.g. inside WinUI's FlipView/PipsPager), so those fall back to the localized type.
    /// </summary>
    /// <param name="e">Element.</param>
    /// <returns>Control type name, or <c>Unknown(localized type)</c>.</returns>
    internal static string Role(AutomationElement e)
    {
        try
        {
            return e.Properties.ControlType.ValueOrDefault.ToString();
        }
        catch (NotSupportedException)
        {
            return $"Unknown({e.Properties.LocalizedControlType.ValueOrDefault})";
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
        if (announcementHandler is not null)
            response["announcements"] = new JsonArray([.. announcements.Select(a => (JsonNode)JsonValue.Create(a)!)]);
        foreach (var key in new[] { "focus", "scans", "aligned", "pinned", "announcements", "paint", "bold" })
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
            case "keys":
                // Chords back to back with no settle between them, e.g. several picks inside one short transition.
                var chords = step["seq"]!.AsArray().Select(c => c!.AsArray().Select(k => (VirtualKeyShort)(int)k!).ToArray()).ToArray();
                for (var i = 0; i < chords.Length; i++)
                {
                    if (postKeys) PostedInput.Press(window.Properties.NativeWindowHandle.Value, chords[i], settle: i == chords.Length - 1);
                    else Keyboard.TypeSimultaneously(chords[i]);
                }
                break;
            case "scroll":
                var amount = (double?)step["amount"] ?? -3;
                if (step["selector"] is not null) Mouse.MoveTo(Find(window, step).GetClickablePoint());
                Mouse.Scroll(amount);
                break;
            case "scrollto":
                var scroller = Find(window, step);
                if (!scroller.Patterns.Scroll.IsSupported) throw new InvalidOperationException("scrollto target has no Scroll pattern");
                scroller.Patterns.Scroll.Pattern.SetScrollPercent(-1, (double)step["percent"]!);
                break;
            case "reveal":
                Reveal(window, step);
                break;
            case "wait":
                Thread.Sleep(TimeSpan.FromSeconds(double.Parse(arg, System.Globalization.CultureInfo.InvariantCulture)));
                break;
            case "shot":
                Shot(window, arg, (string?)step["mode"] ?? "print");
                break;
            case "film":
                StartFilm(window, arg);
                break;
            case "filmstop":
                StopFilm(arg);
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
            case "assertname":
                AssertName(window, step);
                break;
            case "assertaligned":
                AssertAligned(window, step);
                break;
            case "assertnoscrollbar":
                AssertNoScrollBar(window, step);
                break;
            case "assertbelow":
            case "assertlevel":
                AssertVertical(window, step, verb == "assertbelow");
                break;
            case "assertgap":
                AssertGap(window, step);
                break;
            case "assertinset":
                AssertInset(window, step);
                break;
            case "markspan":
            case "assertspan":
                Span(window, step, verb == "assertspan");
                break;
            case "scrollinset":
                ScrollInset(window, step);
                break;
            case "assertstatus":
                AssertStatus(window, step);
                break;
            case "foreground":
                SetForeground(window, arg == "on");
                break;
            case "assertstate":
                AssertState(window, step);
                break;
            case "pin":
            case "assertpinned":
                Pin(window, step, verb == "pin");
                break;
            case "listen":
                Listen(window);
                break;
            case "assertannounced":
                AssertAnnounced(step);
                break;
            case "assertpaint":
                AssertPaint(window, step);
                break;
            case "assertbold":
                AssertBold(window, step);
                break;
            case "assertannouncedcount":
                AssertAnnouncedCount(step);
                break;
            default:
                throw new ArgumentException($"unknown step {verb}");
        }
        Thread.Sleep(150);
    }

    private void Click(Window window, JsonObject step, MouseButton button) => Mouse.Click(ScreenPoint(window, step), button);

    /// <summary>
    /// Brings the target on screen without real input (works on a locked console): an existing target is scrolled into view
    /// through UIA ScrollItem; otherwise (or if that is not enough) its vertical scroller is stepped through the UIA Scroll
    /// pattern from the top, a viewport at a time. Virtualized targets need not exist yet: the window's first vertically
    /// scrollable element is used then.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a selector and an optional timeout (at most 2 s is spent waiting for the target to appear).</param>
    /// <exception cref="InvalidOperationException">No scroller, or the target never came on screen.</exception>
    private void Reveal(Window window, JsonObject step)
    {
        var (condition, label) = Condition(step);
        var raw = IsRaw(step);
        bool OnScreen(out AutomationElement? found)
        {
            found = InView(raw, () => window.FindFirstDescendant(condition));
            return found is not null && !found.Properties.IsOffscreen.ValueOrDefault;
        }
        // Give a loading page a moment to create the target; a virtualized target that is never realized falls through to stepping.
        var until = DateTime.UtcNow + TimeSpan.FromSeconds(Math.Min((double?)step["timeout"] ?? 5, 2));
        AutomationElement? target;
        while (!OnScreen(out target) && target is null && DateTime.UtcNow < until) Thread.Sleep(200);
        if (target is not null && !target.Properties.IsOffscreen.ValueOrDefault) return;
        if (target is not null && target.Patterns.ScrollItem.IsSupported)
        {
            target.Patterns.ScrollItem.Pattern.ScrollIntoView();
            Thread.Sleep(250);
            if (OnScreen(out var scrolled)) return;
            target = scrolled ?? target;
        }
        AutomationElement? scroller = null;
        var walker = automation.TreeWalkerFactory.GetControlViewWalker();
        for (var parent = target is null ? null : walker.GetParent(target); parent is not null; parent = walker.GetParent(parent))
        {
            if (parent.Patterns.Scroll.IsSupported && parent.Patterns.Scroll.Pattern.VerticallyScrollable.ValueOrDefault) { scroller = parent; break; }
        }
        scroller ??= window.FindAllDescendants(automation.ConditionFactory.ByControlType(FlaUI.Core.Definitions.ControlType.Pane))
            .FirstOrDefault(e => e.Patterns.Scroll.IsSupported && e.Patterns.Scroll.Pattern.VerticallyScrollable.ValueOrDefault)
            ?? throw new InvalidOperationException("reveal found no vertical scroller");
        var scroll = scroller.Patterns.Scroll.Pattern;
        // Step by most of a viewport (VerticalViewSize is the visible share of the extent, which grows as items realize).
        for (var percent = 0.0; percent <= 100; percent += Math.Clamp(scroll.VerticalViewSize.ValueOrDefault * 0.8, 0.5, 5))
        {
            scroll.SetScrollPercent(-1, percent);
            Thread.Sleep(250);
            if (OnScreen(out _)) return;
        }
        scroll.SetScrollPercent(-1, 100);
        Thread.Sleep(250);
        if (OnScreen(out _)) return;
        throw new InvalidOperationException($"reveal could not bring {label} on screen");
    }

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

    /// <summary>
    /// Waits until an element matching the selector reports the expected UIA <c>ItemStatus</c>. Off-screen and raw-view
    /// elements count (e.g. the decorative backdrop's state while the window is minimized). Unless the expected status is
    /// <c>not-visible</c>, <c>=background</c> or a held Shop pulse (<c>pulse=held</c>), the window is brought to the front
    /// first (and every 2 s), since the backdrop pauses when covered.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a selector, the expected <c>status</c> and an optional timeout (default 5 s).</param>
    /// <exception cref="InvalidOperationException">No match, or the status still differs at the timeout.</exception>
    private void AssertStatus(Window window, JsonObject step)
    {
        var (condition, label) = Condition(step);
        var expected = (string)step["status"]!;
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        // FindFirst's default cache request filters to the control view; a raw-view element needs a true tree filter.
        var rawView = new FlaUI.Core.CacheRequest
        {
            TreeFilter = TrueCondition.Default,
            TreeScope = FlaUI.Core.Definitions.TreeScope.Element,
            AutomationElementMode = FlaUI.Core.Definitions.AutomationElementMode.Full,
        };
        rawView.Add(automation.PropertyLibrary.Element.ItemStatus);
        // The backdrop is occlusion-aware: asserting a visible state needs the window in front of other lanes' windows
        // (a not-visible assertion, including a first-run demo's rotation=not-visible or a held Shop pulse, must not
        // restore a minimized window, and a rotation=background one must not reactivate a window that foreground:off
        // deactivated).
        var front = !expected.Contains("not-visible", StringComparison.Ordinal) && !expected.Contains("=background", StringComparison.Ordinal)
            && !expected.Contains("pulse=held", StringComparison.Ordinal);
        var nextFront = DateTime.MinValue;
        while (true)
        {
            if (front && DateTime.UtcNow >= nextFront)
            {
                EnsureForeground(window);
                nextFront = DateTime.UtcNow.AddSeconds(2);
            }
            string? seen;
            using (rawView.Activate())
                seen = window.FindFirstDescendant(condition)?.Properties.ItemStatus.ValueOrDefault;
            if (StatusMatches(seen, expected)) return;
            if (DateTime.UtcNow > until)
                throw new InvalidOperationException($"element {label} status is {(seen is null ? "missing" : $"\"{seen}\"")}, expected \"{expected}\"");
            Thread.Sleep(200);
        }
    }

    /// <summary>
    /// <c>foreground:on</c> activates the app window (as <see cref="EnsureForeground"/>); <c>foreground:off</c> hands
    /// activation to the taskbar, which doesn't overlap the window, so the app stays visible and uncovered but is no longer
    /// the foreground window (e.g. a first-run demo's <c>rotation=background</c>, issue #258). While the session is locked
    /// (or <c>post_keys</c>), real activation is refused, so both send <c>WM_ACTIVATE</c> to the window instead, which
    /// raises WinUI's <c>Window.Activated</c> the same way.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="on">Activate (<see langword="true"/>) or deactivate it.</param>
    /// <exception cref="InvalidOperationException">The window's foreground state did not change as asked.</exception>
    private void SetForeground(Window window, bool on)
    {
        var hwnd = window.Properties.NativeWindowHandle.Value;
        if (postKeys)
        {
            PostedInput.Activate(hwnd, on);
            Log($"foreground:{(on ? "on" : "off")} sent as WM_ACTIVATE (session locked or post_keys)");
            return;
        }
        if (on)
        {
            if (!(bool)EnsureForeground(window)["foreground"]!) throw new InvalidOperationException("foreground:on could not activate the app window");
            return;
        }
        if (!Native.Deactivate(hwnd, TimeSpan.FromSeconds(3)))
            throw new InvalidOperationException("foreground:off could not move activation to the taskbar (locked console?)");
        if (Native.WindowsAbove(hwnd, window.Properties.ProcessId.Value) is { Count: > 0 } above)
            throw new InvalidOperationException("foreground:off left the window covered by " + string.Join(", ", above.Select(b => $"\"{b.Title}\"")));
    }

    /// <summary>UIA notification texts (what Narrator speaks) raised in the window since <c>listen:announcements</c>.</summary>
    private readonly System.Collections.Concurrent.ConcurrentQueue<string> announcements = new();

    /// <summary>The window's notification subscription, or <see langword="null"/> before <c>listen</c>.</summary>
    private FlaUI.Core.EventHandlers.NotificationEventHandlerBase? announcementHandler;

    /// <summary>
    /// Starts recording the window's UIA notification events (<c>RaiseNotificationEvent</c>: the app's screen-reader
    /// announcements) for later <c>assertannounced</c> steps in the same <c>drive</c>.
    /// </summary>
    /// <param name="window">App window (its subtree includes dialogs hosted in the window's popups).</param>
    private void Listen(Window window)
    {
        // WinUI raises notifications from peers whose UIA parent chain can stop short of the window (a UserControl's
        // created peer inside a dialog popup), so a window-scoped subscription hears nothing: listen at the desktop and
        // keep this process's notifications only.
        if (announcementHandler is not null) return;
        var processId = window.Properties.ProcessId.Value;
        announcementHandler = automation.GetDesktop().RegisterNotificationEvent(FlaUI.Core.Definitions.TreeScope.Subtree,
            (sender, _, _, text, _) =>
            {
                int? from = null;
                try { from = sender?.Properties.ProcessId.ValueOrDefault; } catch (Exception) { /* sender gone */ }
                if (from is null or 0 || from == processId) announcements.Enqueue(text ?? "");
            });
    }

    /// <summary>
    /// Waits until a recorded announcement equals the step's text (or matches it as a .NET regex when it starts with
    /// <c>~</c>).
    /// </summary>
    /// <param name="step">Step with <c>text</c> and an optional timeout (default 5 s).</param>
    /// <exception cref="InvalidOperationException">No <c>listen</c> step ran, or nothing matched by the timeout.</exception>
    private void AssertAnnounced(JsonObject step)
    {
        if (announcementHandler is null) throw new InvalidOperationException("assertannounced needs an earlier listen:announcements step in the same drive");
        var expected = (string)step["text"]!;
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (!announcements.Any(a => StatusMatches(a, expected)))
        {
            if (DateTime.UtcNow > until)
                throw new InvalidOperationException($"no announcement \"{expected}\"; heard [{string.Join(" | ", announcements)}]");
            Thread.Sleep(100);
        }
    }

    /// <summary>
    /// Fails unless exactly the step's count of recorded announcements match its text (exact, or a <c>~</c> regex) so far,
    /// e.g. a value spoken once and not repeated by later reads.
    /// </summary>
    /// <param name="step">Step with <c>count</c> and <c>text</c>.</param>
    /// <exception cref="InvalidOperationException">No <c>listen</c> step ran, or the count differs.</exception>
    private void AssertAnnouncedCount(JsonObject step)
    {
        if (announcementHandler is null) throw new InvalidOperationException("assertannouncedcount needs an earlier listen:announcements step in the same drive");
        var expected = (string)step["text"]!;
        var count = (int)step["count"]!;
        var heard = announcements.Count(a => StatusMatches(a, expected));
        if (heard != count)
            throw new InvalidOperationException($"announcement \"{expected}\" heard {heard} time(s), expected {count}; heard [{string.Join(" | ", announcements)}]");
    }

    /// <summary>Whether an ItemStatus equals the expected text, or matches it as a regex when it starts with <c>~</c>.</summary>
    /// <param name="seen">ItemStatus, or <see langword="null"/> when the element is missing.</param>
    /// <param name="expected">Exact status, or <c>~</c> followed by a .NET regular expression.</param>
    /// <returns>Whether it matches.</returns>
    internal static bool StatusMatches(string? seen, string expected) =>
        seen is not null && (expected.StartsWith('~')
            ? System.Text.RegularExpressions.Regex.IsMatch(seen, expected[1..])
            : seen == expected);

    /// <summary>
    /// Waits until the selected element's toggle state (<c>on</c>/<c>off</c>/<c>indeterminate</c>), enabled flag
    /// (<c>true</c>/<c>false</c>), SelectionItem <c>IsSelected</c> (<c>true</c>/<c>false</c>), rounded vertical scroll
    /// percent (<c>scroll</c>) or name equals the step's value.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a selector, <c>key</c>, <c>value</c> and an optional timeout (default 5 s).</param>
    /// <exception cref="InvalidOperationException">The element is missing or the state differs at the timeout.</exception>
    private void AssertState(Window window, JsonObject step)
    {
        var (condition, label) = Condition(step);
        var key = (string)step["key"]!;
        var expected = (string)step["value"]!;
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (true)
        {
            string? seen = null;
            if (window.FindFirstDescendant(condition) is { } element)
            {
                seen = key switch
                {
                    "toggle" => element.Patterns.Toggle.PatternOrDefault?.ToggleState.ValueOrDefault switch
                    {
                        FlaUI.Core.Definitions.ToggleState.On => "on",
                        FlaUI.Core.Definitions.ToggleState.Off => "off",
                        FlaUI.Core.Definitions.ToggleState.Indeterminate => "indeterminate",
                        _ => null,
                    },
                    "enabled" => element.Properties.IsEnabled.ValueOrDefault ? "true" : "false",
                    "selected" => element.Patterns.SelectionItem.PatternOrDefault is { } item
                        ? item.IsSelected.ValueOrDefault ? "true" : "false"
                        : null,
                    // Rounded vertical scroll percent (-1 when the content fits), e.g. a list back at its top.
                    "scroll" => element.Patterns.Scroll.PatternOrDefault is { } scroll
                        ? Math.Round(scroll.VerticalScrollPercent.ValueOrDefault).ToString(System.Globalization.CultureInfo.InvariantCulture)
                        : null,
                    // Role checks, e.g. a leaderboard row without a destination is Text with no Invoke and no Tab stop.
                    "type" => element.Properties.ControlType.ValueOrDefault.ToString().ToLowerInvariant(),
                    "invoke" => element.Patterns.Invoke.IsSupported ? "true" : "false",
                    "focusable" => element.Properties.IsKeyboardFocusable.ValueOrDefault ? "true" : "false",
                    // What Narrator reads after a combo box's name: its Value, else the selected item's name.
                    "value" => element.Patterns.Value.PatternOrDefault?.Value.ValueOrDefault is { Length: > 0 } text
                        ? text
                        : element.Patterns.Selection.PatternOrDefault?.Selection.ValueOrDefault is { Length: > 0 } picked
                            ? picked[0].Properties.Name.ValueOrDefault
                            : null,
                    _ => element.Properties.Name.ValueOrDefault,
                };
            }
            if (seen == expected) return;
            if (DateTime.UtcNow > until)
                throw new InvalidOperationException($"element {label} {key} is {(seen is null ? "missing" : $"\"{seen}\"")}, expected \"{expected}\"");
            Thread.Sleep(200);
        }
    }

    /// <summary>Waits until no on-screen element matches the step's selector (an absence assertion).</summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a selector and an optional timeout (default 5 s).</param>
    /// <exception cref="InvalidOperationException">A matching element is still on screen at the timeout.</exception>
    private void WaitGone(Window window, JsonObject step)
    {
        var (condition, label) = Condition(step);
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (InView(IsRaw(step), () => window.FindAllDescendants(condition)).Any(e => !e.Properties.IsOffscreen.ValueOrDefault))
        {
            if (DateTime.UtcNow > until) throw new InvalidOperationException($"element {label} is still on screen");
            Thread.Sleep(200);
        }
    }

    /// <summary>
    /// Brings an element that exists but is scrolled out of view (e.g. below the fold of a flyout's ScrollViewer) on
    /// screen through the UIA ScrollItem pattern, or by paging the nearest scrollable ancestor when the element has no
    /// ScrollItem pattern (e.g. an Expander), so no mouse wheel is needed (works on a locked console). While nothing matches
    /// yet (a virtualized list hasn't realized the item), it pages the window's largest scrollable region down.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a selector and an optional timeout (default 5 s).</param>
    /// <exception cref="InvalidOperationException">No element matches, or it is still off screen at the timeout.</exception>
    private void ScrollInto(Window window, JsonObject step)
    {
        var (condition, label) = Condition(step);
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        var sweepDown = true;
        while (true)
        {
            var found = InView(IsRaw(step), () => window.FindFirstDescendant(condition));
            if (found is not null)
            {
                if (!found.Properties.IsOffscreen.ValueOrDefault) return;
                if (found.Patterns.ScrollItem.IsSupported) found.Patterns.ScrollItem.Pattern.ScrollIntoView();
                else sweepDown = PageTowards(found, sweepDown);
            }
            else PageDown(window);
            if (DateTime.UtcNow > until) throw new InvalidOperationException($"could not scroll {label} on screen");
            Thread.Sleep(200);
        }
    }

    /// <summary>
    /// Pages the window's largest vertically scrollable region down one page, so a virtualized list realizes items that
    /// don't exist yet (nothing happens once every region is at its end).
    /// </summary>
    /// <param name="window">App window.</param>
    private void PageDown(Window window)
    {
        var scrollable = automation.ConditionFactory.ByControlType(FlaUI.Core.Definitions.ControlType.Pane)
            .Or(automation.ConditionFactory.ByControlType(FlaUI.Core.Definitions.ControlType.List))
            .Or(automation.ConditionFactory.ByControlType(FlaUI.Core.Definitions.ControlType.Group));
        var target = window.FindAllDescendants(scrollable)
            .Where(e => e.Patterns.Scroll.IsSupported && e.Patterns.Scroll.Pattern.VerticallyScrollable.ValueOrDefault &&
                        e.Patterns.Scroll.Pattern.VerticalScrollPercent.ValueOrDefault < 100)
            .OrderByDescending(e => e.BoundingRectangle.Width * e.BoundingRectangle.Height)
            .FirstOrDefault();
        target?.Patterns.Scroll.Pattern.Scroll(FlaUI.Core.Definitions.ScrollAmount.NoAmount, FlaUI.Core.Definitions.ScrollAmount.LargeIncrement);
    }

    /// <summary>
    /// Scrolls the nearest vertically scrollable ancestor one page towards an off-screen element. An element with no
    /// bounds (e.g. a list footer that has never been laid out in view) gives no direction, so the ancestor is swept
    /// down to its end and then back up.
    /// </summary>
    /// <param name="element">Element to bring closer to its viewport.</param>
    /// <param name="sweepDown">Sweep direction for an element without bounds.</param>
    /// <returns>The sweep direction for the next call.</returns>
    private bool PageTowards(AutomationElement element, bool sweepDown)
    {
        var walker = automation.TreeWalkerFactory.GetControlViewWalker();
        for (var parent = walker.GetParent(element); parent is not null; parent = walker.GetParent(parent))
        {
            if (!parent.Patterns.Scroll.IsSupported || !parent.Patterns.Scroll.Pattern.VerticallyScrollable.ValueOrDefault) continue;
            var target = element.BoundingRectangle;
            var viewport = parent.BoundingRectangle;
            var scroll = parent.Patterns.Scroll.Pattern;
            bool down;
            if (target.IsEmpty)
            {
                var percent = scroll.VerticalScrollPercent.ValueOrDefault;
                if (sweepDown && percent >= 100) sweepDown = false;
                else if (!sweepDown && percent <= 0) sweepDown = true;
                down = sweepDown;
            }
            else down = target.Top >= viewport.Bottom || target.Bottom > viewport.Bottom;
            scroll.Scroll(FlaUI.Core.Definitions.ScrollAmount.NoAmount,
                down ? FlaUI.Core.Definitions.ScrollAmount.LargeIncrement : FlaUI.Core.Definitions.ScrollAmount.LargeDecrement);
            return sweepDown;
        }
        return sweepDown;
    }

    private (ConditionBase Condition, string Label) Condition(JsonObject step, string key = "selector")
    {
        var selector = step[key]!.AsObject();
        var kind = (string)selector["kind"]!;
        var value = (string)selector["value"]!;
        var cf = automation.ConditionFactory;
        ConditionBase condition = kind switch
        {
            "id" or "raw" => cf.ByAutomationId(value),
            "name" => cf.ByName(value),
            "class" => cf.ByClassName(value),
            _ => throw new ArgumentException($"selector {kind} cannot locate an element"),
        };
        if ((string?)selector["class"] is { } className)
            return (new AndCondition(condition, cf.ByClassName(className)), $"{kind}={value}&class={className}");
        return (condition, $"{kind}={value}");
    }

    /// <summary>Whether a step's selector searches the raw view (<c>raw=</c>) instead of the control view.</summary>
    private static bool IsRaw(JsonObject step, string key = "selector") => (string?)step[key]?["kind"] == "raw";

    /// <summary>
    /// Runs a descendant search in the control view or, for a <c>raw=</c> selector, the raw view: parts a control marks
    /// <c>AccessibilityView=Raw</c> (e.g. a score row's badge text, so Narrator reads the row once) are not control
    /// elements, and UIA's default search filter skips them.
    /// </summary>
    /// <typeparam name="T">Search result.</typeparam>
    /// <param name="raw">Search the raw view.</param>
    /// <param name="search">The search, run while the raw-view cache request is active.</param>
    /// <returns>The search result.</returns>
    private T InView<T>(bool raw, Func<T> search)
    {
        if (!raw) return search();
        var request = new FlaUI.Core.CacheRequest
        {
            TreeFilter = TrueCondition.Default,
            TreeScope = FlaUI.Core.Definitions.TreeScope.Element,
            AutomationElementMode = FlaUI.Core.Definitions.AutomationElementMode.Full,
        };
        request.Add(automation.PropertyLibrary.Element.AutomationId);
        using (request.Activate()) return search();
    }

    internal AutomationElement Find(Window window, JsonObject step, string key = "selector", bool onScreen = true)
    {
        var (condition, label) = Condition(step, key);
        var raw = IsRaw(step, key);
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (true)
        {
            var found = InView(raw, () => window.FindFirstDescendant(condition));
            if (found is not null && (!onScreen || !found.Properties.IsOffscreen.ValueOrDefault)) return found;
            if (DateTime.UtcNow > until) throw new InvalidOperationException($"no on-screen element {label}");
            Thread.Sleep(200);
        }
    }

    /// <summary>
    /// Waits until the step's element is on screen with exactly the step's UIA Name; each <c>*</c> in the text matches
    /// any run of characters (e.g. a chart name whose visible page depends on the text size).
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a selector, the expected <c>text</c> and an optional timeout (default 5 s).</param>
    /// <exception cref="InvalidOperationException">The name still differs at the timeout.</exception>
    private void AssertName(Window window, JsonObject step)
    {
        var expected = (string?)step["text"] ?? "";
        // Each '*' matches any run of characters; a leading '*' covers names that start with a local-time date.
        var pattern = expected.Contains('*')
            ? new System.Text.RegularExpressions.Regex("^" + System.Text.RegularExpressions.Regex.Escape(expected).Replace(@"\*", ".*", StringComparison.Ordinal) + "$", System.Text.RegularExpressions.RegexOptions.Singleline)
            : null;
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (true)
        {
            var actual = Find(window, step).Properties.Name.ValueOrDefault ?? "";
            if (pattern?.IsMatch(actual) ?? actual == expected) return;
            if (DateTime.UtcNow > until)
                throw new InvalidOperationException($"element {(string)step["arg"]!} is named {actual!}, expected {expected}");
            Thread.Sleep(200);
        }
    }

    /// <summary>Window-relative rectangles recorded by <c>pin</c> steps in this request, keyed by selector label.</summary>
    private readonly Dictionary<string, System.Drawing.Rectangle> pins = [];

    /// <summary>The element's bounding rectangle relative to the window's top-left corner (physical pixels).</summary>
    private System.Drawing.Rectangle WindowRelative(Window window, JsonObject step)
    {
        var rect = Find(window, step).BoundingRectangle;
        var origin = window.BoundingRectangle;
        return new System.Drawing.Rectangle(rect.Left - origin.Left, rect.Top - origin.Top, rect.Width, rect.Height);
    }

    /// <summary>
    /// <c>pin</c> records an element's window-relative rectangle; <c>assertpinned</c> fails unless the same selector's
    /// element still has that rectangle within 1 px, e.g. a page toolbar that must not move while its list scrolls.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with a <c>selector</c>.</param>
    /// <param name="record">Whether to record (<c>pin</c>) rather than compare.</param>
    /// <exception cref="InvalidOperationException">Nothing was pinned for the selector, or the rectangle moved.</exception>
    private void Pin(Window window, JsonObject step, bool record)
    {
        var label = Condition(step).Label;
        var now = WindowRelative(window, step);
        if (record)
        {
            pins[label] = now;
            return;
        }
        if (!pins.TryGetValue(label, out var then))
            throw new InvalidOperationException($"assertpinned {label}: no earlier pin step for this selector");
        var moved = Math.Max(Math.Max(Math.Abs(now.Left - then.Left), Math.Abs(now.Top - then.Top)),
            Math.Max(Math.Abs(now.Width - then.Width), Math.Abs(now.Height - then.Height)));
        if (moved > 1)
            throw new InvalidOperationException($"{label} moved: pinned {then} now {now} (window-relative px)");
        response["pinned"] ??= new JsonArray();
        response["pinned"]!.AsArray().Add(new JsonObject
        {
            ["selector"] = label, ["left"] = now.Left, ["top"] = now.Top, ["width"] = now.Width, ["height"] = now.Height,
        });
    }

    /// <summary>Fails unless two on-screen elements share a horizontal centre (a vertically aligned column) within 2 px.</summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with <c>selector</c> and <c>other</c> selectors.</param>
    /// <exception cref="InvalidOperationException">The centres differ by more than 2 px.</exception>
    private void AssertAligned(Window window, JsonObject step)
    {
        var first = Find(window, step).BoundingRectangle;
        var second = Find(window, step, "other").BoundingRectangle;
        var a = first.Left + first.Width / 2.0;
        var b = second.Left + second.Width / 2.0;
        if (Math.Abs(a - b) > 2)
            throw new InvalidOperationException($"centres differ: {a:0.#} vs {b:0.#} px ({(string)step["arg"]!})");
        response["aligned"] ??= new JsonArray();
        response["aligned"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["centre"] = a, ["other"] = b });
    }

    /// <summary>
    /// Fails if a scroller can render a scroll bar or indicator. A WinUI <c>ScrollViewer</c> draws its bars, and the
    /// conscious panning indicator they collapse to, only through its template's <c>ScrollBar</c> parts. With
    /// <c>ScrollBarVisibility.Auto</c> and overflowing content those parts are in the UIA tree (off screen while idle or
    /// after input-free UIA scrolling, drawn as soon as mouse, pen or touch input scrolls); with <c>Hidden</c> they are
    /// collapsed out of it. So any <c>ScrollBar</c> inside the scroller fails, which also holds on a locked console where
    /// no pointer input can bring an Auto indicator up.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with the scroller's selector.</param>
    /// <exception cref="InvalidOperationException">The scroller contains a scroll bar.</exception>
    private void AssertNoScrollBar(Window window, JsonObject step)
    {
        var scroller = Find(window, step);
        var bars = scroller.FindAllDescendants(cf => cf.ByControlType(FlaUI.Core.Definitions.ControlType.ScrollBar))
            .Select(bar => $"{bar.Properties.AutomationId.ValueOrDefault} {bar.BoundingRectangle}"
                           + (bar.Properties.IsOffscreen.ValueOrDefault ? " (idle)" : " (shown)"))
            .ToArray();
        if (bars.Length > 0)
            throw new InvalidOperationException($"scroll bar in {(string)step["arg"]!}: {string.Join("; ", bars)}");
    }

    /// <summary>
    /// Compares two elements' vertical centres: <c>assertbelow</c> needs the first at least 8 px lower (e.g. a chip wrapped
    /// under its row's text), <c>assertlevel</c> needs them within 4 px (e.g. a chip inline on its row's centre line).
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with <c>selector</c> and <c>other</c> selectors.</param>
    /// <param name="below">Whether the first must be lower (else level).</param>
    /// <exception cref="InvalidOperationException">The relation does not hold.</exception>
    private void AssertVertical(Window window, JsonObject step, bool below)
    {
        var first = Find(window, step).BoundingRectangle;
        var second = Find(window, step, "other").BoundingRectangle;
        var a = first.Top + first.Height / 2.0;
        var b = second.Top + second.Height / 2.0;
        if (below ? a - b < 8 : Math.Abs(a - b) > 4)
            throw new InvalidOperationException($"vertical centres {a:0.#} vs {b:0.#} px are not {(below ? "below" : "level")} ({(string)step["arg"]!})");
        response["vertical"] ??= new JsonArray();
        response["vertical"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["centre"] = a, ["other"] = b });
    }

    /// <summary>
    /// Fails unless the vertical gap from the first element's bottom edge to the second's top edge is
    /// <c>epx</c> effective pixels (window DPI), within 1 epx: list-end and footer spacing checks.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with <c>selector</c>, <c>other</c> and <c>epx</c>.</param>
    private void AssertGap(Window window, JsonObject step)
    {
        var first = Find(window, step).BoundingRectangle;
        var second = Find(window, step, "other").BoundingRectangle;
        var scale = Native.GetDpiForWindow(window.Properties.NativeWindowHandle.Value) / 96.0;
        var gap = (second.Top - first.Bottom) / scale;
        var expected = (double)step["epx"]!;
        if (Math.Abs(gap - expected) > 1)
            throw new InvalidOperationException($"vertical gap {gap:0.#} epx is not {expected:0.#} epx ({(string)step["arg"]!})");
        response["gaps"] ??= new JsonArray();
        response["gaps"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["epx"] = Math.Round(gap, 1) });
    }

    /// <summary>
    /// Waits (up to 3 s, for a settling jump) until the first element's top edge is <c>epx</c> effective pixels (window
    /// DPI) below the second's top edge, within 1 epx: e.g. a Quick Links section landed on its scroller's landing line.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with <c>selector</c>, <c>other</c> (the container) and <c>epx</c>.</param>
    /// <exception cref="InvalidOperationException">The inset still differs at the timeout.</exception>
    private void AssertInset(Window window, JsonObject step)
    {
        var scale = Native.GetDpiForWindow(window.Properties.NativeWindowHandle.Value) / 96.0;
        var expected = (double)step["epx"]!;
        var until = DateTime.UtcNow + TimeSpan.FromSeconds(3);
        while (true)
        {
            var inset = (Find(window, step).BoundingRectangle.Top - Find(window, step, "other").BoundingRectangle.Top) / scale;
            if (Math.Abs(inset - expected) <= 1)
            {
                response["insets"] ??= new JsonArray();
                response["insets"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["epx"] = Math.Round(inset, 1) });
                return;
            }
            if (DateTime.UtcNow > until)
                throw new InvalidOperationException($"top inset {inset:0.#} epx is not {expected:0.#} epx ({(string)step["arg"]!})");
            Thread.Sleep(200);
        }
    }

    /// <summary>
    /// Records (<c>markspan</c>) or checks (<c>assertspan</c>) the distance from the first element's top edge to the
    /// second's in effective pixels (window DPI): e.g. a card that must keep its height while its content swaps.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with <c>selector</c>, <c>other</c> and <c>name</c>.</param>
    /// <param name="check">Assert against the recorded span instead of recording it.</param>
    /// <exception cref="InvalidOperationException">No span was recorded under the name, or it changed by more than 1 epx.</exception>
    private void Span(Window window, JsonObject step, bool check)
    {
        var scale = Native.GetDpiForWindow(window.Properties.NativeWindowHandle.Value) / 96.0;
        var name = (string)step["name"]!;
        // A mid-swap check must land within the app's fade (~400 ms): reread the marked elements instead of searching
        // the tree twice, and search again only when they no longer exist or are off screen.
        double? cached = null;
        if (check && spanElements.TryGetValue(name, out var marks))
        {
            try
            {
                if (!marks.Top.Properties.IsOffscreen.ValueOrDefault && !marks.Other.Properties.IsOffscreen.ValueOrDefault)
                    cached = marks.Other.BoundingRectangle.Top - marks.Top.BoundingRectangle.Top;
            }
            catch (Exception error) when (error is FlaUI.Core.Exceptions.ElementNotAvailableException or COMException)
            {
            }
        }
        double span;
        if (cached is { } fast) span = fast / scale;
        else
        {
            var top = Find(window, step);
            var other = Find(window, step, "other");
            span = (other.BoundingRectangle.Top - top.BoundingRectangle.Top) / scale;
            if (!check) spanElements[name] = (top, other);
        }
        response["spans"] ??= new JsonArray();
        response["spans"]!.AsArray().Add(new JsonObject { ["name"] = name, ["check"] = check, ["epx"] = Math.Round(span, 1) });
        if (!check)
        {
            spans[name] = span;
            return;
        }
        if (!spans.TryGetValue(name, out var marked))
            throw new InvalidOperationException($"assertspan {name}: no markspan recorded it");
        if (Math.Abs(span - marked) > 1)
            throw new InvalidOperationException($"span {name} is {span:0.#} epx, not the marked {marked:0.#} epx ({(string)step["arg"]!})");
    }

    /// <summary>
    /// Scrolls a scroller (UIA Scroll pattern, no input) until the target's top edge is <c>epx</c> effective pixels below
    /// the scroller's top edge, within 1 epx: a fixed list position for scans, whatever the window size or scale. UIA
    /// clips a partly scrolled-out element's rectangle to the viewport, so a target whose top reads as the viewport's top
    /// is first scrolled half a viewport back; the remaining offset is then converted to a scroll percent from the
    /// pattern's view size (re-measured each pass, as a virtualized list's extent estimate changes).
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with <c>selector</c> (the target), <c>other</c> (its vertical scroller) and <c>epx</c> (&gt; 0).</param>
    /// <exception cref="InvalidOperationException">No Scroll pattern, or the inset is out of the scroller's range.</exception>
    private void ScrollInset(Window window, JsonObject step)
    {
        var scale = Native.GetDpiForWindow(window.Properties.NativeWindowHandle.Value) / 96.0;
        var expected = (double)step["epx"]!;
        var scroller = Find(window, step, "other");
        if (!scroller.Patterns.Scroll.IsSupported) throw new InvalidOperationException("scrollinset scroller has no Scroll pattern");
        var scroll = scroller.Patterns.Scroll.Pattern;
        Find(window, step); // the target must start on screen (e.g. after scrollinto), so an empty rectangle means "above"
        var inset = double.NaN;
        for (var pass = 0; pass < 12; pass++)
        {
            var viewport = scroller.BoundingRectangle;
            var target = Find(window, step, onScreen: false).BoundingRectangle;
            var percent = scroll.VerticalScrollPercent.ValueOrDefault;
            var viewSize = scroll.VerticalViewSize.ValueOrDefault;
            var scrollable = viewSize is > 0 and < 100 ? viewport.Height * 100 / viewSize - viewport.Height : 0;
            if (scrollable <= 0) throw new InvalidOperationException($"scrollinset scroller cannot scroll ({(string)step["arg"]!})");
            inset = (target.Top - viewport.Top) / scale;
            if (!target.IsEmpty && target.Top > viewport.Top && Math.Abs(inset - expected) <= 1)
            {
                response["insets"] ??= new JsonArray();
                response["insets"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["epx"] = Math.Round(inset, 1) });
                return;
            }
            // A clipped (or unlaid) top gives no real offset: step back half a viewport so the top comes into view.
            var deltaPx = target.IsEmpty || target.Top <= viewport.Top ? -viewport.Height / 2 : target.Top - viewport.Top - expected * scale;
            var next = Math.Clamp(percent + deltaPx / scrollable * 100, 0, 100);
            if (Math.Abs(next - percent) < 1e-6)
                throw new InvalidOperationException($"scrollinset cannot reach a {expected:0.#} epx inset (now {inset:0.#} epx, scroll {percent:0.##}%) ({(string)step["arg"]!})");
            scroll.SetScrollPercent(-1, next);
            Thread.Sleep(300);
        }
        throw new InvalidOperationException($"scrollinset did not settle: inset {inset:0.#} epx, expected {expected:0.#} epx ({(string)step["arg"]!})");
    }

    #endregion

    #region Close

    private JsonNode Close(JsonObject request)
    {
        var window = FindWindow(request);
        var pid = window.Properties.ProcessId.Value;
        using var process = Process.GetProcessById(pid);
        // Open the handle while the app runs: Process.ExitCode refuses processes this driver did not start.
        var handle = process.SafeHandle;
        window.Close();
        var killed = !process.WaitForExit(5000);
        if (killed)
        {
            process.Kill(entireProcessTree: true);
            process.WaitForExit(5000);
        }
        // A fail-fast during shutdown (e.g. 0xc000027b) is a crash, not a clean close (issue #247).
        long? exitCode = process.HasExited && Native.GetExitCodeProcess(handle, out var code) ? (int)code : null;
        return new JsonObject { ["pid"] = pid, ["closed"] = true, ["killed"] = killed, ["exitCode"] = exitCode };
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

    [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(Microsoft.Win32.SafeHandles.SafeProcessHandle process, out uint code);
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
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr FindWindowW(string className, string? windowName);
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

    /// <summary>
    /// Deactivates a window without covering it: the taskbar (topmost, outside the work area) becomes the foreground
    /// window, with the same input-attach workaround as <see cref="BringToForeground"/>.
    /// </summary>
    /// <param name="hwnd">Window to deactivate.</param>
    /// <param name="timeout">How long to retry.</param>
    /// <returns><see langword="true"/> when the taskbar is the foreground window within <paramref name="timeout"/>.</returns>
    public static bool Deactivate(IntPtr hwnd, TimeSpan timeout)
    {
        var taskbar = FindWindowW("Shell_TrayWnd", null);
        if (taskbar == IntPtr.Zero) return false;
        var until = DateTime.UtcNow + timeout;
        for (var attempt = 0; DateTime.UtcNow < until; attempt++)
        {
            if (GetForegroundWindow() == taskbar) return true;
            if (attempt > 0) SendInput(1, [new INPUT { type = 0, mi = new MOUSEINPUT { dwFlags = 0x0001 } }], Marshal.SizeOf<INPUT>());
            var current = GetForegroundWindow();
            var foregroundThread = current == IntPtr.Zero ? 0 : GetWindowThreadProcessId(current, out _);
            var me = GetCurrentThreadId();
            var attached = foregroundThread != 0 && foregroundThread != me && AttachThreadInput(me, foregroundThread, true);
            try
            {
                SetForegroundWindow(taskbar);
            }
            finally
            {
                if (attached) AttachThreadInput(me, foregroundThread, false);
            }
            for (var i = 0; i < 10 && GetForegroundWindow() != taskbar; i++) Thread.Sleep(50);
        }
        return GetForegroundWindow() == taskbar && GetForegroundWindow() != hwnd;
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
