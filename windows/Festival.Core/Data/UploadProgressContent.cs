using System.Net;

namespace Festival.Core.Data;

#region Upload progress content
/// <summary>
/// Wraps a request body and reports the fraction of it written to the connection (issue #634: the feedback form's
/// determinate "Uploading Media" bar). The headers (multipart boundary) are the inner content's; the length is the inner
/// content's computed length, and without one only completion (1) is reported. Reports rise in steps of at least
/// <see cref="Step"/> so a large video doesn't flood the UI thread, and always end with 1 once the body is written.
/// </summary>
public sealed class UploadProgressContent : HttpContent
{
    /// <summary>Smallest rise in the reported fraction between two reports (1 %).</summary>
    public const double Step = 0.01;

    private readonly HttpContent inner;
    private readonly IProgress<double> progress;

    /// <summary>Wraps a body.</summary>
    /// <param name="inner">Body to send (owned: disposed with this content).</param>
    /// <param name="progress">Receives fractions in [0, 1], on the sending thread.</param>
    public UploadProgressContent(HttpContent inner, IProgress<double> progress)
    {
        this.inner = inner;
        this.progress = progress;
        foreach (var header in inner.Headers)
        {
            if (!string.Equals(header.Key, "Content-Length", StringComparison.OrdinalIgnoreCase))
                Headers.TryAddWithoutValidation(header.Key, header.Value);
        }
    }

    /// <inheritdoc />
    protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) =>
        SerializeToStreamAsync(stream, context, CancellationToken.None);

    /// <inheritdoc />
    protected override async Task SerializeToStreamAsync(Stream stream, TransportContext? context, CancellationToken cancellationToken)
    {
        var counter = new CountingStream(stream, inner.Headers.ContentLength, progress);
        progress.Report(0);
        await inner.CopyToAsync(counter, context, cancellationToken).ConfigureAwait(false);
        if (counter.Reported < 1) progress.Report(1);
    }

    /// <inheritdoc />
    protected override bool TryComputeLength(out long length)
    {
        var known = inner.Headers.ContentLength;
        length = known ?? 0;
        return known.HasValue;
    }

    /// <inheritdoc />
    protected override void Dispose(bool disposing)
    {
        if (disposing) inner.Dispose();
        base.Dispose(disposing);
    }

    #region Counting stream
    /// <summary>Write-only pass-through that counts bytes and reports the written fraction.</summary>
    /// <param name="target">Connection stream (not owned).</param>
    /// <param name="total">Body length, or <see langword="null"/> when unknown.</param>
    /// <param name="progress">Receives fractions.</param>
    private sealed class CountingStream(Stream target, long? total, IProgress<double> progress) : Stream
    {
        private long written;
        private double reported;

        /// <summary>Last fraction reported.</summary>
        public double Reported => reported;

        public override bool CanRead => false;
        public override bool CanSeek => false;
        public override bool CanWrite => true;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => written; set => throw new NotSupportedException(); }
        public override void Flush() => target.Flush();
        public override Task FlushAsync(CancellationToken cancellationToken) => target.FlushAsync(cancellationToken);
        public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();

        public override void Write(byte[] buffer, int offset, int count)
        {
            target.Write(buffer, offset, count);
            Count(count);
        }

        public override void Write(ReadOnlySpan<byte> buffer)
        {
            target.Write(buffer);
            Count(buffer.Length);
        }

        public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken) =>
            WriteAsync(buffer.AsMemory(offset, count), cancellationToken).AsTask();

        public override async ValueTask WriteAsync(ReadOnlyMemory<byte> buffer, CancellationToken cancellationToken = default)
        {
            await target.WriteAsync(buffer, cancellationToken).ConfigureAwait(false);
            Count(buffer.Length);
        }

        /// <summary>Adds written bytes and reports when the fraction rose by at least <see cref="Step"/>.</summary>
        /// <param name="count">Bytes just written.</param>
        private void Count(int count)
        {
            written += count;
            if (total is not > 0) return;
            var fraction = Math.Min(1, (double)written / total.Value);
            if (fraction - reported < Step && fraction < 1) return;
            reported = fraction;
            progress.Report(fraction);
        }
    }
    #endregion
}
#endregion
