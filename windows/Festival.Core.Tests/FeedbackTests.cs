using System.Net;
using System.Text;
using Festival.Core.ViewModels;

namespace Festival.Core.Tests;

public class FeedbackTests
{
    private static FeedbackAttachment Media(string id, string mime = "image/png", long? size = 1_000) => new(id, id + ".png", mime, size);

    #region Domain
    [Fact]
    public void Kinds_CarryWireValuesAndCopy()
    {
        Assert.Equal("bug", FeedbackKind.Bug.Wire());
        Assert.Equal("[Feature] ", FeedbackKind.Feature.TitlePrefix());
        Assert.Equal("Report an Issue", FeedbackKind.Bug.FormTitle());
        Assert.Equal("Request a Feature", FeedbackKind.Feature.FormTitle());
        Assert.True(FeedbackKind.Bug.HasBugFields());
        Assert.False(FeedbackKind.Feature.HasBugFields());
        Assert.Equal("feature", FeedbackKind.Feature.AutomationSuffix());
        Assert.NotEqual(FeedbackKind.Bug.RowDescription(), FeedbackKind.Feature.RowDescription());
        Assert.Contains("[Bug]", FeedbackCopy.TitleHelp(FeedbackKind.Bug));
        Assert.Contains("[Feature]", FeedbackCopy.TitleHelp(FeedbackKind.Feature));
        Assert.NotEqual(FeedbackCopy.DescriptionHelp(FeedbackKind.Bug), FeedbackCopy.DescriptionHelp(FeedbackKind.Feature));
    }

    [Fact]
    public void Draft_StartsWithPrefixAndIsClean()
    {
        var draft = new FeedbackDraft(FeedbackKind.Bug);
        Assert.Equal("[Bug] ", draft.Title);
        Assert.False(draft.IsDirty);
        Assert.Equal(FeedbackProblem.MissingTitle, draft.Problem);
    }

    [Fact]
    public void Draft_DirtyForAnyInput_ButFeatureIgnoresBugFields()
    {
        Assert.True((new FeedbackDraft(FeedbackKind.Bug) with { Title = "[Bug] Crash" }).IsDirty);
        Assert.True((new FeedbackDraft(FeedbackKind.Bug) with { ReproSteps = "1" }).IsDirty);
        Assert.True((new FeedbackDraft(FeedbackKind.Bug) with { ExpectedBehavior = "x" }).IsDirty);
        Assert.True((new FeedbackDraft(FeedbackKind.Feature) with { Description = "x" }).IsDirty);
        Assert.True((new FeedbackDraft(FeedbackKind.Feature) with { Attachments = [Media("a")] }).IsDirty);
        Assert.False((new FeedbackDraft(FeedbackKind.Feature) with { ReproSteps = "ignored" }).IsDirty);
        Assert.False((new FeedbackDraft(FeedbackKind.Bug) with { Title = "  [bug]  " }).IsDirty);
    }

    [Fact]
    public void Draft_NormalizesTitleAndValidates()
    {
        var draft = new FeedbackDraft(FeedbackKind.Bug) with { Title = "  Crash on launch " };
        Assert.Equal("[Bug] Crash on launch", draft.NormalizedTitle);
        Assert.Equal(FeedbackProblem.MissingDescription, draft.Problem);
        draft = draft with { Description = "It crashes" };
        Assert.Null(draft.Problem);
        Assert.Equal(FeedbackProblem.TooLong, (draft with { Title = new string('a', 200) }).Problem);
        Assert.Equal(FeedbackProblem.TooLong, (draft with { ReproSteps = new string('a', 10_001) }).Problem);
        Assert.Equal("Add a title after the prefix.", FeedbackProblem.MissingTitle.Message());
        Assert.Equal("Add a description.", FeedbackProblem.MissingDescription.Message());
        Assert.Equal("Shorten the text and try again.", FeedbackProblem.TooLong.Message());
    }

    [Fact]
    public void Adding_SkipsDuplicatesTypesCountAndSize()
    {
        var draft = new FeedbackDraft(FeedbackKind.Bug) with { Attachments = [Media("a")] };
        var result = draft.Adding([Media("a"), Media("b"), new FeedbackAttachment("doc", "x.pdf", "application/pdf", 10)]);
        Assert.Equal(["a", "b"], result.Attachments.Select(a => a.Id));
        Assert.Equal("Only images and videos can be attached.", result.Notice);

        var full = new FeedbackDraft(FeedbackKind.Bug).Adding(Enumerable.Range(0, 12).Select(i => Media($"m{i}")));
        Assert.Equal(FeedbackLimits.MaxAttachments, full.Attachments.Count);
        Assert.Equal(4, FeedbackLimits.MaxAttachments);
        Assert.Equal("You can attach up to 4 files.", full.Notice);

        var big = new FeedbackDraft(FeedbackKind.Bug).Adding([
            Media("huge", "video/mp4", FeedbackLimits.MaxAttachmentBytes + 1),
            Media("v1", "video/mp4", 40L * 1024 * 1024),
            Media("v2", "video/mp4", 40L * 1024 * 1024),
            Media("v3", "video/mp4", 40L * 1024 * 1024),
            Media("unknown", "image/png", null),
        ]);
        Assert.Equal(["v1", "v2", "unknown"], big.Attachments.Select(a => a.Id));
        Assert.Equal("Attachments must add up to less than 90 MB.", big.Notice);
        Assert.True(FeedbackLimits.MaxTotalBytes < FeedbackLimits.MaxRequestBytes);
        Assert.Equal("Add up to 4 screenshots or screen recordings, 90 MB in total. Select one to open it.", FeedbackCopy.AttachHelp);
        Assert.Null(new FeedbackDraft(FeedbackKind.Bug).Adding([Media("ok")]).Notice);
    }

    [Fact]
    public void Attachment_DescribesItself()
    {
        var video = new FeedbackAttachment("p", "clip.mp4", "VIDEO/MP4", 3 * 1024 * 1024);
        Assert.True(video.IsVideo);
        Assert.True(video.IsMedia);
        Assert.Equal("Video, clip.mp4, 3 MB", video.AccessibilityLabel);
        Assert.Equal("Image, a.png", new FeedbackAttachment("a", "a.png", "image/png", null).AccessibilityLabel);
        Assert.False(new FeedbackAttachment("t", "t.txt", "text/plain", 1).IsMedia);
    }

    [Theory]
    [InlineData("shot.PNG", "image/png")]
    [InlineData(@"C:\clips\run.mov", "video/quicktime")]
    [InlineData("notes.txt", "application/octet-stream")]
    [InlineData("noextension", "application/octet-stream")]
    public void Media_MapsExtensions(string name, string mime)
    {
        Assert.Equal(mime, FeedbackMedia.MimeType(name));
        Assert.Contains(".mp4", FeedbackMedia.Extensions);
    }

    [Fact]
    public void Submission_OrdersFieldsAndOmitsEmptyOptionals()
    {
        var bug = (new FeedbackDraft(FeedbackKind.Bug) with
        {
            Title = "[Bug] X", Description = " d ", ReproSteps = " r ", ExpectedBehavior = "",
        }).Submission("windows", "2610.02.01", "Windows 11");
        Assert.Equal(["kind", "platform", "title", "description", "repro", "appVersion", "clientInfo"],
            bug.FormFields.Select(f => f.Key));
        Assert.Equal("d", bug.Description);
        Assert.Equal("Windows 11", bug.ClientInfo);

        var clipped = (new FeedbackDraft(FeedbackKind.Bug) with { Title = "T", Description = "d", ExpectedBehavior = "e" })
            .Submission("windows", new string('v', 70), " " + new string('c', 300));
        var fields = clipped.FormFields.ToDictionary(f => f.Key, f => f.Value);
        Assert.Equal("e", fields["expected"]);
        Assert.Equal(64, fields["appVersion"].Length);
        Assert.Equal(256, fields["clientInfo"].Length);
        Assert.False(fields.ContainsKey("repro"));

        var feature = (new FeedbackDraft(FeedbackKind.Feature) with { Title = "Idea", Description = "d", ReproSteps = "dropped" })
            .Submission("windows", "", "");
        Assert.Equal(["kind", "platform", "title", "description"], feature.FormFields.Select(f => f.Key));
        Assert.Equal("[Feature] Idea", feature.Title);
        Assert.Equal("", feature.ReproSteps);
    }

    [Theory]
    [InlineData("shot.png", "shot.png")]
    [InlineData(@"C:\Users\me\clip ""1"".mp4", "clip 1.mp4")]
    [InlineData("a/b/c.jpg", "c.jpg")]
    [InlineData("bad\u0001\r\nname.png", "badname.png")]
    [InlineData("   ", "attachment")]
    [InlineData("dir/", "attachment")]
    public void SafeFileName_StripsPathsAndUnsafeCharacters(string raw, string expected) =>
        Assert.Equal(expected, FeedbackSubmission.SafeFileName(raw));

    [Fact]
    public void SafeFileName_CapsLength() => Assert.Equal(120, FeedbackSubmission.SafeFileName(new string('x', 300)).Length);

    private const string JobId = "0123456789abcdef0123456789abcdef";

    [Fact]
    public void Job_MessagesStatesAndIds()
    {
        Assert.Equal("Thanks! Your report was filed as issue #42.",
            new FeedbackJob(JobId, FeedbackJobState.Submitted, 42).Message(FeedbackKind.Bug));
        Assert.Equal("Thanks! Your request was filed on GitHub. 1 attachment couldn't be attached.",
            new FeedbackJob(JobId, FeedbackJobState.Submitted, null, 1).Message(FeedbackKind.Feature));
        Assert.Equal("Thanks! Your report was received and will be filed on GitHub shortly. 2 attachments couldn't be attached.",
            new FeedbackJob(null, FeedbackJobState.Processing, null, 2).Message(FeedbackKind.Bug));
        Assert.True(new FeedbackJob(JobId, FeedbackJobState.Failed).IsTerminal);
        Assert.False(new FeedbackJob(JobId, FeedbackJobState.Queued).IsTerminal);
        Assert.True(FeedbackJob.IsValidId(JobId));
        Assert.False(FeedbackJob.IsValidId(JobId.ToUpperInvariant()));
        Assert.False(FeedbackJob.IsValidId(JobId[..31]));
        Assert.False(FeedbackJob.IsValidId("../" + JobId[3..]));
        Assert.False(FeedbackJob.IsValidId(null));
        Assert.Equal(FeedbackJobState.Submitted, FeedbackJob.ParseState(" Submitted "));
        Assert.Equal(FeedbackJobState.Queued, FeedbackJob.ParseState("queued"));
        Assert.Equal(FeedbackJobState.Processing, FeedbackJob.ParseState("processing"));
        Assert.Equal(FeedbackJobState.Failed, FeedbackJob.ParseState("failed"));
        Assert.Null(FeedbackJob.ParseState("other"));
        Assert.Null(FeedbackJob.ParseState(null));
    }

    [Theory]
    [InlineData(400, null, "Check the fields")]
    [InlineData(422, null, "Check the fields")]
    [InlineData(404, null, "isn't available right now")]
    [InlineData(405, null, "isn't available right now")]
    [InlineData(501, null, "isn't available right now")]
    [InlineData(413, null, "under 90 MB in total")]
    [InlineData(415, null, "image and video attachments")]
    [InlineData(429, null, "Try again later")]
    [InlineData(500, null, "temporarily unavailable")]
    [InlineData(503, null, "busy right now")]
    [InlineData(418, null, "(HTTP 418)")]
    [InlineData(413, "payload_too_large", "under 90 MB in total")]
    [InlineData(400, "too_many_attachments", "Attach up to 4 files.")]
    [InlineData(400, "unsupported_media", "image and video attachments")]
    [InlineData(404, "feedback_disabled", "isn't available right now")]
    [InlineData(503, "feedback_busy", "busy right now")]
    [InlineData(400, "title_required", "Add a title")]
    [InlineData(400, "description_required", "Add a description")]
    [InlineData(400, "field_too_long", "too long")]
    [InlineData(400, "invalid_kind", "Check the fields")]
    public void Exception_MapsStatusesAndCodes(int status, string? code, string fragment)
    {
        var error = FeedbackException.ForStatus(status, code);
        Assert.Contains(fragment, error.Message);
        Assert.Equal(status, error.Status);
    }

    [Fact]
    public void Exception_RateLimitNamesTheWait()
    {
        Assert.EndsWith("Try again in 45 seconds.", FeedbackException.ForStatus(429, null, 45).Message);
        Assert.EndsWith("Try again in 10 minutes.", FeedbackException.ForStatus(429, null, 600).Message);
        Assert.Equal("Your request couldn't be filed on GitHub. Try again in a few minutes.",
            FeedbackException.FilingFailed(FeedbackKind.Feature).Message);
    }

    [Theory]
    [InlineData(1, "1 second")]
    [InlineData(59, "59 seconds")]
    [InlineData(60, "1 minute")]
    [InlineData(61, "2 minutes")]
    public void Format_Wait(int seconds, string expected) => Assert.Equal(expected, FeedbackFormat.Wait(seconds));

    [Fact]
    public void Exception_FactoriesAreReadable()
    {
        Assert.Contains("connection", FeedbackException.Offline().Message);
        Assert.Contains("too long", FeedbackException.TimedOut().Message);
        Assert.Equal("\"a.png\" couldn't be read. Remove it and try again.", FeedbackException.Unreadable("a.png").Message);
    }

    [Theory]
    [InlineData(512, "512 B")]
    [InlineData(2048, "2 KB")]
    [InlineData(3 * 1024 * 1024, "3 MB")]
    [InlineData(3_565_158, "3.4 MB")]
    [InlineData(1024L * 1024 * 1024 * 3 / 2, "1.5 GB")]
    public void Format_Bytes(long bytes, string expected) => Assert.Equal(expected, FeedbackFormat.Bytes(bytes));
    #endregion

    #region Request gate
    private static HttpRequestMessage Post(string url, HttpContent? content = null) =>
        new(HttpMethod.Post, url) { Content = content ?? new StringContent("x") };

    [Fact]
    public void ValidateFeedback_AcceptsOnlyThePostToTheFeedbackPath()
    {
        using var ok = RequestGate.CreateFeedbackPost(new Uri("https://x.test/api/feedback"), new StringContent("x"));
        RequestGate.ValidateFeedback(ok);
        Assert.Equal(HttpMethod.Post, ok.Method);
        Assert.True(ok.Headers.CacheControl!.NoCache);
        Assert.Contains(ok.Headers.Accept, a => a.MediaType == "application/json");
        Assert.Throws<FestivalApiException>(() => RequestGate.ValidateKeyless(ok));

        foreach (var bad in new[]
                 {
                     Post("https://x.test/api/feedback/"), Post("https://x.test/api/feedback?x=1"), Post("https://x.test/api/feedback#f"),
                     Post("https://x.test/api/songs"), Post("https://x.test/api/Feedback"),
                     new HttpRequestMessage(HttpMethod.Post, "https://x.test/api/feedback"),
                     new HttpRequestMessage(HttpMethod.Get, "https://x.test/api/feedback"),
                     new HttpRequestMessage(HttpMethod.Put, "https://x.test/api/feedback") { Content = new StringContent("x") },
                     new HttpRequestMessage { Method = HttpMethod.Post, Content = new StringContent("x") },
                 })
        {
            using (bad) Assert.Equal(FestivalApiErrorKind.ForbiddenRequest,
                Assert.Throws<FestivalApiException>(() => RequestGate.ValidateFeedback(bad)).Kind);
        }
    }

    [Theory]
    [InlineData("X-API-Key")]
    [InlineData("x-fst-selected-profile")]
    public void ValidateFeedback_RejectsForbiddenHeadersOnRequestOrContent(string header)
    {
        using var onRequest = Post("https://x.test/api/feedback");
        onRequest.Headers.TryAddWithoutValidation(header, "v");
        Assert.Throws<FestivalApiException>(() => RequestGate.ValidateFeedback(onRequest));
        using var onContent = Post("https://x.test/api/feedback");
        onContent.Content!.Headers.TryAddWithoutValidation(header, "v");
        Assert.Throws<FestivalApiException>(() => RequestGate.ValidateFeedback(onContent));
    }

    [Fact]
    public async Task SendFeedbackAsync_NeverTransmitsForbiddenRequest()
    {
        var handler = new FakeHandler();
        using var request = Post("https://x.test/api/songs");
        await Assert.ThrowsAsync<FestivalApiException>(() => new RequestGate(new HttpClient(handler)).SendFeedbackAsync(request));
        Assert.Empty(handler.Requests);
    }

    [Fact]
    public async Task SendFeedbackAsync_UsesTheLongerUploadDeadline()
    {
        var handler = new FakeHandler
        {
            Responder = async (_, token) =>
            {
                await Task.Delay(300, token);
                return new HttpResponseMessage(HttpStatusCode.Created);
            },
        };
        var gate = new RequestGate(new HttpClient(handler), TimeSpan.FromMilliseconds(50));
        using var request = Post("https://x.test/api/feedback");
        Assert.Equal(201, (await gate.SendFeedbackAsync(request)).Status);
        using var get = RequestGate.CreateGet(new Uri("https://x.test/api/songs"));
        Assert.Equal(FestivalApiErrorKind.Timeout, (await Assert.ThrowsAsync<FestivalApiException>(() => gate.SendAsync(get))).Kind);
    }
    #endregion

    #region Client
    private sealed record Captured(HttpMethod Method, Uri Uri, string ContentType, string Body, Dictionary<string, string> Headers);

    private static (FestivalApiClient Client, FakeHandler Handler, List<Captured> Seen) Client(
        HttpStatusCode status, string? body = null, Exception? failure = null, string? retryAfter = null)
    {
        var seen = new List<Captured>();
        var handler = new FakeHandler
        {
            Responder = async (request, _) =>
            {
                if (failure is not null) throw failure;
                var text = request.Content is null ? "" : await request.Content.ReadAsStringAsync();
                seen.Add(new Captured(request.Method, request.RequestUri!, request.Content?.Headers.ContentType?.ToString() ?? "", text,
                    request.Headers.ToDictionary(h => h.Key, h => string.Join(",", h.Value), StringComparer.OrdinalIgnoreCase)));
                var response = new HttpResponseMessage(status) { Content = new StringContent(body ?? "") };
                if (retryAfter is not null) response.Headers.TryAddWithoutValidation("Retry-After", retryAfter);
                return response;
            },
        };
        return (new FestivalApiClient(new RequestGate(new HttpClient(handler)), new Uri(Wire.BaseUrl)), handler, seen);
    }

    private static FeedbackSubmission Submission(params FeedbackAttachment[] media) =>
        (new FeedbackDraft(FeedbackKind.Bug) with
        {
            Title = "[Bug] Crash", Description = "Desc", ReproSteps = "Step", ExpectedBehavior = "Works", Attachments = media,
        }).Submission("windows", "2610.02.01", "Windows 11");

    private static Stream Open(FeedbackAttachment attachment) => new MemoryStream(Encoding.UTF8.GetBytes("bytes-of-" + attachment.Id));

    [Fact]
    public async Task Submit_PostsMultipartFormWithMediaParts()
    {
        var (client, _, seen) = Client(HttpStatusCode.Accepted, $$"""{"id":"{{JobId}}","status":"queued"}""");
        var job = await client.SubmitFeedbackAsync(
            Submission(new("a", @"C:\pics\shot ""1"".png", "image/png", 9), new("b", "clip.mp4", "video/mp4", 9),
                new("c", "odd.bin", "bogus type", 9)),
            Open);

        Assert.Equal(new FeedbackJob(JobId, FeedbackJobState.Queued), job);
        var sent = Assert.Single(seen);
        Assert.Equal(HttpMethod.Post, sent.Method);
        Assert.Equal("https://festivalscoretracker.com/api/feedback", sent.Uri.ToString());
        Assert.StartsWith("multipart/form-data", sent.ContentType);
        Assert.DoesNotContain(sent.Headers.Keys, k => k.Equals("X-API-Key", StringComparison.OrdinalIgnoreCase) ||
                                                      k.StartsWith("x-fst-selected-", StringComparison.OrdinalIgnoreCase));
        foreach (var (name, value) in new[]
                 {
                     ("kind", "bug"), ("platform", "windows"), ("title", "[Bug] Crash"), ("description", "Desc"),
                     ("repro", "Step"), ("expected", "Works"), ("appVersion", "2610.02.01"), ("clientInfo", "Windows 11"),
                 })
        {
            Assert.Matches($"name={name}\\r\\n(?:[^\\r\\n]+\\r\\n)*\\r\\n{System.Text.RegularExpressions.Regex.Escape(value)}\\r\\n", sent.Body);
        }
        Assert.Contains("name=media; filename=\"shot 1.png\"", sent.Body);
        Assert.Contains("name=media; filename=clip.mp4", sent.Body);
        Assert.Contains("Content-Type: video/mp4", sent.Body);
        Assert.Contains("Content-Type: application/octet-stream", sent.Body);
        Assert.Contains("bytes-of-a", sent.Body);
        Assert.Contains("bytes-of-c", sent.Body);
        Assert.True(sent.Body.IndexOf("name=clientInfo", StringComparison.Ordinal) < sent.Body.IndexOf("name=media", StringComparison.Ordinal));
    }

    [Fact]
    public void ParseJob_IsTolerant()
    {
        static FeedbackJob? Parse(string body, string? known = null) => FestivalApiClient.ParseFeedbackJob(Encoding.UTF8.GetBytes(body), known);
        Assert.Null(Parse(""));
        Assert.Null(Parse("not json"));
        Assert.Null(Parse("[1]"));
        Assert.Equal(new FeedbackJob(null, FeedbackJobState.Processing), Parse("{}"));
        Assert.Equal(new FeedbackJob(JobId, FeedbackJobState.Processing), Parse("""{"id":"NOT-HEX","status":"weird"}""", JobId));
        Assert.Equal(new FeedbackJob(JobId, FeedbackJobState.Submitted, 7, 2), Parse($$"""
            {"id":"{{JobId}}","status":"submitted","issueNumber":7,"attachments":[
              {"name":"a.mov","kind":"video","outcome":"skipped","note":"too big"},
              {"name":"b.png","kind":"image","outcome":"attached"},
              {"name":"c.png","kind":"image","outcome":"SKIPPED"},
              {"outcome":5}, 3]}
            """));
        Assert.Equal(new FeedbackJob(null, FeedbackJobState.Failed), Parse("""{"status":"failed","issueNumber":0,"attachments":{}}"""));
        Assert.Equal(new FeedbackJob(null, FeedbackJobState.Processing), Parse("""{"status":5,"issueNumber":7.5}"""));
    }

    [Fact]
    public async Task Submit_AcceptsBare202()
    {
        var (client, _, _) = Client(HttpStatusCode.Accepted);
        Assert.Equal(new FeedbackJob(null, FeedbackJobState.Queued), await client.SubmitFeedbackAsync(Submission(), Open));
    }

    [Fact]
    public async Task Submit_MapsStatusAndCodeToReadableError()
    {
        var (client, _, _) = Client(HttpStatusCode.RequestEntityTooLarge,
            """{"error":"server text never shown","code":"payload_too_large","maxBytes":94371840}""");
        var error = await Assert.ThrowsAsync<FeedbackException>(() => client.SubmitFeedbackAsync(Submission(), Open));
        Assert.Equal(413, error.Status);
        Assert.Contains("90 MB", error.Message);
        Assert.DoesNotContain("server text", error.Message);

        var (busy, _, _) = Client(HttpStatusCode.TooManyRequests, "not json", retryAfter: "120");
        Assert.EndsWith("Try again in 2 minutes.",
            (await Assert.ThrowsAsync<FeedbackException>(() => busy.SubmitFeedbackAsync(Submission(), Open))).Message);

        var (odd, _, _) = Client(HttpStatusCode.TooManyRequests, """{"code":5}""", retryAfter: "soon");
        Assert.EndsWith("Try again later.",
            (await Assert.ThrowsAsync<FeedbackException>(() => odd.SubmitFeedbackAsync(Submission(), Open))).Message);

        var (array, _, _) = Client(HttpStatusCode.BadRequest, "[]");
        Assert.Contains("Check the fields",
            (await Assert.ThrowsAsync<FeedbackException>(() => array.SubmitFeedbackAsync(Submission(), Open))).Message);
    }

    [Fact]
    public async Task Status_ReadsTheJobWithAKeylessGet()
    {
        var (client, _, seen) = Client(HttpStatusCode.OK, $$"""{"id":"{{JobId}}","status":"submitted","issueNumber":12,"attachments":[]}""");
        Assert.Equal(new FeedbackJob(JobId, FeedbackJobState.Submitted, 12), await client.GetFeedbackStatusAsync(JobId));
        var sent = Assert.Single(seen);
        Assert.Equal(HttpMethod.Get, sent.Method);
        Assert.Equal($"https://festivalscoretracker.com/api/feedback/{JobId}", sent.Uri.ToString());
        Assert.DoesNotContain(sent.Headers.Keys, k => k.Equals("X-API-Key", StringComparison.OrdinalIgnoreCase) ||
                                                      k.StartsWith("x-fst-selected-", StringComparison.OrdinalIgnoreCase));

        await Assert.ThrowsAsync<ArgumentException>(() => client.GetFeedbackStatusAsync("../features"));
        Assert.Single(seen);

        var (gone, _, _) = Client(HttpStatusCode.NotFound, """{"error":"x","code":"not_found"}""");
        Assert.Equal(404, (await Assert.ThrowsAsync<FestivalApiException>(() => gone.GetFeedbackStatusAsync(JobId))).StatusCode);

        var (garbled, _, _) = Client(HttpStatusCode.OK, "nope");
        Assert.Equal(FestivalApiErrorKind.InvalidResponse,
            (await Assert.ThrowsAsync<FestivalApiException>(() => garbled.GetFeedbackStatusAsync(JobId))).Kind);
    }

    [Theory]
    [InlineData("""{"appManual":false,"feedback":true}""", true)]
    [InlineData("""{"appManual":false,"feedback":false}""", false)]
    [InlineData("""{"appManual":false}""", false)]
    [InlineData("""{"feedback":"true"}""", false)]
    [InlineData("""[true]""", false)]
    [InlineData("""not json""", false)]
    public async Task Features_ShowFeedbackOnlyForTrue(string body, bool expected)
    {
        var (client, _, seen) = Client(HttpStatusCode.OK, body);
        Assert.Equal(expected, await client.GetFeedbackEnabledAsync());
        var sent = Assert.Single(seen);
        Assert.Equal(HttpMethod.Get, sent.Method);
        Assert.Equal("https://festivalscoretracker.com/api/features", sent.Uri.ToString());
    }

    [Fact]
    public async Task Features_FailureThrows()
    {
        var (client, _, _) = Client(HttpStatusCode.ServiceUnavailable);
        await Assert.ThrowsAsync<FestivalApiException>(() => client.GetFeedbackEnabledAsync());
    }

    [Fact]
    public async Task Submit_MapsTransportFailures()
    {
        var (offline, _, _) = Client(HttpStatusCode.OK,
            failure: new HttpRequestException(HttpRequestError.ConnectionError, "down"));
        Assert.Equal(FeedbackException.Offline().Message,
            (await Assert.ThrowsAsync<FeedbackException>(() => offline.SubmitFeedbackAsync(Submission(), Open))).Message);

        var (secure, _, _) = Client(HttpStatusCode.OK,
            failure: new HttpRequestException(HttpRequestError.SecureConnectionError, "tls"));
        Assert.Equal(FestivalApiException.Describe(FestivalApiErrorKind.InvalidResponse, null),
            (await Assert.ThrowsAsync<FeedbackException>(() => secure.SubmitFeedbackAsync(Submission(), Open))).Message);
    }

    [Fact]
    public async Task Submit_MapsTimeoutAndPassesCallerCancellation()
    {
        var (timedOut, _, _) = Client(HttpStatusCode.OK, failure: new TaskCanceledException("deadline"));
        Assert.Equal(FeedbackException.TimedOut().Message,
            (await Assert.ThrowsAsync<FeedbackException>(() => timedOut.SubmitFeedbackAsync(Submission(), Open))).Message);

        var handler = new FakeHandler
        {
            Responder = async (_, token) =>
            {
                await Task.Delay(Timeout.Infinite, token);
                return new HttpResponseMessage(HttpStatusCode.OK);
            },
        };
        var client = new FestivalApiClient(new RequestGate(new HttpClient(handler)), new Uri(Wire.BaseUrl));
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(50));
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => client.SubmitFeedbackAsync(Submission(), Open, cts.Token));
    }

    [Fact]
    public async Task Submit_ReportsUnreadableAttachmentWithoutSending()
    {
        var (client, handler, _) = Client(HttpStatusCode.Created);
        var opened = new List<MemoryStream>();
        var error = await Assert.ThrowsAsync<FeedbackException>(() => client.SubmitFeedbackAsync(
            Submission(Media("ok"), new FeedbackAttachment("gone", "gone.png", "image/png", 1)),
            a =>
            {
                if (a.Id == "gone") throw new FileNotFoundException();
                var stream = new MemoryStream([1]);
                opened.Add(stream);
                return stream;
            }));
        Assert.Equal("\"gone.png\" couldn't be read. Remove it and try again.", error.Message);
        Assert.Empty(handler.Requests);
        Assert.Throws<ObjectDisposedException>(() => opened.Single().ReadByte());
    }
    #endregion

    #region View model
    private static FeedbackFormViewModel Form(
        FeedbackKind kind,
        Func<FeedbackSubmission, CancellationToken, Task<FeedbackJob>> send,
        Func<string, CancellationToken, Task<FeedbackJob>>? status = null,
        Func<DateTimeOffset>? now = null) =>
        new(kind, send, status ?? ((id, _) => Task.FromResult(new FeedbackJob(id, FeedbackJobState.Submitted, 42))),
            "2610.02.01", "Windows 11",
            (_, token) =>
            {
                token.ThrowIfCancellationRequested();
                return Task.CompletedTask;
            },
            now);

    private static Task<FeedbackJob> Accepted() => Task.FromResult(new FeedbackJob(JobId, FeedbackJobState.Queued));

    private static FeedbackFormViewModel Filled(FeedbackFormViewModel form)
    {
        form.Title = form.Kind == FeedbackKind.Bug ? "[Bug] Crash" : "Idea";
        form.Description = "Boom";
        return form;
    }

    [Fact]
    public void Form_StartsCleanWithCopy()
    {
        var form = Form(FeedbackKind.Bug, (_, _) => throw new InvalidOperationException());
        Assert.Equal("[Bug] ", form.Title);
        Assert.Equal("Report an Issue", form.FormTitle);
        Assert.True(form.HasBugFields);
        Assert.Equal(FeedbackCopy.TitleHelp(FeedbackKind.Bug), form.TitleHelp);
        Assert.Equal(FeedbackCopy.DescriptionHelp(FeedbackKind.Bug), form.DescriptionHelp);
        Assert.Equal("Sending your report…", form.SendingText);
        Assert.Equal(("Submit", "Cancel"), (form.PrimaryText, form.CloseText));
        Assert.True(form.IsEditing);
        Assert.True(form.RequestClose());
        Assert.False(form.ConfirmingDiscard);
    }

    [Fact]
    public async Task Form_ValidatesOnSubmitWithoutSending()
    {
        var calls = 0;
        var form = Form(FeedbackKind.Feature, (_, _) => { calls++; return Accepted(); });
        await form.SubmitAsync();
        Assert.Equal("Add a title after the prefix.", form.Error);
        Assert.True(form.HasError);
        form.Title = "[Feature] Dark mode";
        Assert.Null(form.Error);
        await form.SubmitAsync();
        Assert.Equal("Add a description.", form.Error);
        Assert.Equal(0, calls);
    }

    [Fact]
    public async Task Form_DirtyCloseAsksThenKeepEditingOrDiscard()
    {
        var form = Form(FeedbackKind.Bug, (_, _) => Accepted());
        form.ReproSteps = "1. Open";
        form.ExpectedBehavior = "Works";
        Assert.False(form.RequestClose());
        Assert.True(form.ConfirmingDiscard);
        form.KeepEditing();
        Assert.False(form.ConfirmingDiscard);
        Assert.Equal("1. Open", form.ReproSteps);
        Assert.Equal("Works", form.ExpectedBehavior);
        Assert.False(form.RequestClose());
        form.ConfirmDiscard();
        Assert.False(form.ConfirmingDiscard);
        await Task.CompletedTask;
    }

    [Fact]
    public async Task Form_SubmitsPollsAndShowsIssueNumber()
    {
        FeedbackSubmission? sent = null;
        var polls = new Queue<FeedbackJob>([
            new(JobId, FeedbackJobState.Queued), new(JobId, FeedbackJobState.Processing), new(JobId, FeedbackJobState.Submitted, 42),
        ]);
        var captions = new List<string>();
        var form = Form(FeedbackKind.Bug, (s, _) =>
        {
            sent = s;
            return Accepted();
        }, (id, _) =>
        {
            Assert.Equal(JobId, id);
            return Task.FromResult(polls.Dequeue());
        });
        form.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == nameof(FeedbackFormViewModel.SendingText)) captions.Add(form.SendingText);
        };
        form.Title = "[Bug] Crash";
        form.Description = "Boom";
        form.AddAttachments([Media("a")]);
        await form.SubmitAsync();
        Assert.Empty(polls);
        Assert.Equal(["Sending your report…", "Filing your report on GitHub…", "Sending your report…"], captions);
        Assert.True(form.IsSent);
        Assert.False(form.IsSubmitting);
        Assert.Equal(new FeedbackJob(JobId, FeedbackJobState.Submitted, 42), form.Job);
        Assert.Equal("Thanks! Your report was filed as issue #42.", form.SuccessMessage);
        Assert.Equal(("", "Done"), (form.PrimaryText, form.CloseText));
        Assert.Equal("windows", sent!.Platform);
        Assert.Equal("2610.02.01", sent.AppVersion);
        Assert.Equal("Windows 11", sent.ClientInfo);
        Assert.Single(sent.Attachments);
        Assert.True(form.RequestClose());

        form.Title = "ignored after send";
        form.AddAttachments([Media("b")]);
        form.RemoveAttachment("a");
        await form.SubmitAsync();
        Assert.Equal("[Bug] Crash", form.Title);
        Assert.Single(form.Attachments);
    }

    [Fact]
    public async Task Form_FailureKeepsInputAndShowsError()
    {
        var form = Form(FeedbackKind.Feature, (_, _) => throw FeedbackException.ForStatus(503, "feedback_busy"));
        form.Title = "Idea";
        form.Description = "More";
        await form.SubmitAsync();
        Assert.True(form.IsEditing);
        Assert.Equal("Feedback is busy right now. Try again in a minute.", form.Error);
        Assert.Equal("Idea", form.Title);

        var crash = Form(FeedbackKind.Feature, (_, _) => throw new InvalidOperationException("raw"));
        crash.Title = "Idea";
        crash.Description = "More";
        await crash.SubmitAsync();
        Assert.Equal(FeedbackException.Offline().Message, crash.Error);
    }

    [Fact]
    public async Task Form_SubmittingLocksFieldsAndDiscardCancelsUpload()
    {
        var started = new TaskCompletionSource();
        CancellationToken seen = default;
        var form = Form(FeedbackKind.Bug, async (_, token) =>
        {
            seen = token;
            started.SetResult();
            await Task.Delay(Timeout.Infinite, token);
            return new FeedbackJob(JobId, FeedbackJobState.Queued);
        });
        form.Title = "[Bug] X";
        form.Description = "Y";
        var submitting = form.SubmitAsync();
        await started.Task;
        Assert.True(form.IsSubmitting);
        form.Description = "changed";
        Assert.Equal("Y", form.Description);
        await form.SubmitAsync();
        Assert.False(form.RequestClose());
        Assert.True(form.ConfirmingDiscard);
        form.ConfirmDiscard();
        await submitting;
        Assert.True(seen.IsCancellationRequested);
        Assert.Null(form.Error);
        Assert.False(form.IsSent);
    }

    [Fact]
    public async Task Form_DiscardDuringFailingUploadShowsNoError()
    {
        var started = new TaskCompletionSource();
        var release = new TaskCompletionSource();
        var form = Form(FeedbackKind.Bug, async (_, _) =>
        {
            started.SetResult();
            await release.Task;
            throw FeedbackException.Offline();
        });
        form.Title = "[Bug] X";
        form.Description = "Y";
        var submitting = form.SubmitAsync();
        await started.Task;
        form.ConfirmDiscard();
        release.SetResult();
        await submitting;
        Assert.Null(form.Error);

        var late = new TaskCompletionSource();
        var lateForm = Form(FeedbackKind.Bug, async (_, _) =>
        {
            await late.Task;
            return new FeedbackJob(JobId, FeedbackJobState.Queued);
        });
        lateForm.Title = "[Bug] X";
        lateForm.Description = "Y";
        var lateSubmit = lateForm.SubmitAsync();
        lateForm.ConfirmDiscard();
        late.SetResult();
        await lateSubmit;
        Assert.False(lateForm.IsSent);
    }

    [Fact]
    public void Form_AttachmentsAddRemoveAndNotice()
    {
        var form = Form(FeedbackKind.Feature, (_, _) => Accepted());
        var changed = new List<string?>();
        form.PropertyChanged += (_, e) => changed.Add(e.PropertyName);
        form.AddAttachments([]);
        Assert.Empty(changed);
        form.AddAttachments([Media("a"), Media("b"), new FeedbackAttachment("t", "t.txt", "text/plain", 1)]);
        Assert.Equal(["a", "b"], form.Attachments.Select(a => a.Id));
        Assert.True(form.HasAttachments);
        Assert.Equal("Only images and videos can be attached.", form.Notice);
        Assert.True(form.HasNotice);
        Assert.False(form.RequestClose());
        form.KeepEditing();
        form.RemoveAttachment("missing");
        Assert.Equal(2, form.Attachments.Count);
        form.RemoveAttachment("a");
        Assert.Equal(["b"], form.Attachments.Select(a => a.Id));
        Assert.Null(form.Notice);
        form.RemoveAttachment("b");
        Assert.False(form.HasAttachments);
        Assert.True(form.RequestClose());
        Assert.Contains(nameof(FeedbackFormViewModel.HasAttachments), changed);
        Assert.Equal(form.Draft.Attachments, form.Attachments);
    }

    [Fact]
    public void Form_NullFieldValuesBecomeEmpty()
    {
        var form = Form(FeedbackKind.Bug, (_, _) => Accepted());
        form.Title = null!;
        form.Description = null!;
        form.ReproSteps = null!;
        form.ExpectedBehavior = null!;
        Assert.Equal("", form.Title);
        Assert.Equal(FeedbackKind.Bug, form.Kind);
        Assert.False(form.IsSubmitting);
        Assert.Null(form.Job);
        Assert.Equal("", form.SuccessMessage);
    }

    [Fact]
    public async Task Form_FailedFilingKeepsInputForRetry()
    {
        var form = Filled(Form(FeedbackKind.Bug, (_, _) => Accepted(),
            (id, _) => Task.FromResult(new FeedbackJob(id, FeedbackJobState.Failed))));
        await form.SubmitAsync();
        Assert.True(form.IsEditing);
        Assert.Equal("Your report couldn't be filed on GitHub. Try again in a few minutes.", form.Error);
        Assert.Equal("[Bug] Crash", form.Title);
        Assert.Equal("", form.SuccessMessage);
    }

    [Fact]
    public async Task Form_UnknownOutcomeReportsReceived()
    {
        var expired = Filled(Form(FeedbackKind.Bug, (_, _) => Accepted(),
            (_, _) => throw new FestivalApiException(FestivalApiErrorKind.HttpStatus, 404)));
        await expired.SubmitAsync();
        Assert.True(expired.IsSent);
        Assert.Equal("Thanks! Your report was received and will be filed on GitHub shortly.", expired.SuccessMessage);

        var statusCalls = 0;
        var noId = Filled(Form(FeedbackKind.Feature, (_, _) => Task.FromResult(new FeedbackJob(null, FeedbackJobState.Queued)),
            (_, _) => { statusCalls++; return Accepted(); }));
        await noId.SubmitAsync();
        Assert.True(noId.IsSent);
        Assert.Equal(0, statusCalls);
        Assert.Equal("Thanks! Your request was received and will be filed on GitHub shortly.", noId.SuccessMessage);

        var immediate = Filled(Form(FeedbackKind.Feature, (_, _) => Task.FromResult(new FeedbackJob(JobId, FeedbackJobState.Submitted, 5)),
            (_, _) => { statusCalls++; return Accepted(); }));
        await immediate.SubmitAsync();
        Assert.Equal(0, statusCalls);
        Assert.Equal("Thanks! Your request was filed as issue #5.", immediate.SuccessMessage);
    }

    [Fact]
    public async Task Form_PollingStopsAtTheDeadline()
    {
        var clock = DateTimeOffset.UnixEpoch;
        var calls = 0;
        var form = Filled(Form(FeedbackKind.Bug, (_, _) => Accepted(), (id, _) =>
        {
            calls++;
            clock += TimeSpan.FromMinutes(1);
            return Task.FromResult(new FeedbackJob(id, FeedbackJobState.Processing, null, 1));
        }, () => clock));
        await form.SubmitAsync();
        Assert.Equal((int)FeedbackFormViewModel.PollTimeout.TotalMinutes, calls);
        Assert.True(form.IsSent);
        Assert.Equal("Thanks! Your report was received and will be filed on GitHub shortly. 1 attachment couldn't be attached.",
            form.SuccessMessage);
    }

    [Fact]
    public async Task Form_ClosingWhileFilingStopsPollingWithoutAsking()
    {
        var polling = new TaskCompletionSource();
        CancellationToken seen = default;
        var form = Filled(Form(FeedbackKind.Bug, (_, _) => Accepted(), async (id, token) =>
        {
            seen = token;
            polling.TrySetResult();
            await Task.Delay(Timeout.Infinite, token);
            return new FeedbackJob(id, FeedbackJobState.Submitted);
        }));
        var submitting = form.SubmitAsync();
        await polling.Task;
        Assert.Equal(FeedbackPhase.Filing, form.Phase);
        Assert.True(form.IsSubmitting);
        Assert.True(form.RequestClose());
        Assert.False(form.ConfirmingDiscard);
        await submitting;
        Assert.True(seen.IsCancellationRequested);
        Assert.Null(form.Error);
        Assert.False(form.IsSent);
    }
    #endregion
}
