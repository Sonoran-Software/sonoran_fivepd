"""Run the Lua bridge tests, optionally through SonoranCADFiveM's actual SDK."""
import json
import sys
from pathlib import Path

from lupa.lua54 import LuaRuntime, lua_type

lua = LuaRuntime(unpack_returned_tuples=True)


def to_python(value):
    if lua_type(value) != "table":
        return value
    keys = list(value.keys())
    if keys and set(keys) == set(range(1, len(keys) + 1)):
        return [to_python(value[index]) for index in range(1, len(keys) + 1)]
    return {str(key): to_python(value[key]) for key in keys}


lua.globals().json = lua.table_from({
    "encode": lambda value: json.dumps(to_python(value), sort_keys=True, separators=(",", ":")),
    "decode": lambda value: lua.table_from(json.loads(value), recursive=True),
})
lua.globals().cad_root = str(Path(sys.argv[1]).resolve()) if len(sys.argv) > 1 else None
lua.execute(Path("tests/server_spec.lua").read_text())
