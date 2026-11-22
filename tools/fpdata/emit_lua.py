"""Write the merged catalog as Lua files for the addon (ForeverProfessional/Data).

Layout (all files share the addon namespace `ns.Data`):
  Data.xml                 load order; include it from the addon TOC
  Meta.lua                 build info and source pins
  Professions.lua          skill line -> { name, file, recipes, new }
  Recipes/<Name>.lua       ns.Data.Recipes[skillLine][spell] = { ... } (one line per recipe)
  Ranks.lua                profession rank spells (Journeyman, Expert, ...)
  NPCs.lua / Objects.lua / Quests.lua   entities referenced by recipe sources
  Categories.lua           TradeSkillCategory tree (empty when the table wasn't available)
  Locales/<locale>.lua     localized NPC / object / quest names (loaded only for that locale)

Recipe fields: learn, yellow, green, grey, cat, creates, count, teach (item or list), bound,
side, src (source types), trainer (copper), rep {faction, standing}, favor, vendors {npc...},
drops {{npc, chance%}...} (chance omitted when unknown, 12 kept), dropTotal, objects,
objectTotal, containers, containerTotal,
quests, unverified (types claimed without a known NPC/quest), unknown, new.
"""
import os
import re

from .merge import PROFESSIONS

HEADER = """-- GENERATED FILE, DO NOT EDIT. Built by tools/build_data.py ({build}).
-- Data: WhatsTraining (MIT), ForeverDB (GPL-3.0), AllTheThings (MIT), Blizzard client tables.
-- Part of ForeverProfessional, licensed under the GNU GPL v3 or later.
local _, ns = ...
ns.Data = ns.Data or {{}}
"""

_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
_LUA_KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in",
                 "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"}


def lua_str(s):
    out = s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "\\r")
    return '"%s"' % out


def lua_num(v):
    if isinstance(v, float):
        if v == int(v):
            return str(int(v))
        return ("%.3f" % v).rstrip("0").rstrip(".")
    return str(v)


def lua(v):
    """Serialize a Python value as a single-line Lua expression."""
    if v is None:
        return "nil"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return lua_num(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        if not v:
            return "{}"
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            if x is None:
                continue
            if isinstance(k, str) and _IDENT.match(k) and k not in _LUA_KEYWORDS:
                parts.append("%s = %s" % (k, lua(x)))
            else:
                parts.append("[%s] = %s" % (lua(k), lua(x)))
        return "{ " + ", ".join(parts) + " }" if parts else "{}"
    raise TypeError("cannot serialize %r" % (v,))


def _pairs(entries):
    """[(id, chance|None)] -> {{id, chance}, {id}}."""
    return [[i, c] if c is not None else [i] for i, c in entries]


def recipe_table(r):
    t = {}
    for key, field in (("learn", "learn"), ("yellow", "yellow"), ("green", "green"), ("grey", "grey"),
                       ("cat", "category"), ("creates", "creates"), ("count", "count")):
        if r.get(field) is not None:
            t[key] = r[field]
    teach = r.get("teach") or []
    if len(teach) == 1:
        t["teach"] = teach[0]
    elif teach:
        t["teach"] = teach
    if r.get("bound") is not None:
        t["bound"] = r["bound"]
    if r.get("side"):
        t["side"] = r["side"]
    if r.get("sources"):
        t["src"] = r["sources"]
    if r.get("trainerCost"):
        t["trainer"] = r["trainerCost"]
    if r.get("reputation"):
        t["rep"] = [r["reputation"]["faction"], r["reputation"]["standing"]]
    if r.get("merchantFavor"):
        t["favor"] = r["merchantFavor"]
    if r.get("vendors"):
        t["vendors"] = r["vendors"]
    if r.get("drops"):
        t["drops"] = _pairs(r["drops"])
        if r.get("dropTotal", 0) > len(r["drops"]):
            t["dropTotal"] = r["dropTotal"]
    if r.get("objects"):
        t["objects"] = _pairs(r["objects"])
        if r.get("objectTotal", 0) > len(r["objects"]):
            t["objectTotal"] = r["objectTotal"]
    if r.get("containers"):
        t["containers"] = _pairs(r["containers"])
        if r.get("containerTotal", 0) > len(r["containers"]):
            t["containerTotal"] = r["containerTotal"]
    if r.get("quests"):
        t["quests"] = r["quests"]
    if r.get("unverified"):
        t["unverified"] = r["unverified"]
    if r.get("unknown"):
        t["unknown"] = True
    if r.get("new"):
        t["new"] = True
    return t


def _write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def _position(pos):
    if not pos:
        return {}
    if "map" in pos:
        return {"map": pos["map"], "x": pos["x"], "y": pos["y"]}
    return {"instance": pos["instance"]}


def emit(catalog, out_dir, build_label, meta):
    header = HEADER.format(build=build_label)
    files = ["Meta.lua", "Professions.lua"]

    # Meta
    lines = [header, "ns.Data.Meta = " + lua(meta)]
    _write(os.path.join(out_dir, "Meta.lua"), "\n".join(lines) + "\n")

    # Recipes per profession
    by_line = {}
    for r in catalog["recipes"]:
        by_line.setdefault(r["skillLine"], []).append(r)
    profs = {}
    for line in sorted(by_line, key=lambda k: PROFESSIONS[k][0]):
        file_name, name = PROFESSIONS[line]
        rs = sorted(by_line[line], key=lambda r: ((r["learn"] if r["learn"] is not None else -1), r["spell"]))
        out = [header, "ns.Data.Recipes = ns.Data.Recipes or {}", "ns.Data.Recipes[%d] = {" % line]
        for r in rs:
            out.append("    [%d] = %s," % (r["spell"], lua(recipe_table(r))))
        out.append("}")
        rel = "Recipes/%s.lua" % file_name
        _write(os.path.join(out_dir, rel), "\n".join(out) + "\n")
        files.append(rel)
        profs[line] = {"name": name, "file": file_name, "recipes": len(rs), "new": sum(1 for r in rs if r["new"])}
    _write(os.path.join(out_dir, "Professions.lua"),
           header + "ns.Data.Professions = {\n" +
           "".join("    [%d] = %s,\n" % (k, lua(v)) for k, v in sorted(profs.items())) + "}\n")

    # Ranks
    out = [header, "ns.Data.Ranks = {"]
    for r in sorted(catalog["ranks"], key=lambda r: (r["skillLine"], r["learn"] or 0)):
        out.append("    [%d] = %s," % (r["spell"], lua({"line": r["skillLine"], "rank": r["rank"], "skill": r["learn"],
                                                         "level": r["level"] or None, "trainer": r["trainerCost"],
                                                         "teach": r["teach"]})))
    out.append("}")
    _write(os.path.join(out_dir, "Ranks.lua"), "\n".join(out) + "\n")
    files.append("Ranks.lua")

    # Entities
    out = [header, "-- [npc] = { name, sub, faction (A/H/AH), map (uiMapID), x, y (0-100), instance, areas }",
           "ns.Data.NPCs = {"]
    for n, e in sorted(catalog["npcs"].items()):
        t = {"name": e["name"], "sub": e["sub"], "faction": e["faction"]}
        t.update(_position(e["pos"]))
        if e["areas"]:
            t["areas"] = e["areas"]
        out.append("    [%d] = %s," % (n, lua(t)))
    out.append("}")
    _write(os.path.join(out_dir, "NPCs.lua"), "\n".join(out) + "\n")

    out = [header, "ns.Data.Objects = {"]
    for o, e in sorted(catalog["objects"].items()):
        t = {"name": e["name"]}
        t.update(_position(e["pos"]))
        out.append("    [%d] = %s," % (o, lua(t)))
    out.append("}")
    _write(os.path.join(out_dir, "Objects.lua"), "\n".join(out) + "\n")

    out = [header, "ns.Data.Quests = {"]
    for q, e in sorted(catalog["quests"].items()):
        t = {"name": e["name"], "level": e["level"], "minLevel": e["minLevel"]}
        if e["giverNpcs"]:
            t["npcs"] = e["giverNpcs"]
        if e["giverObjects"]:
            t["objects"] = e["giverObjects"]
        out.append("    [%d] = %s," % (q, lua(t)))
    out.append("}")
    _write(os.path.join(out_dir, "Quests.lua"), "\n".join(out) + "\n")
    files += ["NPCs.lua", "Objects.lua", "Quests.lua"]

    # Categories
    out = [header, "-- [categoryID] = { name (enUS), parent, line (skill line), order }",
           "-- Empty when TradeSkillCategory couldn't be fetched; the addon then caches names from",
           "-- C_TradeSkillUI.GetCategoryInfo while a profession window is open.",
           "ns.Data.Categories = {"]
    for c, e in sorted(catalog["categories"].items()):
        out.append("    [%d] = %s," % (c, lua({"name": e["name"], "parent": e["parent"] or None,
                                               "line": e["skillLine"] or None, "order": e["order"]})))
    out.append("}")
    _write(os.path.join(out_dir, "Categories.lua"), "\n".join(out) + "\n")
    files.append("Categories.lua")

    # Locales
    for loc, names in sorted(catalog.get("locales", {}).items()):
        out = [header, 'if GetLocale() ~= "%s" then return end' % loc, "ns.Data.Locale = {"]
        for kind in ("npc", "obj", "quest"):
            entries = names.get(kind) or {}
            out.append("    %s = {" % kind)
            for i, name in sorted(entries.items()):
                out.append("        [%d] = %s," % (i, lua_str(name)))
            out.append("    },")
        out.append("}")
        rel = "Locales/%s.lua" % loc
        _write(os.path.join(out_dir, rel), "\n".join(out) + "\n")
        files.append(rel)

    xml = ['<Ui xmlns="http://www.blizzard.com/wow/ui/">',
           "    <!-- GENERATED by tools/build_data.py -->"]
    xml += ['    <Script file="%s"/>' % f.replace("/", "\\") for f in files]
    xml.append("</Ui>")
    _write(os.path.join(out_dir, "Data.xml"), "\n".join(xml) + "\n")
    return files
