using System.Text.Json.Serialization;

namespace Festival.Core.Data;
// Declaration-only: the source generator emits the code, so this lives outside the coverage-gated Data/ folder.

#region Song detail JSON
/// <summary>Song Detail wire types (a separate context: attributed partials of one context collide).</summary>
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = false, UseStringEnumConverter = true)]
[JsonSerializable(typeof(AllLeaderboardsResponse))]
internal sealed partial class SongDetailJsonContext : JsonSerializerContext;
#endregion
