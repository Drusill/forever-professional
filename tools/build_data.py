#!/usr/bin/env python3
"""Build ForeverProfessional's baked data from pinned upstream sources.

Usage (from the repo root):
  python tools/build_data.py            fetch what's missing from tools/.cache, then build
  python tools/build_data.py update     move the pins to the newest upstream data, then build
  python tools/build_data.py build      build from the cache only (no network)
  python tools/build_data.py fetch      download only

Options:
  --out DIR              output folder (default: ForeverProfessional/Data)
  --whatstraining DIR    read WhatsTraining's Camelot recipe files from DIR instead of the pin
                         (e.g. your installed addon: ...\\AddOns\\WhatsTraining\\Crafting\\Recipes\\Camelot)
  --no-locales           skip the localized name files

Outputs: the Lua data files, tools/REPORT.md, and tools/sources.lock.json (on update).
Only the Python standard library is needed (3.9+).
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from fpdata import client_tables, emit_lua, fetch, merge, report, whatstraining  # noqa: E402
from fpdata.foreverdb import ForeverDB  # noqa: E402

REPO = os.path.dirname(HERE)
DEFAULT_OUT = os.path.join(REPO, "ForeverProfessional", "Data")


def collect_locales(catalog, fdb):
    out = {}
    for loc in fdb.locales():
        if loc == "enUS":
            continue
        names = {}
        for kind, ids, enus in (("npc", catalog["npcs"], lambda i: catalog["npcs"][i]["name"]),
                                ("obj", catalog["objects"], lambda i: catalog["objects"][i]["name"]),
                                ("quest", catalog["quests"], lambda i: catalog["quests"][i]["name"])):
            m = {}
            for i in ids:
                name = fdb.localized(loc, kind, i)
                if name and name != enus(i):
                    m[i] = name
            names[kind] = m
        if any(names.values()):
            out[loc] = names
    return out


def run_build(lock, args):
    wt_dir = args.whatstraining or fetch.whatstraining_dir(lock)
    recipes, ranks = whatstraining.load(wt_dir)
    if not recipes:
        raise SystemExit("No WhatsTraining recipes found in %s" % wt_dir)

    att = lock["allthethings"]
    sla_path = client_tables.find_table(fetch.allthethings_dir(lock), "SkillLineAbility", att["build"])
    if not sla_path:
        raise SystemExit("SkillLineAbility CSV missing; run `python tools/build_data.py fetch`")
    sla = client_tables.load_skill_line_abilities(sla_path)

    tsc_path = client_tables.find_table(fetch.wago_dir(lock), "TradeSkillCategory", lock["wago"]["build"])
    categories = client_tables.load_trade_skill_categories(tsc_path) if tsc_path else {}

    fdb_path = fetch.foreverdb_path(lock)
    if not os.path.exists(fdb_path):
        raise SystemExit("forever.json.gz missing; run `python tools/build_data.py fetch`")
    fdb = ForeverDB.load(fdb_path)
    if lock["foreverdb"].get("hash") and fdb.meta.get("hash") != lock["foreverdb"]["hash"]:
        raise SystemExit("Cached forever.json.gz (hash %s) doesn't match the lock (%s). Run fetch or update."
                         % (fdb.meta.get("hash"), lock["foreverdb"]["hash"]))

    with open(os.path.join(HERE, "overrides.json"), encoding="utf-8") as f:
        overrides = json.load(f)

    catalog = merge.build(recipes, ranks, fdb, sla, categories, overrides)
    catalog["locales"] = {} if args.no_locales else collect_locales(catalog, fdb)

    wt_pin = ("local folder" if args.whatstraining else "%s@%s" % (lock["whatstraining"]["repo"], lock["whatstraining"]["ref"][:12]))
    meta = {
        "client": att["build"],
        "sources": {
            "WhatsTraining": wt_pin,
            "AllTheThings client tables": "%s@%s (%s)" % (att["repo"], att["ref"][:12], att["build"]),
            "ForeverDB": "%s build %s, hash %s" % (lock["foreverdb"]["repo"], fdb.meta.get("build"), fdb.meta.get("hash")),
            "wago.tools TradeSkillCategory": lock["wago"]["build"] if categories else "not available",
        },
    }
    build_label = "ForeverDB %s, client %s" % (fdb.meta.get("build"), att["build"])
    files = emit_lua.emit(catalog, args.out, build_label, meta)
    text = report.build_report(catalog, meta, fdb)
    with open(os.path.join(HERE, "REPORT.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

    rs = catalog["recipes"]
    print("Built %d recipes (%d new), %d NPCs, %d quests, %d objects -> %s (%d files)" % (
        len(rs), sum(r["new"] for r in rs), len(catalog["npcs"]), len(catalog["quests"]),
        len(catalog["objects"]), os.path.relpath(args.out, REPO), len(files)))
    print("Unknown source: %d. Unverified claims: %d. Categories: %s. Report: tools/REPORT.md" % (
        sum(r["unknown"] for r in rs), sum(bool(r["unverified"]) for r in rs),
        len(catalog["categories"]) if categories else "IDs only"))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", nargs="?", default="all", choices=["all", "update", "build", "fetch"])
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--whatstraining")
    ap.add_argument("--no-locales", action="store_true")
    ap.add_argument("--force", action="store_true", help="re-download cached files")
    args = ap.parse_args(argv)

    lock = fetch.load_lock()
    if args.command in ("all", "update", "fetch"):
        fetch.fetch_all(lock, update=args.command == "update", force=args.force)
        if args.command == "update":
            fetch.save_lock(lock)
    if args.command != "fetch":
        run_build(lock, args)


if __name__ == "__main__":
    main()
