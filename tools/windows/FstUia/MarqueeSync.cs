// Lockstep marquee check for the device-lab driver (`assertmarqueesync:`): two scrolling text lines that the app syncs
// (a song header's title and artist, pattern song-header R2, web useMarqueeSync) must move the same number of pixels
// between any two captures. Both lines are cropped from one PrintWindow capture, so they are sampled at the same instant.

using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text.Json.Nodes;
using FlaUI.Core.AutomationElements;

namespace FstUia;

internal sealed partial class Driver
{
    #region Marquee sync

    /// <summary>
    /// <c>assertmarqueesync</c>: captures the window about every 150 ms for up to 9 s, crops both elements from each
    /// capture and estimates how far each line's pixels moved left since the previous capture (<see cref="LeftShift"/>).
    /// Fails unless at least four capture pairs show both lines moving (≥ 3 px) and in every pair where either line
    /// moved the two shifts agree within 2 px or 8%. Lines with different scroll distances move at different speeds
    /// (distance / 7.2 s), so their shifts differ by their width ratio; synced lines move by the same amount.
    /// </summary>
    /// <param name="window">App window.</param>
    /// <param name="step">Step with <c>selector</c> and <c>other</c> (the two marquee lines).</param>
    /// <exception cref="InvalidOperationException">Too few moving pairs, or the lines moved by different amounts.</exception>
    private void AssertMarqueeSync(Window window, JsonObject step)
    {
        var label = (string)step["arg"]!;
        var hwnd = window.Properties.NativeWindowHandle.Value;
        var a = Find(window, step).BoundingRectangle;
        var b = Find(window, step, "other").BoundingRectangle;
        var union = Rectangle.Union(a, b);
        var cropA = new Rectangle(a.X - union.X, a.Y - union.Y, a.Width, a.Height);
        var cropB = new Rectangle(b.X - union.X, b.Y - union.Y, b.Width, b.Height);
        (float[,] A, float[,] B)? previous = null;
        var moving = new JsonArray();
        var mismatches = new List<string>();
        var clock = Stopwatch.StartNew();
        while (clock.Elapsed < TimeSpan.FromSeconds(9) && moving.Count < 8)
        {
            (float[,] A, float[,] B) frame;
            using (var capture = Native.PrintWindow(hwnd, union))
                frame = (Luminance(capture, cropA), Luminance(capture, cropB));
            if (previous is { } last)
            {
                int sa = LeftShift(last.A, frame.A), sb = LeftShift(last.B, frame.B);
                // A synced shorter line has a long gap after its text: while the gap fills its column there is nothing to track.
                var readable = Inked(last.A) && Inked(frame.A) && Inked(last.B) && Inked(frame.B);
                if (readable && sa >= 3 && sb >= 3) moving.Add(new JsonArray(sa, sb));
                if (readable && (sa >= 3 || sb >= 3) && Math.Abs(sa - sb) > Math.Max(2, 0.08 * Math.Max(sa, sb)))
                    mismatches.Add($"{sa} vs {sb} px");
            }
            previous = frame;
            Thread.Sleep(150);
        }
        if (mismatches.Count > 0)
            throw new InvalidOperationException($"{label} lines moved by different amounts between captures: {string.Join(", ", mismatches)}");
        if (moving.Count < 4)
            throw new InvalidOperationException($"{label}: only {moving.Count} capture pairs showed both lines moving (need 4)");
        response["marqueesyncs"] ??= new JsonArray();
        response["marqueesyncs"]!.AsArray().Add(new JsonObject { ["arg"] = label, ["shifts"] = moving });
    }

    /// <summary>Luminance (0–255) of a region of a capture, indexed <c>[y, x]</c>.</summary>
    /// <param name="capture">Window capture.</param>
    /// <param name="region">Region within the capture.</param>
    /// <returns>Luminance grid.</returns>
    internal static float[,] Luminance(Bitmap capture, Rectangle region)
    {
        region.Intersect(new Rectangle(0, 0, capture.Width, capture.Height));
        var result = new float[region.Height, region.Width];
        var data = capture.LockBits(region, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            var row = new byte[data.Width * 4];
            for (var y = 0; y < data.Height; y++)
            {
                Marshal.Copy(data.Scan0 + y * data.Stride, row, 0, row.Length);
                for (var x = 0; x < data.Width; x++)
                    result[y, x] = (row[x * 4 + 2] * 299 + row[x * 4 + 1] * 587 + row[x * 4] * 114) / 1000f;
            }
        }
        finally
        {
            capture.UnlockBits(data);
        }
        return result;
    }

    /// <summary>Whether at least 3% of a line capture is ink (luminance more than 40 from its most common value).</summary>
    /// <param name="line">Luminance grid.</param>
    /// <returns>Whether there is enough text to track.</returns>
    internal static bool Inked(float[,] line)
    {
        var histogram = new int[256];
        foreach (var value in line) histogram[Math.Clamp((int)value, 0, 255)]++;
        var background = Array.IndexOf(histogram, histogram.Max());
        var ink = 0;
        foreach (var value in line) if (Math.Abs(value - background) > 40) ink++;
        return line.Length > 0 && ink >= 0.03 * line.Length;
    }

    /// <summary>
    /// How many pixels a line's content moved left between two captures: the shift <c>s</c> (0 to 60% of the width)
    /// that minimizes the mean absolute luminance difference between <c>after[x]</c> and <c>before[x + s]</c> over
    /// their overlap. A marquee only moves left, so a still line gives 0.
    /// </summary>
    /// <param name="before">Earlier capture of the line.</param>
    /// <param name="after">Later capture, the same size.</param>
    /// <returns>Leftward shift in device pixels (0 when the sizes differ).</returns>
    internal static int LeftShift(float[,] before, float[,] after)
    {
        int height = before.GetLength(0), width = before.GetLength(1);
        if (height != after.GetLength(0) || width != after.GetLength(1) || width < 4) return 0;
        var best = 0;
        var bestScore = double.MaxValue;
        for (var s = 0; s <= width * 6 / 10; s++)
        {
            double sum = 0;
            for (var y = 0; y < height; y++)
                for (var x = 0; x < width - s; x++)
                    sum += Math.Abs(after[y, x] - before[y, x + s]);
            var score = sum / (height * (width - s));
            if (score < bestScore - 1e-6)
            {
                bestScore = score;
                best = s;
            }
        }
        return best;
    }

    #endregion
}
