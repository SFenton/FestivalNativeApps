using System.Diagnostics;
using System.Globalization;
using System.Numerics;
using Microsoft.UI;
using Microsoft.UI.Composition;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;

namespace BenchCSharp;

#region Benchmark
/// <summary>
/// C# twin of Bench/Cpp/main.cpp: one WinUI 3 window, a label and a full-window image with a stepped 6 s zoom on
/// the composition thread. Arguments: --static (no animation), --perf-log &lt;path&gt;.
/// </summary>
public static class Program
{
    private static string? log;

    /// <summary>Entry point.</summary>
    /// <param name="args">Arguments.</param>
    [STAThread]
    public static void Main(string[] args)
    {
        var isStatic = args.Contains("--static");
        var index = Array.IndexOf(args, "--perf-log");
        if (index >= 0 && index + 1 < args.Length) log = args[index + 1];
        WinRT.ComWrappersSupport.InitializeComWrappers();
        Application.Start(_ => new BenchApp(isStatic));
    }

    /// <summary>Appends a name=ms marker (ms since the OS recorded process start).</summary>
    /// <param name="name">Marker.</param>
    public static void Mark(string name)
    {
        if (log is null) return;
        var ms = (DateTime.UtcNow - Process.GetCurrentProcess().StartTime.ToUniversalTime()).TotalMilliseconds;
        File.AppendAllText(log, string.Create(CultureInfo.InvariantCulture, $"{name}={ms:F1}\n"));
    }
}

/// <summary>Benchmark application.</summary>
/// <param name="isStatic">Skip the animation.</param>
public sealed partial class BenchApp(bool isStatic) : Application
{
    private Window? window;
    private bool firstFrame;

    /// <inheritdoc />
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        window = new Window();
        var grid = new Grid { Background = new SolidColorBrush(Colors.Black) };
        grid.Children.Add(new TextBlock { Text = "Benchmark (C#)", Margin = new Thickness(24) });
        window.Content = grid;
        grid.Loaded += (_, _) =>
        {
            var compositor = ElementCompositionPreview.GetElementVisual(grid).Compositor;
            var sprite = compositor.CreateSpriteVisual();
            sprite.Size = new Vector2(1400, 900);
            sprite.CenterPoint = new Vector3(700, 450, 0);
            var surface = LoadedImageSurface.StartLoadFromUri(new Uri(Path.Combine(AppContext.BaseDirectory, "bench-art.png")), new Windows.Foundation.Size(1024, 1024));
            var brush = compositor.CreateSurfaceBrush(surface);
            brush.Stretch = CompositionStretch.UniformToFill;
            sprite.Brush = brush;
            ElementCompositionPreview.SetElementChildVisual(grid, sprite);
            if (!isStatic)
            {
                var scale = compositor.CreateVector3KeyFrameAnimation();
                var steps = compositor.CreateStepEasingFunction(180);
                steps.IsFinalStepSingleFrame = false;
                scale.InsertKeyFrame(0, Vector3.One);
                scale.InsertKeyFrame(1, new Vector3(1.18f, 1.18f, 1), steps);
                scale.Duration = TimeSpan.FromSeconds(6);
                scale.IterationBehavior = AnimationIterationBehavior.Forever;
                scale.Direction = AnimationDirection.Alternate;
                sprite.StartAnimation("Scale", scale);
            }
            // Unsubscribe after the first frame: a live Rendering handler makes XAML render every frame.
            CompositionTarget.Rendering += OnRendering;
        };
        window.Activated += (_, _) => Program.Mark("window-activated");
        window.Activate();
    }

    /// <summary>Records the first rendered frame once.</summary>
    /// <param name="sender">Unused.</param>
    /// <param name="e">Unused.</param>
    private void OnRendering(object? sender, object e)
    {
        CompositionTarget.Rendering -= OnRendering;
        if (firstFrame) return;
        firstFrame = true;
        Program.Mark("first-frame");
    }
}
#endregion
