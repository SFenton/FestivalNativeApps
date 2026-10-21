using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Festival.Core.Threading;

#region Context
/// <summary>
/// Wraps the UI thread's <see cref="SynchronizationContext"/> so a blocking wait on that thread does not pump window
/// messages (issue #680).
/// </summary>
/// <remarks>
/// <para>
/// The CLR makes a contended wait on an STA thread pump messages (<c>CoWaitForMultipleHandles</c>). When that wait happens
/// inside WinUI's re-entrancy-protected frame tick (layout, x:Bind <c>ProcessBindings</c>, render callbacks), the pumped
/// dispatcher timer re-enters XAML and WinUI fail-fasts the process with <c>0xC000027B</c> / <c>E_UNEXPECTED</c>
/// (<c>CXcpDispatcher::OnReentrancyProtectedWindowMessage</c>; microsoft/microsoft-ui-xaml#11099, #8501). The app
/// cannot avoid every such wait: CsWinRT's global event-source lock is taken whenever generated x:Bind code removes a
/// <c>DataContextChanged</c> handler, and the finalizer thread holds it while it releases event subscriptions.
/// </para>
/// <para>
/// Setting <see cref="SynchronizationContext.SetWaitNotificationRequired"/> routes every <see cref="WaitHandle"/> wait on
/// this thread (including <see cref="ReaderWriterLockSlim"/> contention) through <see cref="Wait"/>, which blocks without
/// dispatching messages, as WPF's dispatcher does during layout and as UWP's ASTA UI threads always did. Lock holders on
/// other threads never need the UI thread to release these locks, so the wait ends when they do.
/// </para>
/// </remarks>
public sealed class NonReentrantWaitContext : SynchronizationContext
{
    /// <summary>Blocks until the handles are signalled or the timeout elapses, returning a Win32 wait result.</summary>
    /// <param name="waitHandles">Native wait handles.</param>
    /// <param name="waitAll">Whether every handle must be signalled.</param>
    /// <param name="millisecondsTimeout">Timeout in milliseconds, or <see cref="Timeout.Infinite"/>.</param>
    /// <returns><c>WAIT_OBJECT_0 + n</c>, <c>WAIT_ABANDONED_0 + n</c> or <c>WAIT_TIMEOUT</c>.</returns>
    public delegate int WaitFunction(IntPtr[] waitHandles, bool waitAll, int millisecondsTimeout);

    private readonly SynchronizationContext inner;
    private readonly WaitFunction wait;

    /// <summary>Wraps <paramref name="inner"/>, waiting with <paramref name="wait"/> (default: a non-pumping Win32 wait).</summary>
    /// <param name="inner">The context that receives posted and sent work (the UI thread's dispatcher context).</param>
    /// <param name="wait">The wait used for this thread's blocking waits; <see langword="null"/> uses <see cref="WaitWithoutPumping"/>.</param>
    public NonReentrantWaitContext(SynchronizationContext inner, WaitFunction? wait = null)
    {
        ArgumentNullException.ThrowIfNull(inner);
        this.inner = inner;
        this.wait = wait ?? WaitWithoutPumping;
        SetWaitNotificationRequired();
    }

    /// <summary>Installs the wrapper around the calling thread's current context, once.</summary>
    /// <returns>The installed context, or <see langword="null"/> when the thread has no context to wrap.</returns>
    public static NonReentrantWaitContext? InstallOnCurrentThread()
    {
        var current = Current;
        if (current is NonReentrantWaitContext installed)
            return installed;
        if (current is null)
            return null;
        var context = new NonReentrantWaitContext(current);
        SetSynchronizationContext(context);
        return context;
    }

    /// <inheritdoc/>
    public override void Post(SendOrPostCallback d, object? state) => inner.Post(d, state);

    /// <inheritdoc/>
    public override void Send(SendOrPostCallback d, object? state) => inner.Send(d, state);

    /// <inheritdoc/>
    public override void OperationStarted() => inner.OperationStarted();

    /// <inheritdoc/>
    public override void OperationCompleted() => inner.OperationCompleted();

    /// <inheritdoc/>
    public override SynchronizationContext CreateCopy() => new NonReentrantWaitContext(inner.CreateCopy(), wait);

    /// <inheritdoc/>
    public override int Wait(IntPtr[] waitHandles, bool waitAll, int millisecondsTimeout)
    {
        ArgumentNullException.ThrowIfNull(waitHandles);
        return wait(waitHandles, waitAll, millisecondsTimeout);
    }

    /// <summary>Waits with <c>WaitForMultipleObjectsEx</c>, non-alertable, so no message or APC is dispatched meanwhile.</summary>
    /// <param name="waitHandles">Native wait handles.</param>
    /// <param name="waitAll">Whether every handle must be signalled.</param>
    /// <param name="millisecondsTimeout">Timeout in milliseconds, or <see cref="Timeout.Infinite"/>.</param>
    /// <returns>The Win32 wait result.</returns>
    /// <exception cref="Win32Exception">The wait failed (for example, an invalid handle).</exception>
    public static int WaitWithoutPumping(IntPtr[] waitHandles, bool waitAll, int millisecondsTimeout)
    {
        ArgumentNullException.ThrowIfNull(waitHandles);
        var result = WaitForMultipleObjectsEx((uint)waitHandles.Length, waitHandles, waitAll ? 1 : 0, unchecked((uint)millisecondsTimeout), 0);
        if (result == WaitFailed)
            throw new Win32Exception(Marshal.GetLastPInvokeError());
        return (int)result;
    }

    private const uint WaitFailed = 0xFFFFFFFF;

    [DllImport("kernel32.dll", SetLastError = true, ExactSpelling = true)]
    private static extern uint WaitForMultipleObjectsEx(uint count, IntPtr[] handles, int waitAll, uint milliseconds, int alertable);
}
#endregion
