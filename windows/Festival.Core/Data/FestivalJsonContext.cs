using System.Text.Json.Serialization;

namespace Festival.Core.Data;

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
