"""Run EverlookDB Crafting's offline tests in Lua 5.1 (WoW's version) via lupa.

Usage: python -P tests/run.py [Quarry dir]

The parity test runs everlookdb.com's own route code (web/professions.js in the Quarry repo, default D:\\Dev\\Quarry)
under node first (tests/parity.mjs) and hands its routes to the Lua tests.
"""
import json
import os
import subprocess
import sys

from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
QUARRY = sys.argv[1] if len(sys.argv) > 1 else r"D:\Dev\Quarry"


def parity():
    out = subprocess.run(["node", f"{ROOT}/tests/parity.mjs", QUARRY, "a", "197", "129", "185"],
                         check=True, capture_output=True, text=True, encoding="utf-8").stdout
    return json.loads(out)


def to_lua(v):
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ",".join(to_lua(x) for x in v) + "}"
    return "{" + ",".join(f"[{k if k.isdigit() else json.dumps(k)}]={to_lua(x)}" for k, x in v.items()) + "}"


def main() -> int:
    routes = parity()
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    with open(f"{ROOT}/tests/wowmock.lua", encoding="utf-8") as f:
        lua.execute(f.read())
    table = lua.execute("return " + to_lua(routes))
    with open(f"{ROOT}/tests/run.lua", encoding="utf-8") as f:
        runner = lua.execute("return function(...) local f = assert(loadstring(...)); return f end")(f.read())
    failures = runner(ROOT, table)
    # the game integrations (tooltips, guild, trainer and merchant capture, buying), each in a fresh Lua state
    for name in ("integrations", "craftlist", "favor"):
        print(f"-- tests/{name}.lua")
        lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        with open(f"{ROOT}/tests/wowmock.lua", encoding="utf-8") as f:
            lua.execute(f.read())
        with open(f"{ROOT}/tests/{name}.lua", encoding="utf-8") as f:
            run = lua.execute("return function(...) local f = assert(loadstring(...)); return f end")(f.read())
        failures += run(ROOT)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
