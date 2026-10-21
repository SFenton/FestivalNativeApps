"""Attach to the app as a minimal debugger and keep a dump when it fails fast (Windows UI journeys, #680).

A WinUI fail-fast (``0xC000027B``, a stowed exception raised inside ``Microsoft.UI.Xaml.dll``) bypasses
``App.UnhandledException``, and on a hosted CI runner Windows Error Reporting records neither an event nor a LocalDumps
dump for it, so the window just disappears. A debugger still sees the exception: this script attaches to ``pid``, lets
every first-chance exception through to the app (managed exceptions included), and on a fatal one writes
``<name>-<code>.txt`` (code, address, thread, parameters: for ``0xC000027B`` the stowed-exception array and count) and
``<name>-<code>.dmp`` (threads, stacks, heaps) to ``folder`` before the app ends as it would have. It detaches when the
app exits; ending this script never ends the app.

Usage: ``python crash_dump.py <pid> <folder> <name>``. ``journeys/profile.py`` starts it when ``FST_CRASH_DUMPS`` names a
folder (``windows-ui.yml``).
"""

from __future__ import annotations

import ctypes
import sys
from ctypes import wintypes
from pathlib import Path

#: Exceptions that end the app whether or not it handles them first: stowed exception, fail-fast, stack-buffer
#: overrun (``__fastfail``) and stack overflow. Any second-chance exception is fatal as well.
FATAL = {0xC000027B, 0xC0000602, 0xC0000409, 0xC00000FD}
BREAKPOINT = 0x80000003
DBG_CONTINUE = 0x00010002
DBG_EXCEPTION_NOT_HANDLED = 0x80010001
EXCEPTION_DEBUG_EVENT, CREATE_PROCESS_DEBUG_EVENT, EXIT_PROCESS_DEBUG_EVENT, LOAD_DLL_DEBUG_EVENT = 1, 3, 5, 6
#: Data segments, handles, private read-write memory (heaps and stacks), memory info, thread info, unloaded modules.
DUMP_TYPE = 0x1 | 0x4 | 0x200 | 0x800 | 0x1000 | 0x20


class ExceptionRecord(ctypes.Structure):
    _fields_ = [("ExceptionCode", wintypes.DWORD), ("ExceptionFlags", wintypes.DWORD),
                ("ExceptionRecord", ctypes.c_void_p), ("ExceptionAddress", ctypes.c_void_p),
                ("NumberParameters", wintypes.DWORD), ("ExceptionInformation", ctypes.c_ulonglong * 15)]


class ExceptionDebugInfo(ctypes.Structure):
    _fields_ = [("ExceptionRecord", ExceptionRecord), ("dwFirstChance", wintypes.DWORD)]


class DebugEventInfo(ctypes.Union):
    _fields_ = [("Exception", ExceptionDebugInfo), ("Handles", ctypes.c_void_p * 3), ("raw", ctypes.c_byte * 160)]


class DebugEvent(ctypes.Structure):
    _fields_ = [("dwDebugEventCode", wintypes.DWORD), ("dwProcessId", wintypes.DWORD),
                ("dwThreadId", wintypes.DWORD), ("u", DebugEventInfo)]


def describe(code: int, record: ExceptionRecord, thread: int, first_chance: bool) -> str:
    """The exception as text; for a stowed exception the parameters are the stowed-record array and its count.

    Args:
        code: Exception code.
        record: The debug event's exception record.
        thread: Faulting thread ID.
        first_chance: Whether the app has not seen it yet.

    Returns:
        A few ``key: value`` lines.
    """
    params = [f"0x{record.ExceptionInformation[i]:x}" for i in range(min(record.NumberParameters, 15))]
    return (f"code: 0x{code:08X}\nfirst chance: {first_chance}\nthread: {thread}\n"
            f"address: 0x{record.ExceptionAddress or 0:x}\nparameters: {' '.join(params)}\n")


def watch(pid: int, folder: Path, name: str) -> int:
    """Debug ``pid`` until it exits, keeping a report and dump of its first fatal exception.

    Args:
        pid: App process ID.
        folder: Where the report and dump go.
        name: File name prefix (the journey).

    Returns:
        0 when the app exited without a fatal exception, 1 when one was kept, 2 when the attach failed.
    """
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    dbghelp = ctypes.WinDLL("dbghelp", use_last_error=True)
    kernel32.OpenProcess.restype = wintypes.HANDLE
    kernel32.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel32.DebugActiveProcess.argtypes = [wintypes.DWORD]
    kernel32.DebugSetProcessKillOnExit.argtypes = [wintypes.BOOL]
    kernel32.WaitForDebugEvent.argtypes = [ctypes.POINTER(DebugEvent), wintypes.DWORD]
    kernel32.ContinueDebugEvent.argtypes = [wintypes.DWORD, wintypes.DWORD, wintypes.DWORD]
    kernel32.CreateFileW.restype = wintypes.HANDLE
    kernel32.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.c_void_p,
                                     wintypes.DWORD, wintypes.DWORD, wintypes.HANDLE]
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    dbghelp.MiniDumpWriteDump.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.HANDLE, wintypes.DWORD,
                                          ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    if not kernel32.DebugActiveProcess(pid):
        print(f"crash_dump: cannot attach to {pid}: error {ctypes.get_last_error()}", file=sys.stderr)
        return 2
    kernel32.DebugSetProcessKillOnExit(False)
    folder.mkdir(parents=True, exist_ok=True)
    event = DebugEvent()
    attached = False
    kept = False
    while kernel32.WaitForDebugEvent(ctypes.byref(event), 0xFFFFFFFF):
        status = DBG_CONTINUE
        kind = event.dwDebugEventCode
        if kind in (CREATE_PROCESS_DEBUG_EVENT, LOAD_DLL_DEBUG_EVENT) and event.u.Handles[0]:
            kernel32.CloseHandle(event.u.Handles[0])  # the image file handle the debugger owns
        elif kind == EXCEPTION_DEBUG_EVENT:
            record = event.u.Exception.ExceptionRecord
            code = record.ExceptionCode
            first = bool(event.u.Exception.dwFirstChance)
            if code == BREAKPOINT and not attached:
                attached = True  # the attach breakpoint
            else:
                status = DBG_EXCEPTION_NOT_HANDLED
                if not kept and (code in FATAL or not first):
                    kept = True
                    stem = folder / f"{name}-{code:08X}"
                    stem.with_suffix(".txt").write_text(describe(code, record, event.dwThreadId, first), encoding="utf-8")
                    process = kernel32.OpenProcess(0x0400 | 0x0010 | 0x0040, False, pid)
                    dump = kernel32.CreateFileW(str(stem.with_suffix(".dmp")), 0x40000000, 0, None, 2, 0x80, None)
                    if process and dump not in (None, wintypes.HANDLE(-1).value):
                        dbghelp.MiniDumpWriteDump(process, pid, dump, DUMP_TYPE, None, None, None)
                    for handle in (dump, process):
                        if handle and handle != wintypes.HANDLE(-1).value:
                            kernel32.CloseHandle(handle)
        elif kind == EXIT_PROCESS_DEBUG_EVENT:
            kernel32.ContinueDebugEvent(event.dwProcessId, event.dwThreadId, DBG_CONTINUE)
            break
        kernel32.ContinueDebugEvent(event.dwProcessId, event.dwThreadId, status)
    return 1 if kept else 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    return watch(int(args[0]), Path(args[1]), args[2])


if __name__ == "__main__":
    raise SystemExit(main())
