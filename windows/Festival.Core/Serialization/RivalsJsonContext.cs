using System.Text.Json.Serialization;

namespace Festival.Core.Data;
// Declaration-only: its own context because the source generator rejects [JsonSerializable] spread over partials.

#region Source-generated JSON
/// <summary>Reflection-free metadata for the Rivals wire models.</summary>
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = false, UseStringEnumConverter = true)]
[JsonSerializable(typeof(RivalsListResponse))]
[JsonSerializable(typeof(LeaderboardRivalsListResponse))]
[JsonSerializable(typeof(RivalDetailResponse))]
[JsonSerializable(typeof(RivalsAllResponse))]
internal sealed partial class RivalsJsonContext : JsonSerializerContext;
#endregion
