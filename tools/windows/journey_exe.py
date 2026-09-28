#!/usr/bin/env python3
"""App executable selection shared by the Windows journey scripts.

Every journey takes ``--exe`` with a path or one of the build aliases ``debug`` (default),
``release`` (trimmed ReadyToRun publish) or ``aot`` (NativeAOT Release publish, the ship
configuration). Release builds ignore the ``FST_*`` environment unless they run in
automation mode, which ``uiwin.py launch`` turns on (``FST_AUTOMATION=1`` plus the
``fst-automation.marker`` file it writes next to a publish under ``windows/.artifacts``).
"""

from __future__ import annotations

import argparse
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ARTIFACTS = REPO_ROOT / "windows" / ".artifacts" / "app"
EXE_NAME = "FestivalScoreTracker.exe"
ALIASES = {
    "debug": REPO_ROOT / "windows" / "Festival.App" / "bin" / "x64" / "Debug" / "net9.0-windows10.0.26100.0" / "win-x64" / EXE_NAME,
    "release": ARTIFACTS / "Release" / EXE_NAME,
    "aot": ARTIFACTS / "Release-aot" / EXE_NAME,
}
DEBUG_EXE = ALIASES["debug"]

# region Selection


def resolve(value: str | Path) -> Path:
    """Resolve an ``--exe`` value.

    Args:
        value: A build alias (``debug``/``release``/``aot``) or an executable path.

    Returns:
        Absolute executable path (not checked for existence).
    """
    text = str(value)
    return ALIASES.get(text.lower(), Path(text)).resolve()


def add_argument(parser: argparse.ArgumentParser) -> None:
    """Add the shared ``--exe`` option.

    Args:
        parser: Journey argument parser.
    """
    parser.add_argument("--exe", type=resolve, default=DEBUG_EXE,
                        help="app under test: debug (default), release, aot, or a path to FestivalScoreTracker.exe")

# endregion
