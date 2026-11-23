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
DATA_DIR = ADDON_DIR / "Data"

# Loaded right after the baked data. 1251750 was removed from the data as never released (issue #15);
# the tests keep it as their Alchemy recipe with no thresholds and no category, sold for Merchant's Favor.
DATA_FIXTURES = """
local _, ns = ...
ns.Data.Recipes[171][1251750] = { learn = 180, creates = 250952, teach = 250996, bound = true, src = { "vendor" },
    rep = { 2586, 5 }, favor = 120, vendors = { 248196, 256729 }, new = true }
local alchemy = ns.Data.Professions[171]
alchemy.recipes, alchemy.new = alchemy.recipes + 1, alchemy.new + 1
"""

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
        fixtures_added = False
        for path in addon_files():
            if not fixtures_added and DATA_DIR not in path.parents:
                loader(DATA_FIXTURES, "@fixtures")(ADDON_NAME, self.ns)
                fixtures_added = True
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

    @staticmethod
    def call(obj, method, *args):
        """obj:method(...) from Python."""
        return obj[method](obj, *args)

    def printed(self):
        p = self.mock.printed
        return [p[i] for i in range(1, len(p) + 1)]


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


_COLOR = re.compile(r"\|c[0-9a-fA-F]{8}|\|r")


def plain(s):
    """Text without colour codes."""
    return _COLOR.sub("", s) if s is not None else s


# Cached alts, seeded through Addon(setup=ALTS). The logged-in mock character is Player-1-0000000A "Tester".
ALTS = """
ForeverProfessionalDB = { version = 2, chars = {
  ["Player-1-0000000B"] = { guid = "Player-1-0000000B", name = "Dru", class = "ROGUE", faction = "Horde", level = 40,
    updated = 1795000000, professions = { [171] = { skill = 290, max = 300 } }, learned = { [7255] = true } },
  ["Player-1-0000000C"] = { guid = "Player-1-0000000C", name = "Dru", class = "DRUID", faction = "Horde", level = 30,
    updated = 1795000000, professions = { [171] = { skill = 150, max = 225 }, [185] = { skill = 50, max = 75 } }, learned = {} },
  ["Player-1-0000000D"] = { guid = "Player-1-0000000D", name = "Paly", class = "PALADIN", faction = "Alliance", level = 50,
    updated = 1795000000, professions = { [171] = { skill = 285, max = 300 }, [185] = { skill = 30, max = 75 } }, learned = {} },
  ["Player-1-0000000E"] = { guid = "Player-1-0000000E", name = "Banco", class = "SHAMAN", faction = "Horde", level = 10,
    updated = 1795000000, professions = {}, learned = {} },
} }
"""
