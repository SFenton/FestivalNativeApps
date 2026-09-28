using System.Text.Json.Serialization;

namespace Festival.Core;

#region Wire models
/// <summary>A read-only snapshot of songs belonging to one publication.</summary>
/// <param name="PublicationId">Opaque publication identifier.</param>
/// <param name="Songs">Songs in this publication.</param>
public sealed record SongsSnapshot(
    [property: JsonPropertyName("publicationId")] string PublicationId,
    [property: JsonPropertyName("songs")] IReadOnlyList<Song> Songs);

/// <summary>A song and its displayed difficulty, on a scale from one to seven.</summary>
/// <param name="Id">Stable song identifier.</param>
/// <param name="Title">Displayed title.</param>
/// <param name="Artist">Displayed artist.</param>
/// <param name="Difficulty">Difficulty from one through seven.</param>
public sealed record Song(
    [property: JsonPropertyName("id")] string Id,
    [property: JsonPropertyName("title")] string Title,
    [property: JsonPropertyName("artist")] string Artist,
    [property: JsonPropertyName("difficulty")] int Difficulty);
#endregion
