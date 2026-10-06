// Visual assertions for the device-lab driver: pixel probes inside an element's bounds (`assertpaint:`) and the
// bold runs of a text element (`assertbold:`). They pin decorative parts that UI Automation cannot see (a control marks
// them AccessibilityView=Raw so Narrator reads the row once), e.g. a notification row's card, dot, flag pill and grid.

using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;

namespace FstUia;

internal sealed partial class Driver
{
    #region Paint probes

    /// <summary>
    /// <c>assertpaint</c>: captures the window (<c>PrintWindow</c>, so flyouts and occluded windows count) and checks
    /// each probe against the pixels at an effective-pixel offset (window DPI) from the element's edges. A point probe
    /// matches when every channel is within its tolerance of the expected colour (<c>=</c>) or not (<c>!=</c>); an area
    /// probe matches when at least 4 epx² of its pixels do (<c>=</c>) or fewer do (<c>!=</c>). The expected colour is
    /// <c>#RRGGBB</c> or <c>@name</c>, the colour an earlier named point probe sampled in the same step (theme-relative
    /// checks, e.g. a contrast theme's stroke against its own card fill). Retries for up to 3 s (a fade-in settling).
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with <c>selector</c> and <c>probes</c> (see <c>uiwin.parse_probe</c>).</param>
    /// <exception cref="InvalidOperationException">A probe still fails at the timeout, or lies outside the window.</exception>
    private void AssertPaint(Window window, JsonObject step)
    {
        var hwnd = window.Properties.NativeWindowHandle.Value;
        var scale = Native.GetDpiForWindow(hwnd) / 96.0;
        var probes = step["probes"]!.AsArray().Select(p => p!.AsObject()).ToList();
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 3);
        while (true)
        {
            var element = Find(window, step).BoundingRectangle;
            var visible = Native.VisibleBounds(hwnd);
            using var bitmap = Native.PrintWindow(hwnd, visible);
            var pixels = Pixels.From(bitmap);
            var bounds = new RectangleF(element.Left - visible.Left, element.Top - visible.Top, element.Width, element.Height);
            var (failures, samples) = CheckProbes(pixels, bounds, scale, probes);
            if (failures.Count == 0)
            {
                response["paint"] ??= new JsonArray();
                response["paint"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["samples"] = samples });
                return;
            }
            if (DateTime.UtcNow > until)
                throw new InvalidOperationException($"paint probes failed ({(string)step["arg"]!}): {string.Join("; ", failures)}");
            Thread.Sleep(250);
        }
    }

    /// <summary>Checks every probe against one capture.</summary>
    /// <param name="pixels">Window capture.</param>
    /// <param name="bounds">Element bounds in capture pixels.</param>
    /// <param name="scale">Window DPI scale (pixels per epx).</param>
    /// <param name="probes">Parsed probes, in order (a <c>@name</c> refers to an earlier one).</param>
    /// <returns>Failure messages (empty when all match) and the sampled colours per probe.</returns>
    internal static (List<string> Failures, JsonArray Samples) CheckProbes(Pixels pixels, RectangleF bounds, double scale,
        IReadOnlyList<JsonObject> probes)
    {
        var named = new Dictionary<string, int>();
        var failures = new List<string>();
        var samples = new JsonArray();
        var minimum = Math.Max(1, (int)Math.Ceiling(4 * scale * scale));
        foreach (var probe in probes)
        {
            var text = (string)probe["text"]!;
            var x = Edge(probe["x"]!.AsObject(), bounds.Left, bounds.Right, scale);
            var y = Edge(probe["y"]!.AsObject(), bounds.Top, bounds.Bottom, scale);
            var op = (string?)probe["op"];
            var tolerance = (int?)probe["tol"] ?? 16;
            int? expected = (string?)probe["ref"] is { } reference
                ? named.TryGetValue(reference, out var colour) ? colour : throw new ArgumentException($"probe {text}: no earlier probe named {reference}")
                : (string?)probe["color"] is { } hex ? Convert.ToInt32(hex[1..], 16) : null;
            if (probe["x2"] is null)
            {
                if (!pixels.Contains(x, y))
                {
                    failures.Add($"{text}: ({x},{y}) is outside the capture");
                    continue;
                }
                var sampled = pixels[x, y];
                samples.Add(new JsonObject { ["probe"] = text, ["at"] = new JsonArray(x, y), ["color"] = Hex(sampled) });
                if ((string?)probe["name"] is { } name) named[name] = sampled;
                if (op is null || expected is null) continue;
                var near = Near(sampled, expected.Value, tolerance);
                if (near != (op == "="))
                    failures.Add($"{text}: sampled {Hex(sampled)} at ({x},{y})");
            }
            else
            {
                var x2 = Edge(probe["x2"]!.AsObject(), bounds.Left, bounds.Right, scale);
                var y2 = Edge(probe["y2"]!.AsObject(), bounds.Top, bounds.Bottom, scale);
                var area = Rectangle.FromLTRB(Math.Min(x, x2), Math.Min(y, y2), Math.Max(x, x2) + 1, Math.Max(y, y2) + 1);
                if (!pixels.Contains(area.Left, area.Top) || !pixels.Contains(area.Right - 1, area.Bottom - 1))
                {
                    failures.Add($"{text}: area {area} is outside the capture");
                    continue;
                }
                var count = 0;
                var centre = pixels[(area.Left + area.Right) / 2, (area.Top + area.Bottom) / 2];
                for (var py = area.Top; py < area.Bottom; py++)
                    for (var px = area.Left; px < area.Right; px++)
                        if (Near(pixels[px, py], expected!.Value, tolerance)) count++;
                samples.Add(new JsonObject { ["probe"] = text, ["area"] = new JsonArray(area.X, area.Y, area.Width, area.Height), ["matches"] = count, ["centre"] = Hex(centre) });
                if ((count >= minimum) != (op == "="))
                    failures.Add($"{text}: {count} px within {tolerance} of {Hex(expected!.Value)} in {area} (need {(op == "=" ? "at least" : "fewer than")} {minimum}; centre {Hex(centre)})");
            }
        }
        return (failures, samples);
    }

    /// <summary>Converts a probe coordinate (an edge and a signed epx offset) to a capture pixel.</summary>
    /// <param name="spec"><c>edge</c> (<c>L</c>/<c>T</c> from the start, <c>R</c>/<c>B</c> inward from the end,
    /// <c>C</c>/<c>M</c> from the centre) and <c>off</c> (epx).</param>
    /// <param name="start">Element start (pixels).</param>
    /// <param name="end">Element end (pixels).</param>
    /// <param name="scale">Pixels per epx.</param>
    /// <returns>The pixel index.</returns>
    internal static int Edge(JsonObject spec, float start, float end, double scale)
    {
        var offset = (double)spec["off"]! * scale;
        var at = (string)spec["edge"]! switch
        {
            "L" or "T" => start + offset,
            "R" or "B" => end - offset,
            _ => (start + end) / 2.0 + offset,
        };
        return (int)Math.Floor(at);
    }

    /// <summary>Whether two RGB colours are within a per-channel tolerance.</summary>
    internal static bool Near(int a, int b, int tolerance) =>
        Math.Abs((a >> 16 & 0xFF) - (b >> 16 & 0xFF)) <= tolerance
        && Math.Abs((a >> 8 & 0xFF) - (b >> 8 & 0xFF)) <= tolerance
        && Math.Abs((a & 0xFF) - (b & 0xFF)) <= tolerance;

    /// <summary>Formats a <c>0xRRGGBB</c> colour as <c>#RRGGBB</c>.</summary>
    private static string Hex(int rgb) => $"#{rgb & 0xFFFFFF:X6}";

    /// <summary>An RGB copy of a capture (alpha dropped), read without per-pixel GDI calls.</summary>
    internal sealed class Pixels(int width, int height, int[] rgb)
    {
        /// <summary>Copies a 32 bpp bitmap.</summary>
        public static Pixels From(Bitmap bitmap)
        {
            var data = bitmap.LockBits(new Rectangle(0, 0, bitmap.Width, bitmap.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                var rgb = new int[bitmap.Width * bitmap.Height];
                for (var row = 0; row < bitmap.Height; row++)
                    Marshal.Copy(data.Scan0 + row * data.Stride, rgb, row * bitmap.Width, bitmap.Width);
                for (var i = 0; i < rgb.Length; i++) rgb[i] &= 0xFFFFFF;
                return new Pixels(bitmap.Width, bitmap.Height, rgb);
            }
            finally
            {
                bitmap.UnlockBits(data);
            }
        }

        /// <summary>Whether a pixel lies inside the capture.</summary>
        public bool Contains(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

        /// <summary>The <c>0xRRGGBB</c> colour at a pixel.</summary>
        public int this[int x, int y] => rgb[y * width + x];
    }

    #endregion

    #region Bold runs

    /// <summary>
    /// <c>assertbold</c>: waits (default 5 s) until the bold runs (UIA TextPattern <c>FontWeight</c> 700, trimmed) of
    /// the element's text are exactly the expected runs, in order. The
    /// element is the selector's target when it offers the Text pattern, else its first control-view descendant that
    /// does (e.g. a list item's message line).
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with <c>selector</c>, <c>runs</c> and an optional timeout.</param>
    /// <exception cref="InvalidOperationException">No Text pattern, or the runs still differ at the timeout.</exception>
    private void AssertBold(Window window, JsonObject step)
    {
        var expected = step["runs"]!.AsArray().Select(r => (string)r!).ToList();
        var until = DateTime.UtcNow + TimeSpan.FromSeconds((double?)step["timeout"] ?? 5);
        while (true)
        {
            var target = Find(window, step);
            var text = target.Patterns.Text.IsSupported
                ? target
                : target.FindAllDescendants().FirstOrDefault(e => e.Patterns.Text.IsSupported)
                  ?? throw new InvalidOperationException($"no Text pattern in {(string)step["arg"]!}");
            var runs = BoldRuns(text);
            if (runs.SequenceEqual(expected))
            {
                response["bold"] ??= new JsonArray();
                response["bold"]!.AsArray().Add(new JsonObject { ["arg"] = (string)step["arg"]!, ["runs"] = new JsonArray(runs.Select(r => (JsonNode)r).ToArray()) });
                return;
            }
            if (DateTime.UtcNow > until)
                throw new InvalidOperationException($"bold runs [{string.Join(" | ", runs)}] are not [{string.Join(" | ", expected)}] ({(string)step["arg"]!})");
            Thread.Sleep(200);
        }
    }

    /// <summary>
    /// The trimmed runs of text whose font weight is 700 (bold). A WinUI TextBlock's TextPattern has no <c>Format</c>
    /// unit and no <c>FindAttribute</c>, and the range after <c>i</c> character units reports the combined weight of
    /// units <c>i-1</c> and <c>i</c> (mixed at a run boundary), so weights are decoded left to right: a uniform value
    /// is the unit's weight and a mixed value flips the previous unit's weight. A <c>LineBreak</c> is one character
    /// unit but two characters of text (<c>\r\n</c>), so each unit is placed at the text length of the range before it
    /// rather than at its unit index; skipped characters (the break's second half) are never bold.
    /// </summary>
    /// <param name="element">Element offering the Text pattern.</param>
    /// <returns>Bold runs in document order, trimmed, empty runs dropped.</returns>
    private List<string> BoldRuns(AutomationElement element)
    {
        var weight = automation.TextAttributeLibrary.FontWeight;
        var document = element.Patterns.Text.Pattern.DocumentRange;
        var text = document.GetText(-1);
        var bold = new bool[text.Length];
        bool? previous = null;
        for (var unit = 0; unit < text.Length; unit++)
        {
            var character = document.Clone();
            character.MoveEndpointByRange(TextPatternRangeEndpoint.End, character, TextPatternRangeEndpoint.Start);
            if (unit > 0 && character.Move(TextUnit.Character, unit) < unit) break;
            var prefix = document.Clone();
            prefix.MoveEndpointByRange(TextPatternRangeEndpoint.End, character, TextPatternRangeEndpoint.Start);
            var index = unit == 0 ? 0 : prefix.GetText(-1).Length;
            if (index >= text.Length) break;
            var on = DecodeWeight(character.GetAttributeValue(weight), previous);
            previous = on;
            bold[index] = on;
        }
        return Runs(text, bold);
    }

    /// <summary>Decodes one TextPattern weight value given the previous character's boldness.</summary>
    /// <param name="value">Attribute value: a weight number when uniform, otherwise the mixed sentinel.</param>
    /// <param name="previous">The previous character's boldness, or <c>null</c> for the first character.</param>
    /// <returns><c>true</c> when the character is bold.</returns>
    internal static bool DecodeWeight(object? value, bool? previous) => value switch
    {
        int w => w >= 700,
        _ => previous is bool p && !p,
    };

    /// <summary>Splits text into trimmed bold runs.</summary>
    /// <param name="text">Document text.</param>
    /// <param name="bold">Per-character boldness.</param>
    /// <returns>Non-empty trimmed runs of consecutive bold characters.</returns>
    internal static List<string> Runs(string text, bool[] bold)
    {
        var runs = new List<string>();
        var start = -1;
        for (var i = 0; i <= text.Length; i++)
        {
            var on = i < text.Length && bold[i];
            if (on && start < 0) start = i;
            if (on || start < 0) continue;
            var run = text[start..i].Trim();
            if (run.Length > 0) runs.Add(run);
            start = -1;
        }
        return runs;
    }
    #endregion
}
