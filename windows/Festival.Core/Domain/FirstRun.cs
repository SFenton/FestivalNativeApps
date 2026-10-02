using System.Globalization;
using System.Text.Json.Serialization;

namespace Festival.Core.Domain;

#region Gate context
/// <summary>
/// Runtime facts a slide gate may depend on (web <c>FirstRunGateContext</c>, <c>firstRun/types.ts</c>).
/// </summary>
/// <param name="HasPlayer">A player profile is selected.</param>
/// <param name="ShopHighlightEnabled">Item Shop highlighting is active (Shop visible, highlighting on).</param>
/// <param name="ExperimentalRanksEnabled">Experimental leaderboard ranks are on.</param>
/// <param name="Ready">When false nothing shows: dependent facts are still resolving.</param>
/// <param name="AlwaysShow">Bypass seen-state (debug force) while still respecting gates.</param>
public sealed record FirstRunGateContext(
    bool HasPlayer = false,
    bool ShopHighlightEnabled = false,
    bool ExperimentalRanksEnabled = false,
    bool Ready = true,
    bool AlwaysShow = false);

/// <summary>A named slide gate (an enum rather than a delegate so slides stay comparable data).</summary>
public enum FirstRunGate
{
    /// <summary>Always eligible.</summary>
    Always,
    /// <summary>Only with a selected player.</summary>
    HasPlayer,
    /// <summary>Only while Shop highlighting is active.</summary>
    ShopHighlightEnabled,
    /// <summary>Only while experimental ranks are on.</summary>
    ExperimentalRanksEnabled,
}

/// <summary>Gate evaluation.</summary>
public static class FirstRunGates
{
    /// <summary>Evaluates a gate.</summary>
    /// <param name="gate">Gate.</param>
    /// <param name="context">Runtime facts.</param>
    /// <returns>Whether a slide using the gate may show.</returns>
    public static bool Passes(this FirstRunGate gate, FirstRunGateContext context) => gate switch
    {
        FirstRunGate.HasPlayer => context.HasPlayer,
        FirstRunGate.ShopHighlightEnabled => context.ShopHighlightEnabled,
        FirstRunGate.ExperimentalRanksEnabled => context.ExperimentalRanksEnabled,
        _ => true,
    };
}
#endregion

#region Slide
/// <summary>One slide definition (web <c>FirstRunSlideDef</c> without <c>render</c>; the UI maps <see cref="Id"/> to a demo).</summary>
/// <param name="Id">Stable web slide ID, e.g. <c>songs-song-list</c>.</param>
/// <param name="Version">Replay-contract version; bumped only when dismissed users should see it again.</param>
/// <param name="Title">Title Case title.</param>
/// <param name="Description">Sentence-case description.</param>
/// <param name="ContentKey">Overrides the hashed text so copy variants share one seen record.</param>
/// <param name="Gate">Eligibility predicate.</param>
public sealed record FirstRunSlide(
    string Id, int Version, string Title, string Description, string? ContentKey = null, FirstRunGate Gate = FirstRunGate.Always)
{
    /// <summary>Text hashed to detect copy changes: <c>contentKey ?? title + description</c>.</summary>
    public string HashedContent => ContentKey ?? Title + Description;

    /// <summary>
    /// The slide's title. XAML names each <c>FlipViewItem</c> from its item's <c>ToString()</c>, so this is what
    /// Narrator reads for the focused slide when a guide opens (issue #24); the record default would read every field.
    /// </summary>
    /// <returns><see cref="Title"/>.</returns>
    public override string ToString() => Title;
}
#endregion

#region Hashing and records
/// <summary>The web's djb2 <c>contentHash</c>, bit for bit.</summary>
public static class FirstRunHashing
{
    /// <summary>
    /// Hashes UTF-16 code units exactly like JavaScript's <c>charCodeAt</c> loop with 32-bit wraparound,
    /// returned as unsigned lowercase hex.
    /// </summary>
    /// <param name="text">Slide content.</param>
    /// <returns>Lowercase hex digest.</returns>
    public static string ContentHash(string text)
    {
        var hash = 5381u;
        foreach (var unit in text)
        {
            unchecked { hash = (hash << 5) + hash + unit; }
        }
        return hash.ToString("x", CultureInfo.InvariantCulture);
    }
}

/// <summary>Evidence that a slide was shown (web <c>FirstRunSeenRecord</c>).</summary>
/// <param name="Version">Slide version when shown.</param>
/// <param name="Hash">Content hash when shown.</param>
/// <param name="SeenAt">When it was marked seen.</param>
public sealed record FirstRunSeenRecord(
    [property: JsonPropertyName("version")] int Version,
    [property: JsonPropertyName("hash")] string Hash,
    [property: JsonPropertyName("seenAt")] DateTimeOffset SeenAt)
{
    /// <summary>Whether the record has a shape <see cref="FirstRunSlideEvaluator.SeenRecord"/> could have written.</summary>
    [JsonIgnore]
    public bool IsValid => Version >= 0 && Hash is { Length: > 0 and <= 32 };
}
#endregion

#region Evaluator
/// <summary>Pure unseen/eligibility rules (web <c>isSlideUnseen</c>, <c>getUnseenSlides</c>, <c>getAllSlides</c>).</summary>
public static class FirstRunSlideEvaluator
{
    /// <summary>Unseen: no record, a strictly higher slide version, or changed content.</summary>
    /// <param name="slide">Slide.</param>
    /// <param name="seen">Seen-state.</param>
    /// <returns><see langword="true"/> when the slide should show.</returns>
    public static bool IsUnseen(FirstRunSlide slide, IReadOnlyDictionary<string, FirstRunSeenRecord> seen)
    {
        if (!seen.TryGetValue(slide.Id, out var record)) return true;
        if (slide.Version > record.Version) return true;
        return FirstRunHashing.ContentHash(slide.HashedContent) != record.Hash;
    }

    /// <summary>Gate-passing unseen slides in catalogue order (all gate-passing ones under <c>AlwaysShow</c>); none until ready.</summary>
    /// <param name="slides">A page's catalogue.</param>
    /// <param name="context">Runtime facts.</param>
    /// <param name="seen">Seen-state.</param>
    /// <returns>Slides to show.</returns>
    public static IReadOnlyList<FirstRunSlide> UnseenSlides(
        IEnumerable<FirstRunSlide> slides, FirstRunGateContext context, IReadOnlyDictionary<string, FirstRunSeenRecord> seen)
    {
        if (!context.Ready) return [];
        var passing = GatePassingSlides(slides, context);
        return context.AlwaysShow ? passing : [.. passing.Where(s => IsUnseen(s, seen))];
    }

    /// <summary>Every slide whose gate passes, ignoring seen-state.</summary>
    /// <param name="slides">A page's catalogue.</param>
    /// <param name="context">Runtime facts.</param>
    /// <returns>Gate-passing slides.</returns>
    public static IReadOnlyList<FirstRunSlide> GatePassingSlides(IEnumerable<FirstRunSlide> slides, FirstRunGateContext context) =>
        [.. slides.Where(s => s.Gate.Passes(context))];

    /// <summary>Every slide, ignoring gates and seen-state (Settings replay, web <c>getAllSlides</c>).</summary>
    /// <param name="slides">A page's catalogue.</param>
    /// <returns>The same slides.</returns>
    public static IReadOnlyList<FirstRunSlide> AllSlides(IEnumerable<FirstRunSlide> slides) => [.. slides];

    /// <summary>The record to persist once a slide was shown.</summary>
    /// <param name="slide">Slide.</param>
    /// <param name="now">Timestamp.</param>
    /// <returns>Record with the current version and hash.</returns>
    public static FirstRunSeenRecord SeenRecord(FirstRunSlide slide, DateTimeOffset now) =>
        new(slide.Version, FirstRunHashing.ContentHash(slide.HashedContent), now);
}
#endregion

#region Debug mode
/// <summary>First-run behaviour for this launch.</summary>
public enum FirstRunMode
{
    /// <summary>Real seen-state behaviour (Release default, <c>on</c>).</summary>
    Normal,
    /// <summary>Never show automatically (Debug default so automation is not blocked; replay still works).</summary>
    Off,
    /// <summary>Show every gate-passing slide on every page visit (<c>force</c>).</summary>
    Force,
}

/// <summary>Parses <c>--first-run off|on|force</c> or Debug <c>FST_DEBUG_FIRST_RUN</c>.</summary>
public static class FirstRunModeParser
{
    /// <summary>Resolves the mode; the flag wins over the environment.</summary>
    /// <param name="args">Command-line arguments.</param>
    /// <param name="environment">Environment lookup (Debug builds only; Release passes a null lookup).</param>
    /// <param name="debugBuild">Whether this is a Debug build (unset means <see cref="FirstRunMode.Off"/>).</param>
    /// <returns>Mode.</returns>
    public static FirstRunMode Parse(IReadOnlyList<string> args, Func<string, string?> environment, bool debugBuild)
    {
        string? value = null;
        for (var i = 0; i < args.Count; i++)
        {
            if (args[i].StartsWith("--first-run=", StringComparison.OrdinalIgnoreCase)) value = args[i]["--first-run=".Length..];
            else if (string.Equals(args[i], "--first-run", StringComparison.OrdinalIgnoreCase) && i + 1 < args.Count) value = args[++i];
        }
        value ??= environment("FST_DEBUG_FIRST_RUN");
        return value?.Trim().ToLowerInvariant() switch
        {
            "force" => FirstRunMode.Force,
            "on" => FirstRunMode.Normal,
            "off" => FirstRunMode.Off,
            _ => debugBuild ? FirstRunMode.Off : FirstRunMode.Normal,
        };
    }
}
#endregion
