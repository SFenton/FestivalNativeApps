using System.Text.Json.Serialization;

namespace Festival.Core.Data;
// Declaration-only (source-generated); one context per feature (see FirstRunJsonContext).

#region Source-generated JSON
/// <summary>Notification wire and seen-state metadata.</summary>
[JsonSourceGenerationOptions(PropertyNameCaseInsensitive = false, DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
[JsonSerializable(typeof(ImprovementNotificationsEnvelope))]
[JsonSerializable(typeof(Dictionary<string, List<string>>))]
internal sealed partial class NotificationsJsonContext : JsonSerializerContext;
#endregion
