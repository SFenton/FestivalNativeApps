using System.Text.Json.Serialization;

namespace Festival.Core.Data;
// Declaration-only (source-generated), kept outside the coverage-gated Data/ folder. A separate context per
// feature: a second [JsonSerializable] partial of FestivalJsonContext makes the generator emit duplicate files.

#region Source-generated JSON
/// <summary>First-run seen-state metadata.</summary>
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = false, DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(Dictionary<string, FirstRunSeenRecord>))]
internal sealed partial class FirstRunJsonContext : JsonSerializerContext;
#endregion
