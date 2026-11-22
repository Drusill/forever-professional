"""Download upstream sources into tools/.cache, pinned by tools/sources.lock.json.

Sources:
  whatstraining  fusionpit/WhatsTraining (MIT): Crafting/Recipes/Camelot/*.lua, by commit
  allthethings   ATTWoWAddon/AllTheThings (MIT): Forever client tables (wago.tools CSV), by commit
  foreverdb      foreverfraddons/forever-db (GPL-3.0): forever.json.gz from the rolling `latest`
                 release, pinned by its meta.hash (versioned releases don't carry the file)
  wago           wago.tools DB2 CSV exports for tables AllTheThings doesn't ship (optional)
"""
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request

TOOLS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_DIR = os.path.join(TOOLS_DIR, ".cache")
LOCK_PATH = os.path.join(TOOLS_DIR, "sources.lock.json")
RAW = "https://raw.githubusercontent.com/{repo}/{ref}/{path}"
FDB_URL = "https://github.com/{repo}/releases/download/latest/{asset}"
WAGO_URL = "https://wago.tools/db2/{table}/csv?build={build}"
USER_AGENT = "forever-professional-data-pipeline"


def log(msg):
    print(msg, file=sys.stderr)


def load_lock(path=LOCK_PATH):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_lock(lock, path=LOCK_PATH):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(lock, f, indent=2, sort_keys=False)
        f.write("\n")


def download(url, dest, timeout=120):
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    tmp = dest + ".part"
    with urllib.request.urlopen(req, timeout=timeout) as r, open(tmp, "wb") as f:
        shutil.copyfileobj(r, f)
    os.replace(tmp, dest)
    return dest


def latest_commit(repo, branch=None):
    """Newest commit of a GitHub repo's default branch, via `git ls-remote` (no API token)."""
    ref = "refs/heads/" + branch if branch else "HEAD"
    out = subprocess.run(["git", "ls-remote", "https://github.com/%s" % repo, ref],
                         capture_output=True, text=True, timeout=120, check=True).stdout
    return out.split()[0]


def cache_path(*parts):
    return os.path.join(CACHE_DIR, *parts)


def whatstraining_dir(lock):
    s = lock["whatstraining"]
    return cache_path("whatstraining", s["ref"][:12])


def allthethings_dir(lock):
    s = lock["allthethings"]
    return cache_path("allthethings", s["ref"][:12])


def foreverdb_path(lock):
    return cache_path("foreverdb", "forever.json.gz")


def wago_dir(lock):
    return cache_path("wago", lock["wago"]["build"])


def fetch_whatstraining(lock, force=False):
    s = lock["whatstraining"]
    out = whatstraining_dir(lock)
    for name in s["files"]:
        dest = os.path.join(out, name)
        if force or not os.path.exists(dest):
            download(RAW.format(repo=s["repo"], ref=s["ref"], path=s["path"] + "/" + name), dest)
    log("whatstraining: %d files @ %s" % (len(s["files"]), s["ref"][:12]))


def fetch_allthethings(lock, force=False):
    s = lock["allthethings"]
    out = allthethings_dir(lock)
    for table in s["tables"]:
        name = "%s.%s.csv" % (table, s["build"])
        dest = os.path.join(out, name)
        if force or not os.path.exists(dest):
            download(RAW.format(repo=s["repo"], ref=s["ref"], path=s["path"] + "/" + name), dest)
    for name in ("LICENSE",):
        dest = os.path.join(out, name)
        if force or not os.path.exists(dest):
            download(RAW.format(repo=s["repo"], ref=s["ref"], path=name), dest)
    log("allthethings: %s @ %s" % (", ".join(s["tables"]), s["ref"][:12]))


def foreverdb_meta(path):
    with gzip.open(path, "rt", encoding="utf-8") as f:
        meta = json.load(f)["meta"]
    return meta


def file_sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_foreverdb(lock, update=False):
    """Download `latest`. With update=False, keep a cached copy whose hash matches the lock."""
    s = lock["foreverdb"]
    dest = foreverdb_path(lock)
    if not update and os.path.exists(dest) and foreverdb_meta(dest).get("hash") == s.get("hash"):
        log("foreverdb: cached, hash %s" % s["hash"])
        return
    tmp = dest + ".new"
    download(FDB_URL.format(repo=s["repo"], asset=s["asset"]), tmp)
    meta = foreverdb_meta(tmp)
    if not update and s.get("hash") and meta.get("hash") != s["hash"]:
        os.remove(tmp)
        raise SystemExit(
            "foreverdb: the published file changed (hash %s, lock pins %s).\n"
            "Run `python tools/build_data.py update` to move the pin, then rebuild."
            % (meta.get("hash"), s["hash"]))
    os.replace(tmp, dest)
    s["hash"], s["build"] = meta.get("hash"), meta.get("build")
    log("foreverdb: downloaded, build %s hash %s" % (s["build"], s["hash"]))


def fetch_wago(lock, force=False):
    """Optional tables; failures are reported, not fatal (the build degrades gracefully)."""
    s = lock["wago"]
    out = wago_dir(lock)
    got = []
    for table in s["tables"]:
        dest = os.path.join(out, "%s.%s.csv" % (table, s["build"]))
        if os.path.exists(dest) and not force:
            got.append(table)
            continue
        try:
            download(WAGO_URL.format(table=table, build=s["build"]), dest)
            got.append(table)
        except (urllib.error.URLError, OSError) as e:
            log("wago: could not fetch %s (%s). Categories will have IDs but no names." % (table, e))
    if got:
        log("wago: %s @ %s" % (", ".join(got), s["build"]))


def fetch_all(lock, update=False, force=False):
    if update:
        for key in ("whatstraining", "allthethings"):
            s = lock[key]
            try:
                new = latest_commit(s["repo"], s.get("branch"))
            except (OSError, subprocess.SubprocessError) as e:
                log("%s: could not check for updates (%s); keeping %s" % (key, e, s["ref"][:12]))
                continue
            if new != s["ref"]:
                log("%s: %s -> %s" % (key, s["ref"][:12], new[:12]))
                s["ref"] = new
    fetch_whatstraining(lock, force)
    fetch_allthethings(lock, force)
    fetch_foreverdb(lock, update=update)
    fetch_wago(lock, force)
    return lock
