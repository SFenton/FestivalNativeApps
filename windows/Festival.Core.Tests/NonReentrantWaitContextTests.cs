using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using Festival.Core.Threading;

namespace Festival.Core.Tests;

[SupportedOSPlatform("windows")]
public class NonReentrantWaitContextTests
{
    private const int WaitTimeout = 0x102;

    #region Delegation
    private sealed class RecordingContext : SynchronizationContext
    {
        public List<string> Calls { get; } = [];
        public override void Post(SendOrPostCallback d, object? state) { Calls.Add("post"); d(state); }
        public override void Send(SendOrPostCallback d, object? state) { Calls.Add("send"); d(state); }
        public override void OperationStarted() => Calls.Add("started");
        public override void OperationCompleted() => Calls.Add("completed");
        public override SynchronizationContext CreateCopy() { Calls.Add("copy"); return this; }
    }

    [Fact]
    public void Requires_wait_notification_so_waits_reach_it()
    {
        Assert.True(new NonReentrantWaitContext(new SynchronizationContext()).IsWaitNotificationRequired());
    }

    [Fact]
    public void Forwards_posted_and_sent_work_and_operations_to_the_inner_context()
    {
        var inner = new RecordingContext();
        var context = new NonReentrantWaitContext(inner);
        var ran = new List<object?>();

        context.Post(ran.Add, 1);
        context.Send(ran.Add, 2);
        context.OperationStarted();
        context.OperationCompleted();
        var copy = context.CreateCopy();

        Assert.Equal([1, 2], ran);
        Assert.Equal(["post", "send", "started", "completed", "copy"], inner.Calls);
        var wrapped = Assert.IsType<NonReentrantWaitContext>(copy);
        Assert.True(wrapped.IsWaitNotificationRequired());
    }

    [Fact]
    public void Rejects_a_missing_inner_context_or_handle_list()
    {
        Assert.Throws<ArgumentNullException>(() => new NonReentrantWaitContext(null!));
        Assert.Throws<ArgumentNullException>(() => new NonReentrantWaitContext(new SynchronizationContext()).Wait(null!, false, 0));
        Assert.Throws<ArgumentNullException>(() => NonReentrantWaitContext.WaitWithoutPumping(null!, false, 0));
    }

    [Fact]
    public void Installs_once_around_the_current_context_and_never_without_one()
    {
        var results = RunOnThread(ApartmentState.MTA, () =>
        {
            var none = NonReentrantWaitContext.InstallOnCurrentThread();
            var inner = new RecordingContext();
            SynchronizationContext.SetSynchronizationContext(inner);
            var first = NonReentrantWaitContext.InstallOnCurrentThread();
            var second = NonReentrantWaitContext.InstallOnCurrentThread();
            first?.Post(_ => { }, null);
            return (none, first, second, current: SynchronizationContext.Current, inner.Calls);
        });

        Assert.Null(results.none);
        Assert.NotNull(results.first);
        Assert.Same(results.first, results.second);
        Assert.Same(results.first, results.current);
        Assert.Equal(["post"], results.Calls);
    }
    #endregion

    #region Waiting
    [Fact]
    public void Routes_a_contended_reader_writer_lock_wait_through_its_wait()
    {
        // The #680 crash path: CsWinRT's EventSourceCache write lock contended by the finalizer thread.
        using var gate = new ReaderWriterLockSlim();
        var calls = 0;
        var held = new ManualResetEventSlim();
        var holder = new Thread(() =>
        {
            gate.EnterWriteLock();
            held.Set();
            Thread.Sleep(200);
            gate.ExitWriteLock();
        });
        holder.Start();
        held.Wait();

        var entered = RunOnThread(ApartmentState.MTA, () =>
        {
            SynchronizationContext.SetSynchronizationContext(new NonReentrantWaitContext(new SynchronizationContext(), (handles, all, timeout) =>
            {
                Interlocked.Increment(ref calls);
                return NonReentrantWaitContext.WaitWithoutPumping(handles, all, timeout);
            }));
            gate.EnterWriteLock();
            gate.ExitWriteLock();
            return true;
        });
        holder.Join();

        Assert.True(entered);
        Assert.True(calls > 0);
    }

    [Fact]
    public void Returns_the_signalled_index_or_a_timeout()
    {
        using var first = new ManualResetEvent(false);
        using var second = new ManualResetEvent(true);
        IntPtr[] handles = [first.SafeWaitHandle.DangerousGetHandle(), second.SafeWaitHandle.DangerousGetHandle()];

        Assert.Equal(1, NonReentrantWaitContext.WaitWithoutPumping(handles, waitAll: false, 0));
        Assert.Equal(WaitTimeout, NonReentrantWaitContext.WaitWithoutPumping(handles, waitAll: true, 10));
        first.Set();
        Assert.Equal(0, NonReentrantWaitContext.WaitWithoutPumping(handles, waitAll: true, Timeout.Infinite));
    }

    [Fact]
    public void Throws_for_an_invalid_handle()
    {
        Assert.Throws<Win32Exception>(() => NonReentrantWaitContext.WaitWithoutPumping([new IntPtr(0x7FFFFFF0)], false, 0));
    }

    [Fact]
    public void Keeps_wait_handle_semantics_for_timeouts_and_abandoned_mutexes()
    {
        var mutex = new Mutex();
        var owner = new Thread(() => mutex.WaitOne());
        owner.Start();
        owner.Join();

        var outcome = RunOnThread(ApartmentState.MTA, () =>
        {
            SynchronizationContext.SetSynchronizationContext(new NonReentrantWaitContext(new SynchronizationContext()));
            using var unsignalled = new ManualResetEvent(false);
            var timedOut = !unsignalled.WaitOne(10);
            try
            {
                mutex.WaitOne();
                return (timedOut, abandoned: false);
            }
            catch (AbandonedMutexException)
            {
                return (timedOut, abandoned: true);
            }
        });
        mutex.Dispose();

        Assert.True(outcome.timedOut);
        Assert.True(outcome.abandoned);
    }

    [Theory]
    [InlineData(false, true)]
    [InlineData(true, false)]
    public void A_contended_wait_on_an_sta_thread_dispatches_sent_messages_only_without_the_context(bool install, bool expectDispatched)
    {
        // A message sent to the waiting thread's window stands in for WinUI's dispatcher timer: if the wait pumps, the
        // message runs mid-wait (the re-entrancy that fail-fasts WinUI); if not, it waits until the lock is free.
        using var gate = new ReaderWriterLockSlim();
        var held = new ManualResetEventSlim();
        var ready = new ManualResetEventSlim();
        var release = new ManualResetEventSlim();
        var window = IntPtr.Zero;
        var holder = new Thread(() =>
        {
            gate.EnterWriteLock();
            held.Set();
            release.Wait();
            gate.ExitWriteLock();
        });
        holder.Start();
        held.Wait();

        var waiter = new Thread(() =>
        {
            window = CreateWindowExW(0, "STATIC", null, 0, 0, 0, 0, 0, HwndMessage, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
            if (install)
                SynchronizationContext.SetSynchronizationContext(new NonReentrantWaitContext(new SynchronizationContext()));
            ready.Set();
            gate.EnterWriteLock();
            gate.ExitWriteLock();
            DestroyWindow(window);
        });
        waiter.SetApartmentState(ApartmentState.STA);
        waiter.Start();
        ready.Wait();
        Thread.Sleep(200);

        var dispatched = SendMessageTimeoutW(window, WmNull, IntPtr.Zero, IntPtr.Zero, SmtoNormal, 1000, out _) != IntPtr.Zero;
        release.Set();
        holder.Join();
        waiter.Join();

        Assert.NotEqual(IntPtr.Zero, window);
        Assert.Equal(expectDispatched, dispatched);
    }
    #endregion

    #region Helpers
    private static T RunOnThread<T>(ApartmentState apartment, Func<T> body)
    {
        T result = default!;
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try { result = body(); }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(apartment);
        thread.Start();
        thread.Join();
        if (failure is not null)
            throw new InvalidOperationException("Thread body failed", failure);
        return result;
    }

    private static readonly IntPtr HwndMessage = new(-3);
    private const uint WmNull = 0;
    private const uint SmtoNormal = 0;

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowExW(uint exStyle, string className, string? windowName, uint style, int x, int y,
        int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr param);

    [DllImport("user32.dll")]
    private static extern bool DestroyWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessageTimeoutW(IntPtr window, uint message, IntPtr wParam, IntPtr lParam, uint flags,
        uint timeout, out IntPtr result);
    #endregion
}
