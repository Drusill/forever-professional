"""Accessors for ForeverDB's master export (forever.json.gz, GPL-3.0).

Relevant tables (keys are strings in the JSON):
  item[id]   [name, quality, ..., class(4), subclass(5), ...]   recipes are class 9
  ieff[id]   [[spell, trigger, ...]]  trigger 6 = spell taught by using the item
  drop/odrop/idrop[item]  [[npc|object|container, chance per 10000]]  0 = unknown
  vend[item] [npc, ...]       rew[item] [quest, ...]
  npc[id]    [name, subname, minLevel, maxLevel, rank]     nfac[id] "A" | "H" | "AH"
  obj[id]    [name]           quest[id] [name, level, minLevel]   qg[quest] ["c123", "o45"]
  spz["c<npc>" | "o<obj>"]  {uiMap: [x, y, x, y, ...]}  0-1000 map coordinates
  spw["c<npc>" | "o<obj>"]  [[instanceMap, x, y, ...]]   world coordinates
  loc[locale][npc|obj|quest|item][id]  localized names
"""
import gzip
import json

LEARN_TRIGGER = 6
RECIPE_ITEM_CLASS = 9


class ForeverDB:
    def __init__(self, data):
        self.d = data
        self.meta = data.get("meta", {})
        self._spell_items = None

    @classmethod
    def load(cls, path):
        with gzip.open(path, "rt", encoding="utf-8") as f:
            return cls(json.load(f))

    def _get(self, table, key):
        return self.d.get(table, {}).get(str(key))

    # items -------------------------------------------------------------
    def item(self, item_id):
        return self._get("item", item_id)

    def item_name(self, item_id):
        it = self.item(item_id)
        return it[0] if it else None

    def is_recipe_item(self, item_id):
        it = self.item(item_id)
        return bool(it) and len(it) > 4 and it[4] == RECIPE_ITEM_CLASS

    def spell_items(self):
        """spell -> sorted recipe item IDs that teach it (ItemEffect trigger 6)."""
        if self._spell_items is None:
            m = {}
            for item_id, effects in self.d.get("ieff", {}).items():
                for e in effects:
                    if len(e) > 1 and e[1] == LEARN_TRIGGER:
                        m.setdefault(int(e[0]), set()).add(int(item_id))
            self._spell_items = {k: sorted(v) for k, v in m.items()}
        return self._spell_items

    def teaching_items(self, spell):
        return [i for i in self.spell_items().get(int(spell), []) if self.is_recipe_item(i)]

    # sources -----------------------------------------------------------
    def vendors(self, item_id):
        return [int(n) for n in self._get("vend", item_id) or []]

    def drops(self, item_id):
        """[(npc, chance%|None)], excluding NPCs that also sell the item (merge artifact)."""
        sellers = set(self.vendors(item_id))
        out = []
        for npc, chance in self._get("drop", item_id) or []:
            if int(npc) in sellers:
                continue
            out.append((int(npc), chance / 100.0 if chance else None))
        return out

    def object_drops(self, item_id):
        return [(int(o), c / 100.0 if c else None) for o, c in self._get("odrop", item_id) or []]

    def container_drops(self, item_id):
        return [(int(i), c / 100.0 if c else None) for i, c in self._get("idrop", item_id) or []]

    def quest_rewards(self, item_id):
        return [int(q) for q in self._get("rew", item_id) or []]

    # entities ----------------------------------------------------------
    def npc(self, npc_id):
        return self._get("npc", npc_id)

    def npc_faction(self, npc_id):
        return self._get("nfac", npc_id)

    def obj(self, obj_id):
        return self._get("obj", obj_id)

    def quest(self, quest_id):
        return self._get("quest", quest_id)

    def quest_givers(self, quest_id):
        return self._get("qg", quest_id) or []

    def localized(self, locale, kind, ident):
        return self.d.get("loc", {}).get(locale, {}).get(kind, {}).get(str(ident))

    def locales(self):
        return sorted(self.d.get("loc", {}))

    def position(self, kind, ident):
        """Best known position: {map, x, y, spawns} in percent (0-100), or {instance} or None.

        Picks the uiMap with the most spawn points and returns its first point; falls back to
        the instance map of world coordinates (e.g. dungeon bosses, which have no uiMap spot).
        """
        key = "%s%d" % (kind, int(ident))
        for table in ("spz", "spm"):
            spots = self.d.get(table, {}).get(key)
            if spots:
                ui_map, pts = max(spots.items(), key=lambda kv: (len(kv[1]), -int(kv[0])))
                if len(pts) >= 2:
                    return {"map": int(ui_map), "x": round(pts[0] / 10.0, 1), "y": round(pts[1] / 10.0, 1),
                            "spawns": len(pts) // 2}
        world = self.d.get("spw", {}).get(key)
        if world and world[0]:
            return {"instance": int(world[0][0])}
        return None

    def ui_map_name(self, ui_map):
        m = self._get("umap", ui_map)
        return m[0] if m else None
