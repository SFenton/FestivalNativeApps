
namespace Festival.Core.Tests;

public class ServiceIssueTests
{
    [Theory]
    [InlineData("scrape", true)]
    [InlineData(" Post-Process ", true)]
    [InlineData("publish", true)]
    [InlineData("publication-commit", true)]
    [InlineData("publication-commit-deferred", true)]
    [InlineData("publication-isolation-pending", false)]
    [InlineData("max-score-maintenance:v1:x", false)]
    [InlineData(null, false)]
    public void FreezeReason_Classifies(string? reason, bool scoreUpdate) =>
        Assert.Equal(scoreUpdate, ServiceFreezeReason.IsScoreUpdate(reason));

    [Fact]
    public void From_ScrapeFreeze_RetriesAutomatically()
    {
        var issue = ServiceIssue.From(new FestivalApiException(FestivalApiErrorKind.PublicReadFrozen, 503, "30", "scrape"));
        Assert.Equal(new ServiceIssue(ServiceIssueKind.ScrapeInProgress, 30), issue);
        Assert.True(issue.RetriesAutomatically);
        Assert.Equal("Scores are updating", issue.Title);
        Assert.Equal("Retry Now", issue.RetryLabel);
        Assert.Contains("automatically", issue.Message);
    }

    [Fact]
    public void From_OtherFreezeAndOutage_AreUnavailable()
    {
        var other = ServiceIssue.From(new FestivalApiException(FestivalApiErrorKind.PublicReadFrozen, 503, null, "publication-isolation-pending"));
        Assert.Equal(ServiceIssueKind.Unavailable, other.Kind);
        Assert.False(other.RetriesAutomatically);
        Assert.Null(other.Title);
        Assert.Equal("The service is temporarily unavailable. Try again.", other.Message);
        var outage = ServiceIssue.From(new FestivalApiException(FestivalApiErrorKind.Unavailable, 503, "12"));
        Assert.Equal(12, outage.RetryAfter);
        Assert.Equal("The service is temporarily unavailable. Try again in 12 seconds.", outage.Message);
        Assert.Equal("Retry", outage.RetryLabel);
    }

    [Fact]
    public void From_MapsRemainingKinds()
    {
        var syncing = ServiceIssue.From(new FestivalApiException(FestivalApiErrorKind.Syncing));
        Assert.Equal(("Still syncing", ServiceIssueKind.Syncing), (syncing.Title, syncing.Kind));
        Assert.Contains("prepared", syncing.Message);
        var notFound = ServiceIssue.From(new FestivalApiException(FestivalApiErrorKind.HttpStatus, 404));
        Assert.Equal(ServiceIssueKind.NotFound, notFound.Kind);
        Assert.Equal("This content is no longer available.", notFound.Message);
        var offline = ServiceIssue.From(new FestivalApiException(FestivalApiErrorKind.Offline));
        Assert.Equal(("You're offline", "Check your connection and try again."), (offline.Title, offline.Message));
        Assert.Equal(ServiceIssueKind.Offline, ServiceIssue.From(new FestivalApiException(FestivalApiErrorKind.Timeout)).Kind);
        var other = ServiceIssue.From(new FestivalApiException(FestivalApiErrorKind.HttpStatus, 500));
        Assert.Equal(ServiceIssueKind.Other, other.Kind);
        Assert.Equal("The service is temporarily unavailable. Try again.", other.Message);
        var foreign = ServiceIssue.From(new InvalidOperationException("secret server text"));
        Assert.Equal("Something went wrong. Try again.", foreign.Message);
        Assert.Equal("Something went wrong. Try again.", new ServiceIssue(ServiceIssueKind.Other).Message);
    }

    [Theory]
    [InlineData("30", 30)]
    [InlineData(" 5 ", 5)]
    [InlineData("0", null)]
    [InlineData("86401", null)]
    [InlineData("-3", null)]
    [InlineData("Wed, 21 Oct 2015 07:28:00 GMT", null)]
    [InlineData(null, null)]
    public void RetryAfterSeconds_ParsesDeltaSecondsOnly(string? raw, int? expected) =>
        Assert.Equal(expected, ServiceIssue.RetryAfterSeconds(raw));

    [Fact]
    public void Backoff_DoublesConsecutiveFailuresToCap()
    {
        var backoff = new ServiceRetryBackoff();
        var now = DateTimeOffset.UnixEpoch;
        Assert.Equal(30, backoff.NextDelay("s", 30, now));
        now += TimeSpan.FromSeconds(31);
        Assert.Equal(60, backoff.NextDelay("s", 30, now));
        now += TimeSpan.FromSeconds(61);
        Assert.Equal(120, backoff.NextDelay("s", 30, now));
        now += TimeSpan.FromSeconds(121);
        Assert.Equal(240, backoff.NextDelay("s", 30, now));
        now += TimeSpan.FromSeconds(241);
        Assert.Equal(300, backoff.NextDelay("s", 30, now));
        now += TimeSpan.FromSeconds(301);
        Assert.Equal(300, backoff.NextDelay("s", 30, now));
    }

    [Fact]
    public void Backoff_RestartsAfterQuietPeriodOrReset()
    {
        var backoff = new ServiceRetryBackoff();
        var now = DateTimeOffset.UnixEpoch;
        backoff.NextDelay("s", null, now);
        Assert.Equal(30, backoff.NextDelay("s", null, now + TimeSpan.FromMinutes(10)));
        backoff.NextDelay("s", 10, now);
        backoff.Reset("s");
        Assert.Equal(10, backoff.NextDelay("s", 10, now));
        Assert.Equal(1, backoff.NextDelay("other", 0, now));
        Assert.Equal(300, backoff.NextDelay("big", 9999, now));
    }

    [Theory]
    [InlineData(FestivalApiErrorKind.InsecureBaseUrl, "secure")]
    [InlineData(FestivalApiErrorKind.ForbiddenRequest, "unsafe")]
    [InlineData(FestivalApiErrorKind.InvalidResource, "unavailable")]
    [InlineData(FestivalApiErrorKind.InvalidResponse, "could not read")]
    [InlineData(FestivalApiErrorKind.InvalidPublication, "verified")]
    [InlineData(FestivalApiErrorKind.Unavailable, "temporarily")]
    [InlineData(FestivalApiErrorKind.PublicReadFrozen, "temporarily")]
    [InlineData(FestivalApiErrorKind.Syncing, "syncing")]
    [InlineData(FestivalApiErrorKind.UnexpectedNotModified, "incomplete")]
    [InlineData(FestivalApiErrorKind.Timeout, "too long")]
    [InlineData(FestivalApiErrorKind.Offline, "connection")]
    public void Describe_IsReadable(FestivalApiErrorKind kind, string fragment) =>
        Assert.Contains(fragment, FestivalApiException.Describe(kind, null));

    [Theory]
    [InlineData(404, "no longer")]
    [InlineData(429, "Too many")]
    [InlineData(502, "temporarily")]
    [InlineData(418, "HTTP 418")]
    public void Describe_HttpStatus(int status, string fragment) =>
        Assert.Contains(fragment, FestivalApiException.Describe(FestivalApiErrorKind.HttpStatus, status));
}
