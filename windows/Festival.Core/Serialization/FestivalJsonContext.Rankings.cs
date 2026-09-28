using System.Text.Json.Serialization;

namespace Festival.Core.Data;

#region Rankings JSON
/// <summary>
/// Source-generated metadata for the rankings boards. A separate context rather than another partial of
/// <see cref="FestivalJsonContext"/>: the System.Text.Json generator treats each attributed partial declaration
/// as its own context and fails with duplicate hint names (CS8785).
/// </summary>
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = false, UseStringEnumConverter = true)]
[JsonSerializable(typeof(RankingsResponse))]
[JsonSerializable(typeof(BandRankingsResponse))]
internal sealed partial class RankingsJsonContext : JsonSerializerContext;
#endregion
