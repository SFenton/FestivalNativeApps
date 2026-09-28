namespace Festival.Core.Tests;

public class BandTypesTests
{
    [Theory]
    [InlineData(BandType.Duets, "Band_Duets", "Duos", 2)]
    [InlineData(BandType.Trios, "Band_Trios", "Trios", 3)]
    [InlineData(BandType.Quad, "Band_Quad", "Quads", 4)]
    public void BandType_RoundTripsAndLabels(BandType type, string id, string label, int members)
    {
        Assert.Equal(id, type.ServiceId());
        Assert.Equal(label, type.Label());
        Assert.Equal(members, type.MemberCount());
        Assert.True(BandTypeInfo.TryParse(id, out var parsed));
        Assert.Equal(type, parsed);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("band_duets")]
    [InlineData("Duos")]
    public void BandType_RejectsUnknown(string? id)
    {
        Assert.False(BandTypeInfo.TryParse(id, out var parsed));
        Assert.Equal(default, parsed);
        Assert.Equal(3, BandTypeInfo.All.Count);
    }

    [Theory]
    [InlineData(BandRankingMetric.Adjusted, "adjusted", "Adjusted Skill")]
    [InlineData(BandRankingMetric.Weighted, "weighted", "Weighted")]
    [InlineData(BandRankingMetric.FcRate, "fcrate", "FC Rate")]
    [InlineData(BandRankingMetric.TotalScore, "totalscore", "Total Score")]
    public void Metric_RoundTripsAndLabels(BandRankingMetric metric, string id, string label)
    {
        Assert.Equal(id, metric.ServiceId());
        Assert.Equal(label, metric.Label());
        Assert.True(BandRankingMetricInfo.TryParse(id, out var parsed));
        Assert.Equal(metric, parsed);
        Assert.False(BandRankingMetricInfo.TryParse("maxscore", out _));
        Assert.Equal(4, BandRankingMetricInfo.All.Count);
    }
}
