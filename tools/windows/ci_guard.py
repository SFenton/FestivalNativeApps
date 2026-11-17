#!/usr/bin/env python3
"""Run one Windows UI CI task inside a bounded Windows job object (issue #700).

``ci_ui.py`` used to run each task with a plain ``subprocess.run`` and no limit. When a shard's task ran away on the
hosted runner (release run 44079233807: ``windows-ui-journeys (3/4)`` ran 55 minutes instead of about 17 until GitHub
reported "The hosted runner lost communication with the server"), nothing bounded it, so the job lost its log, its
screenshots and its artifact. :func:`run_task` puts the task and everything it starts (the app, the FstUia driver,
fixture services) in one job object and ends that tree when the task

* runs longer than its wall-clock limit (a hang), or
* drives the runner's available physical memory under a floor (a runaway that would starve the runner),

after first writing the evidence into the task's own folder, which the workflow uploads: every process in the tree and
the runner's largest processes (memory and CPU), a desktop screenshot, and a small dump (threads and stacks) of each app
process. A task that exits normally but leaves processes behind gets them listed and ended too, so a leaked app can't
pile up across tasks.
"""

from __future__ import annotations

import ctypes
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

WINDOWS_TOOLS = Path(__file__).resolve().parent
if str(WINDOWS_TOOLS) not in sys.path:
    sys.path.insert(0, str(WINDOWS_TOOLS))  # crash_dump, when imported as tools.windows.ci_guard
#: Executable whose processes get a small dump before a killed task's tree ends.
APP_EXE = "FestivalScoreTracker.exe"
#: Seconds between checks of the task's time and the runner's memory.
POLL_SECONDS = 2.0


# region Win32 job object


if sys.platform == "win32":
    from ctypes import wintypes

    class _BasicLimit(ctypes.Structure):
        _fields_ = [("PerProcessUserTimeLimit", ctypes.c_int64), ("PerJobUserTimeLimit", ctypes.c_int64),
                    ("LimitFlags", wintypes.DWORD), ("MinimumWorkingSetSize", ctypes.c_size_t),
                    ("MaximumWorkingSetSize", ctypes.c_size_t), ("ActiveProcessLimit", wintypes.DWORD),
                    ("Affinity", ctypes.c_size_t), ("PriorityClass", wintypes.DWORD),
                    ("SchedulingClass", wintypes.DWORD)]

    class _ExtendedLimit(ctypes.Structure):
        _fields_ = [("BasicLimitInformation", _BasicLimit), ("IoInfo", ctypes.c_uint64 * 6),
                    ("ProcessMemoryLimit", ctypes.c_size_t), ("JobMemoryLimit", ctypes.c_size_t),
                    ("PeakProcessMemoryUsed", ctypes.c_size_t), ("PeakJobMemoryUsed", ctypes.c_size_t)]

    class _MemoryStatus(ctypes.Structure):
        _fields_ = [("dwLength", wintypes.DWORD), ("dwMemoryLoad", wintypes.DWORD),
                    ("ullTotalPhys", ctypes.c_uint64), ("ullAvailPhys", ctypes.c_uint64),
                    ("ullTotalPageFile", ctypes.c_uint64), ("ullAvailPageFile", ctypes.c_uint64),
                    ("ullTotalVirtual", ctypes.c_uint64), ("ullAvailVirtual", ctypes.c_uint64),
                    ("ullAvailExtendedVirtual", ctypes.c_uint64)]

    class _MemoryCounters(ctypes.Structure):
        _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t), ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t), ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t), ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t), ("PeakPagefileUsage", ctypes.c_size_t),
                    ("PrivateUsage", ctypes.c_size_t)]

    _kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _psapi = ctypes.WinDLL("psapi", use_last_error=True)
    _kernel32.CreateJobObjectW.restype = wintypes.HANDLE
    _kernel32.CreateJobObjectW.argtypes = [ctypes.c_void_p, wintypes.LPCWSTR]
    _kernel32.SetInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD]
    _kernel32.QueryInformationJobObject.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD,
                                                    ctypes.c_void_p]
    _kernel32.AssignProcessToJobObject.argtypes = [wintypes.HANDLE, wintypes.HANDLE]
    _kernel32.TerminateJobObject.argtypes = [wintypes.HANDLE, wintypes.UINT]
    _kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    _kernel32.OpenProcess.restype = wintypes.HANDLE
    _kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    _kernel32.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR,
                                                     ctypes.POINTER(wintypes.DWORD)]
    _kernel32.GetProcessTimes.argtypes = [wintypes.HANDLE] + [ctypes.POINTER(ctypes.c_uint64)] * 4
    _kernel32.GlobalMemoryStatusEx.argtypes = [ctypes.POINTER(_MemoryStatus)]
    _psapi.GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(_MemoryCounters), wintypes.DWORD]
    _psapi.EnumProcesses.argtypes = [ctypes.POINTER(wintypes.DWORD), wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]

#: ``JobObjectBasicProcessIdList`` and ``JobObjectExtendedLimitInformation`` information classes.
_PROCESS_ID_LIST, _EXTENDED_LIMIT = 3, 9
#: ``JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE``: the tree ends with the job handle even if this script dies.
_KILL_ON_JOB_CLOSE = 0x2000


class TaskJob:
    """A kill-on-close job object holding one task process and everything it starts (no-op off Windows)."""

    def __init__(self) -> None:
        self.handle = None
        if sys.platform != "win32":
            return
        self.handle = _kernel32.CreateJobObjectW(None, None)
        limit = _ExtendedLimit()
        limit.BasicLimitInformation.LimitFlags = _KILL_ON_JOB_CLOSE
        _kernel32.SetInformationJobObject(self.handle, _EXTENDED_LIMIT, ctypes.byref(limit), ctypes.sizeof(limit))

    def assign(self, proc: subprocess.Popen) -> None:
        """Add the task process; children it starts afterwards join the job too."""
        if self.handle:
            _kernel32.AssignProcessToJobObject(self.handle, int(proc._handle))  # type: ignore[attr-defined]

    def pids(self) -> list[int]:
        """Process IDs currently in the job."""
        if not self.handle:
            return []
        # JOBOBJECT_BASIC_PROCESS_ID_LIST: two DWORD counts (assigned, listed) share the first slot, then the IDs.
        buffer = (ctypes.c_size_t * 1025)()
        if not _kernel32.QueryInformationJobObject(self.handle, _PROCESS_ID_LIST, buffer, ctypes.sizeof(buffer), None):
            return []
        return [int(pid) for pid in buffer[1:1 + min(int(buffer[0]) >> 32, 1024)]]

    def peak_mb(self) -> int:
        """The job's peak committed memory, in MB (0 off Windows)."""
        if not self.handle:
            return 0
        limit = _ExtendedLimit()
        if not _kernel32.QueryInformationJobObject(self.handle, _EXTENDED_LIMIT, ctypes.byref(limit),
                                                   ctypes.sizeof(limit), None):
            return 0
        return limit.PeakJobMemoryUsed // (1 << 20)

    def terminate(self) -> None:
        """End every process in the job."""
        if self.handle:
            _kernel32.TerminateJobObject(self.handle, 1)

    def close(self) -> None:
        """Close the job, ending anything still in it."""
        if self.handle:
            _kernel32.CloseHandle(self.handle)
            self.handle = None


# endregion

# region Diagnostics


def available_mb() -> int:
    """The runner's available physical memory in MB (a large number off Windows, so the guard never fires there)."""
    if sys.platform != "win32":
        return 1 << 30
    status = _MemoryStatus()
    status.dwLength = ctypes.sizeof(status)
    _kernel32.GlobalMemoryStatusEx(ctypes.byref(status))
    return status.ullAvailPhys // (1 << 20)


@dataclass
class ProcessInfo:
    """One process's name and resource use."""

    pid: int
    name: str
    private_mb: int
    working_set_mb: int
    cpu_seconds: float

    def line(self) -> str:
        """``name[pid] private=… MB working set=… MB cpu=… s``."""
        return (f"{self.name}[{self.pid}] private={self.private_mb} MB working set={self.working_set_mb} MB "
                f"cpu={self.cpu_seconds:.0f} s")


def process_info(pid: int) -> ProcessInfo | None:
    """Name, memory and CPU time of ``pid``; ``None`` when it can't be opened (gone, or protected)."""
    if sys.platform != "win32":
        return None
    handle = _kernel32.OpenProcess(0x1000 | 0x0010, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION, VM_READ
    if not handle:
        handle = _kernel32.OpenProcess(0x1000, False, pid)
    if not handle:
        return None
    try:
        name = ctypes.create_unicode_buffer(520)
        size = wintypes.DWORD(520)
        image = name.value if _kernel32.QueryFullProcessImageNameW(handle, 0, name, ctypes.byref(size)) else "?"
        counters = _MemoryCounters()
        counters.cb = ctypes.sizeof(counters)
        _psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb)
        times = [ctypes.c_uint64() for _ in range(4)]
        _kernel32.GetProcessTimes(handle, *[ctypes.byref(t) for t in times])
        return ProcessInfo(pid, Path(image).name, counters.PrivateUsage // (1 << 20),
                           counters.WorkingSetSize // (1 << 20), (times[2].value + times[3].value) / 1e7)
    finally:
        _kernel32.CloseHandle(handle)


def largest_processes(count: int = 8) -> list[ProcessInfo]:
    """The runner's ``count`` processes with the most private memory, to show a starvation outside the task too."""
    if sys.platform != "win32":
        return []
    pids = (wintypes.DWORD * 4096)()
    needed = wintypes.DWORD()
    if not _psapi.EnumProcesses(pids, ctypes.sizeof(pids), ctypes.byref(needed)):
        return []
    infos = [info for pid in pids[:needed.value // ctypes.sizeof(wintypes.DWORD)] if pid
             for info in [process_info(int(pid))] if info]
    return sorted(infos, key=lambda info: -info.private_mb)[:count]


def screenshot(path: Path) -> str:
    """Save the whole desktop to ``path`` (PNG); returns ``"saved"`` or why it failed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    script = ("Add-Type -AssemblyName System.Windows.Forms,System.Drawing;"
              "$b=[System.Windows.Forms.SystemInformation]::VirtualScreen;"
              "$i=New-Object System.Drawing.Bitmap $b.Width,$b.Height;"
              "$g=[System.Drawing.Graphics]::FromImage($i);$g.CopyFromScreen($b.Location,[System.Drawing.Point]::Empty,$b.Size);"
              f"$i.Save('{path}',[System.Drawing.Imaging.ImageFormat]::Png)")
    try:
        result = subprocess.run(["powershell", "-NoProfile", "-Command", script], capture_output=True, text=True,
                                timeout=60)
    except (OSError, subprocess.TimeoutExpired) as error:
        return f"failed: {error}"
    return "saved" if result.returncode == 0 and path.exists() else \
        "failed: " + " ".join((result.stderr or "").split())[-300:]


def evidence(job: TaskJob, out: Path, dumps: bool) -> list[str]:
    """Describe the task's processes and the runner, and keep a screenshot and app dumps in ``out``.

    Args:
        job: The task's job.
        out: The task's folder (uploaded by the workflow).
        dumps: Whether to write a small dump of each app process (only for a task about to be ended).

    Returns:
        Report lines.
    """
    lines = [f"runner available memory: {available_mb()} MB; task peak committed memory: {job.peak_mb()} MB",
             "task processes:"]
    infos = [info for pid in job.pids() for info in [process_info(pid)] if info]
    lines += [f"  {info.line()}" for info in infos] or ["  (none)"]
    lines += ["runner's largest processes:"] + [f"  {info.line()}" for info in largest_processes()]
    if dumps:
        lines.append(f"screenshot: {screenshot(out / 'screenshots' / 'ci-guard.png')}")
        if sys.platform == "win32":
            import crash_dump  # noqa: PLC0415  (Windows-only)

            for info in infos:
                if info.name.lower() == APP_EXE.lower():
                    target = out / "dumps" / f"{info.name}-{info.pid}-small.dmp"
                    lines.append(f"dump {target.name}: {crash_dump.snapshot(info.pid, target)}")
    return lines


# endregion

# region Runner


@dataclass
class TaskResult:
    """How one task ended."""

    returncode: int
    seconds: float
    peak_mb: int
    #: Why the guard ended the task (empty when it exited by itself).
    stopped: str = ""
    #: Report lines for a stopped task or one that left processes running.
    report: list[str] = field(default_factory=list)


def run_task(command: list[str], cwd: Path, log_path: Path, out: Path, timeout: float, min_available_mb: int,
             memory: Callable[[], int] = available_mb) -> TaskResult:
    """Run ``command`` with its output in ``log_path``, ending its whole process tree on a hang or memory runaway.

    Args:
        command: The task command.
        cwd: Working directory.
        log_path: The task's ``command.log``; the guard's report is appended to it.
        out: The task's folder, for the screenshot and dumps.
        timeout: Wall-clock limit in seconds.
        min_available_mb: End the task when the runner's available physical memory falls under this.
        memory: Available-memory probe (tests replace it).

    Returns:
        The exit code (``124`` when the guard ended the task), duration, peak memory and any report.
    """
    job = TaskJob()
    started = time.monotonic()
    stopped = ""
    try:
        with log_path.open("w", encoding="utf-8") as log:
            proc = subprocess.Popen(command, cwd=cwd, stdout=log, stderr=subprocess.STDOUT)
            job.assign(proc)
            while proc.poll() is None:
                elapsed = time.monotonic() - started
                if elapsed > timeout:
                    stopped = f"timed out after {elapsed:.0f} s (limit {timeout:.0f} s)"
                elif (free := memory()) < min_available_mb:
                    stopped = f"runner memory low: {free} MB available (floor {min_available_mb} MB)"
                if stopped:
                    break
                time.sleep(POLL_SECONDS)
        report: list[str] = []
        if stopped:
            report = [f"ci_guard: {stopped}; ending the task's process tree", *evidence(job, out, dumps=True)]
            job.terminate()
            proc.kill()
            proc.wait(timeout=30)
        else:
            leftover = [info for pid in job.pids() for info in [process_info(pid)] if info]
            if leftover:
                report = ["ci_guard: the task exited but left processes running; ending them",
                          *[f"  {info.line()}" for info in leftover]]
                job.terminate()
        if report:
            with log_path.open("a", encoding="utf-8") as log:
                log.write("\n" + "\n".join(report) + "\n")
        return TaskResult(124 if stopped else proc.returncode, time.monotonic() - started, job.peak_mb(), stopped,
                          report)
    finally:
        job.close()


# endregion
