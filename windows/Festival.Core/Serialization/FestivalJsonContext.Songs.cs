using System.Text.Json.Serialization;

namespace Festival.Core.Data;
// Declaration-only: the source generator emits the code, so this lives outside the coverage-gated Data/ folder.

#region Songs-lane JSON
/// <summary>Item Shop and CHOpt path wire metadata (a separate context: attributed partials of one context collide).</summary>
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = false, UseStringEnumConverter = true)]
[JsonSerializable(typeof(ShopResponse))]
[JsonSerializable(typeof(SongPathData))]
internal sealed partial class SongsJsonContext : JsonSerializerContext;
#endregion
