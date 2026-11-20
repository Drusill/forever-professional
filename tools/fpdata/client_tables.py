"""Forever client tables (wago.tools CSV exports): SkillLineAbility and TradeSkillCategory."""
import csv
import glob
import os


def _read_csv(path):
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def find_table(folder, table, build=None):
    """Path of ``<table>.<build>.csv`` (or the newest build present), or None."""
    if not folder or not os.path.isdir(folder):
        return None
    if build:
        p = os.path.join(folder, "%s.%s.csv" % (table, build))
        if os.path.exists(p):
            return p
    files = sorted(glob.glob(os.path.join(folder, table + ".[0-9]*.csv")))
    return files[-1] if files else None


def _int(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


def load_skill_line_abilities(path):
    """spell -> list of rows {skillLine, minRank, trivialLow, trivialHigh, category, acquire}."""
    out = {}
    for row in _read_csv(path):
        spell = _int(row.get("Spell"))
        if not spell:
            continue
        out.setdefault(spell, []).append({
            "skillLine": _int(row.get("SkillLine")),
            "minRank": _int(row.get("MinSkillLineRank")),
            "trivialLow": _int(row.get("TrivialSkillLineRankLow")),
            "trivialHigh": _int(row.get("TrivialSkillLineRankHigh")),
            "category": _int(row.get("TradeSkillCategoryID")),
            "acquire": _int(row.get("AcquireMethod")),
            "skillupLine": _int(row.get("SkillupSkillLineID")),
        })
    return out


def load_trade_skill_categories(path):
    """id -> {name, parent, skillLine, order}. Column names follow wago.tools exports."""
    out = {}
    for row in _read_csv(path):
        cid = _int(row.get("ID"))
        if not cid:
            continue
        out[cid] = {
            "name": row.get("Name_lang") or row.get("Name") or "",
            "parent": _int(row.get("ParentTradeSkillCategoryID")),
            "skillLine": _int(row.get("SkillLineID")),
            "order": _int(row.get("OrderIndex")),
        }
    return out
