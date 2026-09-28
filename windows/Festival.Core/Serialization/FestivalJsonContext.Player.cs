using System.Text.Json.Serialization;

namespace Festival.Core.Data;
// Declaration-only: the source generator emits the code, so this lives outside the coverage-gated Data/ folder.

#region Source-generated JSON (player)
/// <summary>
/// Player profile, ranking and history wire types. A separate context, not a partial of
/// <c>FestivalJsonContext</c>: the generator treats every attributed partial declaration as its own context.
/// </summary>
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = false, UseStringEnumConverter = true)]
[JsonSerializable(typeof(PlayerProfileResponse))]
[JsonSerializable(typeof(PlayerInstrumentRanking))]
[JsonSerializable(typeof(PlayerRankHistory))]
[JsonSerializable(typeof(PlayerHistoryResponse))]
internal sealed partial class PlayerJsonContext : JsonSerializerContext;
#endregion
