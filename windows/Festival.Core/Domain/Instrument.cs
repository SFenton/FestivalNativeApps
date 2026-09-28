namespace Festival.Core.Domain;

#region Instrument
/// <summary>The nine solo instrument charts, in the service's stable display order.</summary>
public enum Instrument
{
    /// <summary>Lead (<c>Solo_Guitar</c>).</summary>
    Lead,
    /// <summary>Bass (<c>Solo_Bass</c>).</summary>
    Bass,
    /// <summary>Drums (<c>Solo_Drums</c>).</summary>
    Drums,
    /// <summary>Tap Vocals (<c>Solo_Vocals</c>).</summary>
    Vocals,
    /// <summary>Pro Lead (<c>Solo_PeripheralGuitar</c>).</summary>
    ProLead,
    /// <summary>Pro Bass (<c>Solo_PeripheralBass</c>).</summary>
    ProBass,
    /// <summary>Karaoke (<c>Solo_PeripheralVocals</c>).</summary>
    Karaoke,
    /// <summary>Pro Drums + Cymbals (<c>Solo_PeripheralCymbals</c>).</summary>
    ProCymbals,
    /// <summary>Pro Drums (<c>Solo_PeripheralDrums</c>).</summary>
    ProDrums,
}
#endregion

#region Instrument metadata
/// <summary>Service identifiers, labels and icon assets for <see cref="Instrument"/>.</summary>
public static class InstrumentInfo
{
    /// <summary>All nine charts in the service's display order.</summary>
    public static IReadOnlyList<Instrument> All { get; } = Enum.GetValues<Instrument>();

    /// <summary>Returns the exact service identifier used in URLs and score maps.</summary>
    /// <param name="instrument">Solo chart.</param>
    /// <returns>A value such as <c>Solo_Guitar</c>.</returns>
    public static string ServiceId(this Instrument instrument) => instrument switch
    {
        Instrument.Lead => "Solo_Guitar",
        Instrument.Bass => "Solo_Bass",
        Instrument.Drums => "Solo_Drums",
        Instrument.Vocals => "Solo_Vocals",
        Instrument.ProLead => "Solo_PeripheralGuitar",
        Instrument.ProBass => "Solo_PeripheralBass",
        Instrument.Karaoke => "Solo_PeripheralVocals",
        Instrument.ProCymbals => "Solo_PeripheralCymbals",
        _ => "Solo_PeripheralDrums",
    };

    /// <summary>Returns the same user-facing name as the web client.</summary>
    /// <param name="instrument">Solo chart.</param>
    /// <returns>Title Case label.</returns>
    public static string Label(this Instrument instrument) => instrument switch
    {
        Instrument.Lead => "Lead",
        Instrument.Bass => "Bass",
        Instrument.Drums => "Drums",
        Instrument.Vocals => "Tap Vocals",
        Instrument.ProLead => "Pro Lead",
        Instrument.ProBass => "Pro Bass",
        Instrument.Karaoke => "Karaoke",
        Instrument.ProCymbals => "Pro Drums + Cymbals",
        _ => "Pro Drums",
    };

    /// <summary>Returns the bundled icon file name, choosing the keys variant for keyboard charts.</summary>
    /// <param name="instrument">Solo chart.</param>
    /// <param name="keyboard">Whether the song's Lead signature is <c>Keyboard</c>.</param>
    /// <returns>File name such as <c>instrument_guitar.png</c>.</returns>
    public static string IconFile(this Instrument instrument, bool keyboard = false)
    {
        var name = instrument switch
        {
            Instrument.Lead => keyboard ? "keys" : "guitar",
            Instrument.Bass => "bass",
            Instrument.Drums => "drums",
            Instrument.Vocals => "vocals",
            Instrument.ProLead => keyboard ? "pro_keys" : "pro_guitar",
            Instrument.ProBass => "pro_bass",
            Instrument.Karaoke => "peripheral_vocals",
            Instrument.ProCymbals => "peripheral_cymbals",
            _ => "peripheral_drums",
        };
        return $"instrument_{name}.png";
    }

    /// <summary>Parses an exact service identifier.</summary>
    /// <param name="serviceId">Identifier such as <c>Solo_Bass</c>.</param>
    /// <param name="instrument">Parsed chart when successful.</param>
    /// <returns><see langword="true"/> for one of the nine known identifiers.</returns>
    public static bool TryParse(string? serviceId, out Instrument instrument)
    {
        foreach (var candidate in All)
        {
            if (string.Equals(candidate.ServiceId(), serviceId, StringComparison.Ordinal))
            {
                instrument = candidate;
                return true;
            }
        }
        instrument = default;
        return false;
    }
}
#endregion
