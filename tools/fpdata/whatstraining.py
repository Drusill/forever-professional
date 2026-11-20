"""Read WhatsTraining's Forever recipe data (Crafting/Recipes/Camelot/*.lua, MIT)."""
import glob
import os

from .luaparse import Ref, find_assignments

# Profession rank-up spells (Apprentice -> Journeyman ...) live in the same lists; they
# aren't recipes and are returned separately.


def _as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return v
    if isinstance(v, dict):  # mixed table: positional part only
        return [v[k] for k in sorted(k for k in v if isinstance(k, int))]
    return [v]


def normalize(entry, skill_line):
    """Turn one WhatsTraining entry into a plain dict with predictable types."""
    r = {
        "spell": int(entry["spell"]),
        "skillLine": skill_line,
        "learn": entry.get("skill"),
        "creates": entry.get("creates"),
        "count": entry.get("count"),
        "teach": entry.get("teach"),
        "sources": [s for s in _as_list(entry.get("source")) if isinstance(s, str)],
        "trainerCost": entry.get("cost"),
        "bound": entry.get("bound"),
        "side": entry.get("side"),
        "merchantFavor": entry.get("merchantFavor"),
        "autoLearned": bool(entry.get("autoLearned")),
        "rank": entry.get("rank"),
        "level": entry.get("level"),
        "reputation": None,
        "vendors": [],
        "quests": [],
    }
    rep = entry.get("reputation")
    if rep:
        rep = _as_list(rep)
        nums = [x for x in rep if isinstance(x, int) and not isinstance(x, bool)]
        if len(nums) >= 2:
            r["reputation"] = {"faction": nums[0], "standing": nums[1]}
    for v in _as_list(entry.get("vendors")):
        if not isinstance(v, dict) or "npc" not in v:
            continue
        areas = _as_list(v.get("areas")) or ([v["area"]] if v.get("area") else [])
        r["vendors"].append({"npc": int(v["npc"]), "areas": [int(a) for a in areas], "faction": v.get("faction")})
    for q in _as_list(entry.get("quests")):
        if not isinstance(q, dict) or "id" not in q:
            continue
        r["quests"].append({"id": int(q["id"]), "area": q.get("area"), "faction": q.get("faction"), "level": q.get("level")})
    for k, v in list(r.items()):
        if isinstance(v, Ref):
            r[k] = None
    return r


def load_file(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    out = []
    for m, entries in find_assignments(text, r"ns\.Recipes\[(\d+)\]"):
        skill_line = int(m.group(1))
        for e in _as_list(entries):
            if isinstance(e, dict) and "spell" in e:
                out.append(normalize(e, skill_line))
    return out


def load(folder):
    """Return (recipes, ranks) from every *.lua file in ``folder``, in file order."""
    recipes, ranks = [], []
    for path in sorted(glob.glob(os.path.join(folder, "*.lua"))):
        for r in load_file(path):
            (ranks if r["rank"] else recipes).append(r)
    return recipes, ranks
