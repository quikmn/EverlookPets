"""Run Everlook Pets' offline tests in Lua 5.1 (WoW's version) via lupa.

Usage: python -P tests/run.py
"""
import sys
from pathlib import Path

from lupa import lua51

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute((ROOT / "tests" / "wowmock.lua").read_text(encoding="utf-8"))
    runner = lua.eval("function(src, ...) local f = assert(loadstring(src, 'run.lua')); return f(...) end")
    failures = runner((ROOT / "tests" / "run.lua").read_text(encoding="utf-8"), str(ROOT).replace("\\", "/"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
