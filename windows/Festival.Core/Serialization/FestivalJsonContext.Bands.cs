using System.Text.Json.Serialization;

namespace Festival.Core.Data;
// Declaration-only: a separate source-generated context per feature (one generator run per context class).

#region Band wire types
/// <summary>Reflection-free metadata for the Bands lane's wire types.</summary>
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = false, UseStringEnumConverter = true)]
[JsonSerializable(typeof(PlayerBandListResponse))]
[JsonSerializable(typeof(BandProfileEnvelope))]
[JsonSerializable(typeof(BandRankHistoryResponse))]
[JsonSerializable(typeof(BandSongExtremesResponse))]
[JsonSerializable(typeof(SongBandLeaderboardResponse))]
[JsonSerializable(typeof(SongBandLeaderboardsResponse))]
internal sealed partial class BandsJsonContext : JsonSerializerContext;
#endregion
