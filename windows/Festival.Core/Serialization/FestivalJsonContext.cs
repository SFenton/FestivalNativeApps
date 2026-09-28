using System.Text.Json.Serialization;

namespace Festival.Core.Data;
// Declaration-only: the source generator emits the code, so this lives outside the coverage-gated Data/ folder.

#region Source-generated JSON
/// <summary>Reflection-free System.Text.Json metadata so the app stays trim- and NativeAOT-safe.</summary>
[JsonSourceGenerationOptions(
    PropertyNameCaseInsensitive = false,
    WriteIndented = true,
    UseStringEnumConverter = true,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(Publication))]
[JsonSerializable(typeof(SongsResponse))]
[JsonSerializable(typeof(LeaderboardResponse))]
[JsonSerializable(typeof(PlayerSearchResponse))]
[JsonSerializable(typeof(ConflictBody))]
[JsonSerializable(typeof(AppSettings))]
internal sealed partial class FestivalJsonContext : JsonSerializerContext;
#endregion
