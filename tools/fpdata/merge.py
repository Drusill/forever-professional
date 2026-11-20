"""Merge WhatsTraining, ForeverDB and the client tables into one recipe catalog.

Rules (see tools/README.md):
- The recipe list and source *types*, trainer costs, reputation / Merchant's Favor gates,
  bound flags and faction sides come from WhatsTraining.
- Skill thresholds and category IDs come from the client's SkillLineAbility table:
  yellow = TrivialSkillLineRankLow, grey = TrivialSkillLineRankHigh, green = midpoint.
  The orange "learn" skill comes from WhatsTraining (the client table has 1 for most).
- Recipe item <-> spell mapping comes from WhatsTraining's `teach`, completed with
  ForeverDB's ItemEffect (trigger 6) when WhatsTraining has none.
- Vendor NPCs: union of WhatsTraining and ForeverDB. Drops, object drops, container drops
  and quest rewards: ForeverDB, plus WhatsTraining's quest list.
- NPC / object / quest names and positions come from ForeverDB.
- "auto" = learned with the profession (WhatsTraining autoLearned, or AcquireMethod 1).
  A recipe with no known source at all is flagged `unknown`.
- tools/overrides.json is applied last and wins.
"""
NEW_SPELL_MIN = 1000000  # Forever's new recipe spells use IDs >= 1,000,000
DROP_CAP = 12            # drop sources kept per recipe (highest rate first); total is kept

PROFESSIONS = {
    129: ("FirstAid", "First Aid"), 164: ("Blacksmithing", "Blacksmithing"), 165: ("Leatherworking", "Leatherworking"),
    171: ("Alchemy", "Alchemy"), 182: ("Herbalism", "Herbalism"), 185: ("Cooking", "Cooking"),
    186: ("Mining", "Mining"), 197: ("Tailoring", "Tailoring"), 202: ("Engineering", "Engineering"),
    333: ("Enchanting", "Enchanting"), 356: ("Fishing", "Fishing"), 393: ("Skinning", "Skinning"),
}

# Source types in display order. "trainer" first, then the ones that need travelling.
SOURCE_ORDER = ["auto", "trainer", "vendor", "quest", "drop", "object", "container", "crafted", "worldObject"]
WT_SOURCE_MAP = {"trainer": "trainer", "vendor": "vendor", "quest": "quest", "drop": "drop",
                 "world_object": "worldObject", "crafted": "crafted"}


def _sort_drops(drops):
    return sorted(drops, key=lambda d: (d[1] is None, -(d[1] or 0), d[0]))


def thresholds(sla_rows, skill_line):
    rows = sla_rows or []
    row = next((r for r in rows if r["skillLine"] == skill_line), rows[0] if rows else None)
    if not row:
        return None, None, None, 0, 0
    yellow, grey = row["trivialLow"] or None, row["trivialHigh"] or None
    green = (yellow + grey) // 2 if yellow and grey else None
    return yellow, green, grey, row["category"], row["acquire"]


def merge_recipe(wt, fdb, sla):
    spell = wt["spell"]
    yellow, green, grey, category, acquire = thresholds(sla.get(spell), wt["skillLine"])
    teach = [wt["teach"]] if wt.get("teach") else []
    for item in fdb.teaching_items(spell):
        if item not in teach:
            teach.append(item)

    wt_types = {WT_SOURCE_MAP[s] for s in wt["sources"] if s in WT_SOURCE_MAP}
    vendors, drops, objects, containers, quests = [], {}, {}, {}, []
    for v in wt["vendors"]:
        if v["npc"] not in vendors:
            vendors.append(v["npc"])
    for q in wt["quests"]:
        if q["id"] not in quests:
            quests.append(q["id"])
    for item in teach:
        for n in fdb.vendors(item):
            if n not in vendors:
                vendors.append(n)
        for n, rate in fdb.drops(item):
            if n not in vendors and (n not in drops or (rate or 0) > (drops[n] or 0)):
                drops[n] = rate
        for o, rate in fdb.object_drops(item):
            objects[o] = rate
        for c, rate in fdb.container_drops(item):
            containers[c] = rate
        for q in fdb.quest_rewards(item):
            if q not in quests:
                quests.append(q)

    found = set()
    if vendors:
        found.add("vendor")
    if drops:
        found.add("drop")
    if objects:
        found.add("object")
    if containers:
        found.add("container")
    if quests:
        found.add("quest")
    types = set(found)
    if "trainer" in wt_types or wt.get("trainerCost"):
        types.add("trainer")
    if wt["autoLearned"] or acquire == 1:  # AcquireMethod 1: learned with the profession
        types.add("auto")
    types |= wt_types & {"crafted", "worldObject"}
    # WhatsTraining claims a type we have no NPC / quest / object for: keep it, flag it.
    unverified = sorted((wt_types & {"vendor", "drop", "quest"}) - found)
    types |= set(unverified)
    if "worldObject" in types and objects:
        types.discard("worldObject")
        types.add("object")

    drop_list = _sort_drops(list(drops.items()))
    rec = {
        "spell": spell,
        "skillLine": wt["skillLine"],
        "new": spell >= NEW_SPELL_MIN,
        "learn": wt.get("learn"),
        "yellow": yellow, "green": green, "grey": grey,
        "category": category or None,
        "creates": wt.get("creates"),
        "count": wt.get("count"),
        "teach": teach,
        "bound": wt.get("bound"),
        "side": wt.get("side"),
        "sources": [t for t in SOURCE_ORDER if t in types],
        "trainerCost": wt.get("trainerCost"),
        "reputation": wt.get("reputation"),
        "merchantFavor": wt.get("merchantFavor"),
        "vendors": vendors,
        "drops": drop_list[:DROP_CAP],
        "dropTotal": len(drop_list),
        "objects": _sort_drops(list(objects.items()))[:DROP_CAP],
        "objectTotal": len(objects),
        "containers": _sort_drops(list(containers.items()))[:DROP_CAP],
        "containerTotal": len(containers),
        "quests": quests,
        "unverified": unverified,
        "unknown": not types,
        "wtVendorAreas": {v["npc"]: v["areas"] for v in wt["vendors"] if v["areas"]},
        "wtVendorFaction": {v["npc"]: v["faction"] for v in wt["vendors"] if v.get("faction")},
    }
    return rec


def apply_overrides(recipes, overrides):
    by_spell = {r["spell"]: r for r in recipes}
    applied = []
    for key, patch in (overrides.get("recipes") or {}).items():
        if key.startswith("_"):
            continue
        r = by_spell.get(int(key))
        if not r:
            applied.append((int(key), "unknown recipe, skipped"))
            continue
        for field, value in patch.items():
            if field.startswith("_"):
                continue
            if field in ("drops", "objects", "containers"):
                value = [(int(e[0]), e[1] if len(e) > 1 else None) for e in value]
                if field == "drops":
                    r["dropTotal"] = len(value)
            r[field] = value
        if r.get("vendors") and "vendor" in r.get("unverified", []):
            r["unverified"] = [u for u in r["unverified"] if u != "vendor"]
        if r.get("sources"):
            r["unknown"] = False
        applied.append((int(key), ", ".join(k for k in patch if not k.startswith("_"))))
    return applied


def _entity_ids(recipes):
    npcs, objs, quests = set(), set(), set()
    for r in recipes:
        npcs.update(r["vendors"])
        npcs.update(n for n, _ in r["drops"])
        objs.update(o for o, _ in r["objects"])
        quests.update(r["quests"])
    return npcs, objs, quests


def build_entities(recipes, fdb):
    npc_ids, obj_ids, quest_ids = _entity_ids(recipes)
    quests = {}
    for q in sorted(quest_ids):
        info = fdb.quest(q)
        givers_npc, givers_obj = [], []
        for g in fdb.quest_givers(q):
            if g.startswith("c"):
                givers_npc.append(int(g[1:]))
            elif g.startswith("o"):
                givers_obj.append(int(g[1:]))
        npc_ids.update(givers_npc)
        obj_ids.update(givers_obj)
        quests[q] = {"name": info[0] if info else None, "level": info[1] if info and len(info) > 1 else None,
                     "minLevel": info[2] if info and len(info) > 2 else None,
                     "giverNpcs": givers_npc, "giverObjects": givers_obj}

    vendor_areas, vendor_faction = {}, {}
    for r in recipes:
        for n, areas in r["wtVendorAreas"].items():
            vendor_areas.setdefault(n, set()).update(areas)
        vendor_faction.update(r["wtVendorFaction"])

    npcs = {}
    for n in sorted(npc_ids):
        info = fdb.npc(n)
        fac = fdb.npc_faction(n)
        if not fac and vendor_faction.get(n):
            fac = {"Alliance": "A", "Horde": "H"}.get(vendor_faction[n])
        npcs[n] = {"name": info[0] if info else None, "sub": info[1] if info and len(info) > 1 else None,
                   "faction": fac, "pos": fdb.position("c", n), "areas": sorted(vendor_areas.get(n, []))}
    objects = {}
    for o in sorted(obj_ids):
        info = fdb.obj(o)
        objects[o] = {"name": info[0] if info else None, "pos": fdb.position("o", o)}
    return npcs, objects, quests


def apply_npc_overrides(npcs, overrides):
    """overrides["npcs"][id] = {name, sub, faction, map, x, y, instance, areas} (partial is fine)."""
    for key, patch in (overrides.get("npcs") or {}).items():
        if key.startswith("_"):
            continue
        n = int(key)
        e = npcs.setdefault(n, {"name": None, "sub": None, "faction": None, "pos": None, "areas": []})
        for field in ("name", "sub", "faction", "areas"):
            if field in patch:
                e[field] = patch[field]
        if "map" in patch:
            e["pos"] = {"map": patch["map"], "x": patch.get("x"), "y": patch.get("y"), "spawns": 1}
        elif "instance" in patch:
            e["pos"] = {"instance": patch["instance"]}


def category_tree(recipes, categories):
    """Used categories plus all their ancestors, or {} if the table isn't available."""
    if not categories:
        return {}
    keep = {}
    for r in recipes:
        c = r["category"]
        while c and c in categories and c not in keep:
            keep[c] = categories[c]
            c = categories[c]["parent"]
    return keep


def unlisted_recipe_spells(recipes, ranks, sla):
    """Profession spells with a recipe category in the client table but missing from WT."""
    known = {r["spell"] for r in recipes} | {r["spell"] for r in ranks}
    out = []
    for spell, rows in sla.items():
        for row in rows:
            if row["skillLine"] in PROFESSIONS and row["category"] and spell not in known:
                out.append((row["skillLine"], spell, row["category"]))
                break
    return sorted(out)


def build(wt_recipes, wt_ranks, fdb, sla, categories, overrides):
    recipes = [merge_recipe(r, fdb, sla) for r in wt_recipes]
    applied = apply_overrides(recipes, overrides or {})
    npcs, objects, quests = build_entities(recipes, fdb)
    apply_npc_overrides(npcs, overrides or {})
    return {
        "recipes": recipes,
        "ranks": wt_ranks,
        "npcs": npcs,
        "objects": objects,
        "quests": quests,
        "categories": category_tree(recipes, categories),
        "categoriesAvailable": bool(categories),
        "overridesApplied": applied,
        "unlisted": unlisted_recipe_spells(wt_recipes, wt_ranks, sla),
    }
