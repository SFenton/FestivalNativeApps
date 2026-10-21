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
import struct
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
#: Thread info, unloaded modules and data segments only: a few MB that keep every thread's stack.
SMALL_DUMP_TYPE = 0x1 | 0x1000 | 0x20
INVALID_HANDLE = wintypes.HANDLE(-1).value


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


def modules(process: int) -> list[tuple[int, int, str]]:
    """The process's loaded modules as ``(base, size, name)``.

    Args:
        process: Handle with query and read access.

    Returns:
        Modules sorted by base address.
    """
    psapi = ctypes.WinDLL("psapi", use_last_error=True)
    psapi.EnumProcessModulesEx.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD,
                                           ctypes.POINTER(wintypes.DWORD), wintypes.DWORD]
    psapi.GetModuleInformation.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD]
    psapi.GetModuleBaseNameW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.LPWSTR, wintypes.DWORD]
    handles = (ctypes.c_void_p * 1024)()
    needed = wintypes.DWORD()
    if not psapi.EnumProcessModulesEx(process, handles, ctypes.sizeof(handles), ctypes.byref(needed), 3):
        return []
    found = []
    for module in handles[:min(needed.value // ctypes.sizeof(ctypes.c_void_p), 1024)]:
        info = (ctypes.c_void_p * 3)()  # MODULEINFO: base, size (DWORD, padded), entry point
        name = ctypes.create_unicode_buffer(260)
        if psapi.GetModuleInformation(process, module, info, ctypes.sizeof(info)):
            psapi.GetModuleBaseNameW(process, module, name, 260)
            found.append((info[0] or 0, (info[1] or 0) & 0xFFFFFFFF, name.value))
    return sorted(found)


def stowed(process: int, array: int, count: int) -> str:
    """Decode a ``0xC000027B``'s stowed exceptions (``STOWED_EXCEPTION_INFORMATION_V2``) from the stopped process: each
    one's HRESULT and the stack where it was originated, as ``module+offset`` (JIT code, outside any module, stays an
    address for ``dotnet-dump`` ``ip2md``). Read before the dump, so it survives a dump that fails.

    Args:
        process: Handle with query and read access.
        array: Exception parameter 0, the array of record pointers.
        count: Exception parameter 1, the number of records.

    Returns:
        Text lines, or a note on what could not be read.
    """
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.ReadProcessMemory.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                           ctypes.POINTER(ctypes.c_size_t)]

    def read(address: int, size: int) -> bytes:
        buffer = ctypes.create_string_buffer(size)
        done = ctypes.c_size_t()
        if not kernel32.ReadProcessMemory(process, ctypes.c_void_p(address), buffer, size, ctypes.byref(done)):
            raise OSError(f"cannot read 0x{address:x}: error {ctypes.get_last_error()}")
        return buffer.raw[:done.value]

    loaded = modules(process)

    def where(address: int) -> str:
        for base, size, name in loaded:
            if base <= address < base + size:
                return f"{name}+0x{address - base:x}"
        return f"0x{address:x} (JIT code?)"

    lines = []
    try:
        for index in range(min(count, 8)):
            pointer = struct.unpack("<Q", read(array + 8 * index, 8))[0]
            raw = read(pointer, 56)
            _, signature, hresult, form_thread = struct.unpack_from("<IIiI", raw, 0)
            form = form_thread & 3
            # Multi-character signatures ('SE02', 'CLR1') read big-endian; the 30-bit thread field drops the ID's
            # always-zero low two bits.
            lines.append(f"stowed[{index}]: {signature.to_bytes(4, 'big').decode('ascii', 'replace')} "
                         f"hr 0x{hresult & 0xFFFFFFFF:08X} thread {form_thread & ~3}")
            if form == 1:
                address, word_size, words, trace = struct.unpack_from("<QIIQ", raw, 16)
                lines.append(f"  originated at {where(address)}")
                frames = read(trace, word_size * min(words, 64))
                for frame in range(min(words, 64)):
                    value = int.from_bytes(frames[frame * word_size:(frame + 1) * word_size], "little")
                    lines.append(f"  {frame:2}: {where(value)}")
            nested_type, nested = struct.unpack_from("<I", raw, 40)[0], struct.unpack_from("<Q", raw, 48)[0]
            if nested:
                lines.append(f"  nested {nested_type.to_bytes(4, 'big').decode('ascii', 'replace')} at 0x{nested:x}")
    except OSError as error:
        lines.append(f"stowed exceptions unreadable: {error}")
    return "\n".join(lines) + "\n"


def keep(kernel32, dbghelp, pid: int, stem: Path, text: str, code: int, record: ExceptionRecord) -> None:
    """Write the fatal exception's report (with decoded stowed exceptions) and its dumps while the app is stopped.

    The report is written first and each dump's result is appended, because a dump can fail partway (#680: the first CI
    dump stopped at 48 MB with no stream directory). A small dump (threads, stacks, modules) comes before the full one.

    Args:
        kernel32: kernel32 with argument types set.
        dbghelp: dbghelp with argument types set.
        pid: App process ID.
        stem: Path without suffix, ``<folder>/<name>-<code>``.
        text: :func:`describe` output.
        code: Exception code.
        record: The exception record.
    """
    report = stem.with_suffix(".txt")
    process = kernel32.OpenProcess(0x0400 | 0x0010 | 0x0040, False, pid)  # query, read, duplicate handles
    if process and code == 0xC000027B and record.NumberParameters >= 2:
        text += stowed(process, record.ExceptionInformation[0], record.ExceptionInformation[1])
    report.write_text(text, encoding="utf-8")
    for path, kind in ((stem.parent / f"{stem.name}-small.dmp", SMALL_DUMP_TYPE), (stem.with_suffix(".dmp"), DUMP_TYPE)):
        dump = kernel32.CreateFileW(str(path), 0x40000000, 0, None, 2, 0x80, None)  # GENERIC_WRITE, CREATE_ALWAYS
        ok = bool(process) and dump not in (None, INVALID_HANDLE) and \
            bool(dbghelp.MiniDumpWriteDump(process, pid, dump, kind, None, None, None))
        error = ctypes.get_last_error()
        if dump not in (None, INVALID_HANDLE):
            kernel32.CloseHandle(dump)
        with report.open("a", encoding="utf-8") as out:
            out.write(f"dump {path.name}: {'written' if ok else f'failed (error 0x{error & 0xFFFFFFFF:08X})'}\n")
    if process:
        kernel32.CloseHandle(process)


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
                    keep(kernel32, dbghelp, pid, folder / f"{name}-{code:08X}",
                         describe(code, record, event.dwThreadId, first), code, record)
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
