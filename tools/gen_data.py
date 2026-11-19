"""Write Data.lua, the addon's static data, from EverlookDB's own data.

    python tools/gen_data.py [--guides D:/Dev/Quarry/web/data/guides.json] [--offline]

What it reads:
  * Quarry's web/data/guides.json, "pets" section: the tameable families (diet, icon, abilities) and every ability
    with its ranks (pet level needed, spell id, trainer or not, new in WoW Forever or not). Names in other languages
    come from the game itself at run time (C_Spell.GetSpellName, UnitCreatureFamily, C_Map.GetMapInfo), so the
    localized copies of guides.json aren't needed.
  * The tameable beasts (npc id, family, levels, English name, classification, display id, main zone) from the
    site's query API:
    https://everlookdb.com/api/v1/query?q=npcs | where tameable == 1 ...
    With --offline, or when the site can't be reached, it falls back to classic-db (Quarry's state/classicdb.sqlite,
    creatures with the tameable flag), and if that is missing too it keeps the list already in Data.lua.

  * Which beast teaches which ability rank: Quarry's web/data/bestiary.json (crates/build/src/bestiary.rs there), the
    merge of WoW Forever players' tames (EG Link, Forever Hunter Pets, BeastScout; later our own Collector) with
    classic data (VMaNGOS pet_spell_data) where nobody has reported a beast yet. Each rank carries a state: 3 confirmed
    (two sources agree or several tames), 2 seen (one WoW Forever source), 1 classic. We keep per beast its levels,
    main zone, English name, ranks with state and attack speed, and per rank its beasts best first; nothing else, so
    Data.lua stays small. Without the file the addon falls back to the site link.
  * For the bestiary browser (D.wild): where each tameable beast spawns, from Forever Hunter Pets' coordinates (MIT,
    seen in WoW Forever) or else classic-db's spawn points (Quarry's web/data/classicdb.json, GPL-3.0), merged into a
    few spots per zone. Zone names and continents: the WoW Forever client's UiMap table (ForeverMiner's
    out/tables/UiMap.csv) and the bestiary's zone list.
  * Training points per ability rank (D.training): Forever Hunter Pets' Beast Training readings (MIT), else the highest
    cost EG Link players' Beast Training showed (CC BY 4.0).
"""
import argparse
import csv
import json
import re
import sqlite3
import sys
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QUARRY = Path(r"D:\Dev\Quarry")
OUT = ROOT / "Data.lua"
# The site's food names, in the bit order of CreatureFamily.PetFoodMask (web/pets.js)
FOODS = ["Meat", "Fish", "Cheese", "Bread", "Fungus", "Fruit", "Raw meat", "Raw fish"]
API = "https://everlookdb.com/api/v1/query?q="
RANKS = {"normal": 0, "elite": 1, "rare": 2, "rareelite": 3}
STATE = {"confirmed": 3, "seen": 2, "classic": 1}


def lua_str(s: str) -> str:
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        print(f"no {path}", file=sys.stderr)
        return {}


def tameable_from_api(families: dict, info: dict) -> dict:
    """npc id -> (family id, lo, hi); fills info[npc id] = (name, rank code, display id, main zone name)."""
    q = ("npcs | where tameable == 1 | project id, level, maxlevel, family, name, classification, display, zone"
         " | take 5000")
    req = urllib.request.Request(API + urllib.parse.quote(q), headers={"User-Agent": "everlookpets-gen-data"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)
    out = {}
    for npc, lvl, maxlvl, fam, name, cls, display, zone in data["result"]["rows"]:
        fid = families.get(fam)
        if fid:
            out[int(npc)] = (fid, int(lvl or 0), int(maxlvl or lvl or 0))
            info[int(npc)] = (name or "", RANKS.get(cls, 0), int(display or 0), zone or "")
    return out


def tameable_from_classicdb(db: Path) -> dict:
    c = sqlite3.connect(db)
    rows = c.execute("select Entry, Family, MinLevel, MaxLevel from creature_template "
                     "where CreatureType = 1 and Family > 0 and (CreatureTypeFlags & 1)")
    return {int(e): (int(f), int(a), int(b)) for e, f, a, b in rows}


def tameable_from_existing() -> dict:
    if not OUT.exists():
        return {}
    text = OUT.read_text(encoding="utf-8")
    return {int(m[0]): (int(m[1]), int(m[2]), int(m[3])) for m in re.findall(r"\[(\d+)\]=\{(\d+),(\d+),(\d+)\}", text)}


def uimaps(path: Path) -> dict:
    """uiMap id -> (English name, parent id, type) from the client's UiMap table."""
    out = {}
    try:
        with open(path, encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f):
                out[int(r["ID"])] = (r["Name_lang"], int(r["ParentUiMapID"] or 0), int(r["Type"] or 0))
    except OSError:
        print(f"no {path}: zone names from the bestiary only", file=sys.stderr)
    return out


def continent_of(maps: dict, m: int) -> int:
    for _ in range(8):
        e = maps.get(m)
        if not e:
            return 0
        if e[2] == 2:
            return m
        m = e[1]
    return 0


def spots(points: list, cell: float = 4.0, per_zone: int = 3, most: int = 6) -> list:
    """[[map, x, y], ...] (percent) -> [(map, [(x10, y10), ...]), ...]: points merged into cells of `cell` percent,
    the busiest cells first, at most `per_zone` per zone and `most` in all; x and y in tenths of a percent."""
    cells = {}
    for p in points:
        if not isinstance(p, list) or len(p) < 3:
            continue
        m, x, y = int(p[0]), float(p[1]), float(p[2])
        if not (0 <= x <= 100 and 0 <= y <= 100):
            continue
        c = cells.setdefault((m, int(x // cell), int(y // cell)), [0, 0.0, 0.0])
        c[0] += 1
        c[1] += x
        c[2] += y
    zones = {}
    for (m, _, _), (n, sx, sy) in sorted(cells.items(), key=lambda kv: (-kv[1][0], kv[0])):
        zones.setdefault(m, []).append((n, round(sx / n * 10), round(sy / n * 10)))
    order = sorted(zones, key=lambda m: (-sum(c[0] for c in zones[m]), m))
    out, left = [], most
    for m in order:
        if left <= 0:
            break
        keep = zones[m][:min(per_zone, left)]
        left -= len(keep)
        out.append((m, [(x, y) for _, x, y in keep]))
    return out


def collector_npc(npc: int, offline: bool) -> dict:
    """What players' EverlookDB Collector uploads saw of one creature (levels, positions), {} when nothing yet."""
    if offline:
        return {}
    base = API.split("/api/")[0]
    req = urllib.request.Request(f"{base}/api/v1/crowd/npc/{npc}", headers={"User-Agent": "everlookpets-gen-data"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except Exception:
        return {}


def collector_points(c: dict) -> list:
    """Collector positions ({map, cells: [[x, y, n], ...]} in tenths of a percent) -> [[map, x, y], ...] percent."""
    return [[p["map"], x / 10, y / 10] for p in c.get("positions") or [] for x, y, *_ in p.get("cells") or []]


def wild_rows(tame: dict, info: dict, data_dir: Path, maps: dict, used: set, offline: bool = False) -> list:
    """D.wild lines: per tameable beast its English name, rank, model and where it spawns."""
    classic = load_json(data_dir / "classicdb.json").get("npcs", {})
    jazz = load_json(data_dir / "jazzman.json").get("beasts", {})
    # where EG Link players met each creature in WoW Forever (CC BY 4.0): the only spots for WoW Forever's new beasts
    eg = load_json(data_dir / "eglink.json").get("npcs", {})
    by_name = {}
    for mid, (name, _, typ) in sorted(maps.items()):
        if typ in (3, 4, 5) and name not in by_name:
            by_name[name] = mid
    rows = []
    for npc in sorted(tame):
        name, rank, display, zone = info.get(npc, ("", 0, 0, ""))
        c = classic.get(str(npc), {})
        if npc not in info:
            name = c.get("name", "")
            rank = {1: 1, 2: 3, 4: 2}.get(c.get("rank", 0), 0)
        jz = jazz.get(str(npc), {})
        src, groups = 0, []
        if jz.get("at"):
            src, groups = 1, spots(jz["at"])
        elif eg.get(str(npc), {}).get("at"):
            src, groups = 1, spots([p for p in eg[str(npc)]["at"] if len(p) >= 3])
        elif c.get("at"):
            groups = spots(c["at"])
        if not groups:
            # last: where our own Collector's players saw it (WoW Forever)
            pts = collector_points(collector_npc(npc, offline))
            if pts:
                src, groups = 1, spots(pts)
        places = []
        for m, pts in groups:
            used.add(m)
            places.append("{ " + ", ".join([str(m)] + [f"{x}, {y}" for x, y in pts]) + " }")
        if not places and zone:
            if zone in by_name:
                used.add(by_name[zone])
                places.append(f"{{ {by_name[zone]} }}")
            else:
                places.append(f"{{ {lua_str(zone)} }}")
        rows.append(f"\t[{npc}] = {{ {lua_str(name)}, {rank}, {display}, {src}, {{ {', '.join(places)} }} }},")
    return rows


def training_costs(data_dir: Path) -> dict:
    """spell id -> the training points Beast Training asks for that rank."""
    jz = load_json(data_dir / "jazzman.json").get("training", {})
    eg = load_json(data_dir / "eglink.json").get("hunter_pets", {}).get("training", {})
    cost = {}
    for sid, t in eg.items():
        seen = [int(k) for k in (t.get("costs") or {}) if str(k).isdigit() and int(k) > 0]
        if seen:
            cost[int(sid)] = max(seen)
    for sid, t in jz.items():
        if isinstance(t.get("tp"), int):
            cost[int(sid)] = t["tp"]
    return cost


def write_bestiary(w, b: dict, maps: dict, used: set) -> int:
    """D.zones, D.beasts and D.teachers from bestiary.json; empty tables when it is missing."""
    beasts = b.get("beasts", {})
    w(f"-- Who teaches what: EverlookDB's bestiary (build {b.get('build', '?')}): WoW Forever players' tames (EG Link,")
    w("-- Forever Hunter Pets, BeastScout) and classic data (VMaNGOS) where nobody has reported a beast yet.")
    w("-- States: 3 confirmed (two sources agree, or several tames), 2 seen (one WoW Forever source), 1 classic data.")
    for e in beasts.values():
        if e.get("z"):
            used.add(e["z"][0][0])
    w("-- uiMap id = { English name, continent uiMap id } (names in your language come from the game)")
    w("D.zones = {")
    for z in sorted(used):
        name, cont = b.get("zones", {}).get(str(z), ["", 0])
        if not name and z in maps:
            name, cont = maps[z][0], continent_of(maps, z)
        if name:
            w(f"\t[{z}] = {{ {lua_str(name)}, {cont} }},")
    w("}")
    w("-- npc id = { lowest level, highest level, main zone, English name, { spell, state, ... }, attack speed (0 unknown) }")
    w("D.beasts = {")
    for k in sorted(beasts, key=int):
        e = beasts[k]
        lo, hi = e.get("l", [0, 0])[:2]
        zone = e["z"][0][0] if e.get("z") else 0
        t = ", ".join(f"{sp}, {STATE.get(st, 1)}" for sp, st, _ in e.get("t", []))
        speed = e.get("s", [0])[0] or 0
        w(f"\t[{k}] = {{ {lo}, {hi}, {zone}, {lua_str(e.get('n', ''))}, {{ {t} }}, {speed} }},")
    w("}")
    w("-- spell id = { npc ids that teach it, best first: confirmed, seen, classic; then lowest level }")
    w("D.teachers = {")
    for sp in sorted(b.get("ranks", {}), key=int):
        w(f"\t[{sp}] = {{ {', '.join(str(n) for n in b['ranks'][sp])} }},")
    w("}")
    return len(beasts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--guides", default=str(QUARRY / "web" / "data" / "guides.json"))
    ap.add_argument("--classicdb", default=str(QUARRY / "state" / "classicdb.sqlite"))
    ap.add_argument("--bestiary", default=str(QUARRY / "web" / "data" / "bestiary.json"))
    ap.add_argument("--uimap", default=r"D:\Dev\ForeverMiner\out\tables\UiMap.csv")
    ap.add_argument("--offline", action="store_true")
    a = ap.parse_args()

    guides_path = Path(a.guides)
    g = json.loads(guides_path.read_text(encoding="utf-8"))
    pets, spells = g["pets"], g["spells"]
    fam_ids = {f["key"]: f["id"] for f in pets["families"]}

    tame, source, info = {}, "", {}
    if not a.offline:
        try:
            tame, source = tameable_from_api(fam_ids, info), "everlookdb.com query API (tameable == 1)"
        except Exception as e:  # noqa: BLE001 - any network trouble: fall back
            print(f"site API failed ({e}); trying classic-db", file=sys.stderr)
    if not tame and Path(a.classicdb).exists():
        tame, source = tameable_from_classicdb(Path(a.classicdb)), "classic-db (tameable flag)"
    if not tame:
        tame, source = tameable_from_existing(), "kept from the previous Data.lua"

    data_dir = Path(a.bestiary).parent
    best = load_json(Path(a.bestiary))
    if not best:
        print(f"no {a.bestiary}: no bestiary in Data.lua (Where? links the site instead)", file=sys.stderr)
    # WoW Forever's own beasts have no level in classic-db: take the levels players' tames reported (bestiary.json)
    for npc, (fam, lo, hi) in list(tame.items()):
        if not lo:
            l = ((best or {}).get("beasts", {}).get(str(npc), {}).get("l") or [0, 0])[:2]
            if not l[0] and not a.offline:
                l = (collector_npc(npc, False).get("level") or [0, 0])[:2]
            if l and l[0]:
                tame[npc] = (fam, l[0], l[1] if len(l) > 1 and l[1] else l[0])
    maps = uimaps(Path(a.uimap))
    used = set()
    wild = wild_rows(tame, info, data_dir, maps, used, a.offline)
    costs = training_costs(data_dir)

    L = []
    w = L.append
    w("-- Generated by tools/gen_data.py from EverlookDB's data. Do not edit by hand: run the script again.")
    w(f"-- Pets: Quarry web/data/guides.json (build {g.get('build', '?')}). Tameable beasts: {source}.")
    w("-- Spell names and icons are read from the game at run time (localized); these English names are the fallback.")
    w("local _, ns = ...")
    w("local D = {}")
    w("ns.Data = D")
    w(f"D.build = {lua_str(g.get('build', ''))}")
    w(f"D.generated = {lua_str(date.today().isoformat())}")
    w("D.foods = { " + ", ".join(lua_str(x) for x in FOODS) + " }")
    w("D.families = {")
    for f in pets["families"]:
        abil = ", ".join(lua_str(x) for x in f["abilities"])
        w(f"\t[{f['id']}] = {{ key = {lua_str(f['key'])}, petopia = {lua_str(f['petopia'])}, icon = {f['icon']}, "
          f"diet = {f['diet']}, abilities = {{ {abil} }} }},")
    w("}")
    w("D.abilities = {")
    for ab in pets["abilities"]:
        first = spells.get(str(ab["ranks"][0]["spell"]), {})
        ranks = ", ".join(
            f"{{ rank = {r['rank']}, level = {r['level']}, spell = {r['spell']}"
            + (", forever = true" if r.get("forever") else "") + " }"
            for r in ab["ranks"])
        w(f"\t[{lua_str(ab['key'])}] = {{ name = {lua_str(first.get('name') or ab['key'])}, petopia = {lua_str(ab['petopia'])}, "
          f"trainer = {str(bool(ab['trainer'])).lower()}, forever = {str(bool(ab['forever'])).lower()}, "
          f"icon = {first.get('icon') or 'nil'}, families = {{ {', '.join(str(x) for x in ab['families'])} }},")
        w(f"\t\tranks = {{ {ranks} }} }},")
    w("}")
    w("-- npc id = { family id, lowest level, highest level }")
    w("D.tameable = {")
    items = [f"[{n}]={{{v[0]},{v[1]},{v[2]}}}" for n, v in sorted(tame.items())]
    for i in range(0, len(items), 8):
        w("\t" + ",".join(items[i:i + 8]) + ",")
    w("}")
    nb = write_bestiary(w, best, maps, used)
    w("-- The bestiary browser: npc id = { English name, rank (0 normal, 1 elite, 2 rare, 3 rare elite), display id")
    w("-- (0 unknown), spots from (1 WoW Forever players: Forever Hunter Pets, MIT, EG Link, CC BY 4.0, or our Collector; 0 classic-db, GPL-3.0),")
    w("-- { { uiMap, x, y, x, y... }, ... } } with x and y in tenths of a percent of that map. A zone without spots is")
    w("-- { uiMap } or { \"name\" } (an instance).")
    w("D.wild = {")
    for r in wild:
        w(r)
    w("}")
    w("-- Training points per ability rank (Beast Training): Forever Hunter Pets (MIT), else EG Link (CC BY 4.0).")
    w("D.training = {")
    items = [f"[{k}]={v}" for k, v in sorted(costs.items())]
    for i in range(0, len(items), 10):
        w("\t" + ", ".join(items[i:i + 10]) + ",")
    w("}")
    OUT.write_text("\n".join(L) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {OUT}: {len(pets['families'])} families, {len(pets['abilities'])} abilities, "
          f"{len(tame)} tameable beasts ({source}), {nb} beasts in the bestiary, {len(wild)} in the browser, "
          f"{len(costs)} training costs; {OUT.stat().st_size // 1024} KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
