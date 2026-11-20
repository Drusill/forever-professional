"""Load ForeverProfessional in Lua 5.1 (lupa) against tests/wow_mock.lua, the way the client does.

The TOC and Data/Data.xml are parsed for real, so a missing or misspelled file fails the tests.
"""
import pathlib
import re

import lupa.lua51 as lupa

ROOT = pathlib.Path(__file__).resolve().parent.parent
ADDON_DIR = ROOT / "ForeverProfessional"
ADDON_NAME = "ForeverProfessional"
TOC = ADDON_DIR / f"{ADDON_NAME}_Camelot.toc"
MOCK = pathlib.Path(__file__).resolve().parent / "wow_mock.lua"

_SUFFIX = re.compile(r"\s*\[[^\]]*\]")


def toc_metadata(toc=TOC):
    meta = {}
    for line in toc.read_text(encoding="utf-8").splitlines():
        if line.startswith("## ") and ":" in line:
            key, value = line[3:].split(":", 1)
            meta.setdefault(key.strip(), []).append(value.strip())
    return meta


def _xml_scripts(xml_path):
    text = xml_path.read_text(encoding="utf-8")
    files = []
    for m in re.finditer(r'<(Script|Include)\s+file="([^"]+)"', text):
        kind, rel = m.group(1), m.group(2).replace("\\", "/")
        path = xml_path.parent / rel
        files.extend(_xml_scripts(path) if kind == "Include" else [path])
    return files


def addon_files(toc=TOC):
    """Lua files in load order, with XML includes expanded."""
    files = []
    for raw in toc.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        rel = _SUFFIX.sub("", line).strip().replace("\\", "/")
        path = toc.parent / rel
        files.extend(_xml_scripts(path) if path.suffix.lower() == ".xml" else [path])
    return files


class Addon:
    """A fresh Lua state with the mock API and the addon loaded."""

    def __init__(self, setup=None, locale=None):
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK.read_text(encoding="utf-8"))
        self.g = self.lua.globals()
        self.mock = self.g.mock
        if locale:
            self.mock.locale = locale
        if setup:
            self.run(setup)
        self.ns = self.lua.table()
        loader = self.lua.eval("function(src, name) return assert(loadstring(src, name)) end")
        for path in addon_files():
            chunk = loader(path.read_text(encoding="utf-8"), "@" + str(path.relative_to(ADDON_DIR)))
            chunk(ADDON_NAME, self.ns)
        self._run = self.lua.eval("function(code) return assert(loadstring(code))() end")

    def run(self, code):
        if not hasattr(self, "_run"):
            return self.lua.execute(code)
        return self._run(code)

    def login(self):
        self.run(f'fire("ADDON_LOADED", "{ADDON_NAME}"); fire("PLAYER_LOGIN"); flush()')

    def slash(self, msg=""):
        self.g.SlashCmdList.FOREVERPROFESSIONAL(msg)
        self.run("flush()")

    def printed(self):
        p = self.mock.printed
        return [p[i] for i in range(1, len(p) + 1)]


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []
