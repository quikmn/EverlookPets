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
  * For the bestiary browser (D.wild): where each tameable beast spawns. Seen in WoW Forever first: Forever Hunter
    Pets' coordinates (MIT), EG Link's (CC BY 4.0) and our Collector's (the site's /api/v1/crowd/map/{id} per zone,
    cached a day in tools/.cache), weighted by how often players saw it there. classic-db's spawn points (Quarry's
    web/data/classicdb.json, GPL-3.0) only as secondary, marked older data: dropped where players see the beast anyway,
    and dropped as contradicted where players saw it often in that zone and never near that point (see DENSE).
    Merged into a few spots per zone, each one a real source point (check_spots). Zone names and continents: the WoW Forever client's UiMap table (ForeverMiner's
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
import time
import urllib.error
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


# Spots. Every spot we write is one of the source's own points (the densest point's neighbourhood, snapped to the
# member nearest its weighted centre), never an average of points in different places, so a waypoint always lands
# where a beast was seen or spawns. Player-seen spots (WoW Forever) carry how often they were seen; classic-db spots
# carry 0 ("older data, may be wrong").
RADIUS = 3.0        # percent of the map: points this close form one spot
NEAR = 6.0          # a classic-db spot this close to a player-seen point adds nothing (players see it there): dropped
DENSE = 20          # sightings of a beast in a zone from which player data overrules classic-db there: a classic-db spot
                    # farther than NEAR from every player-seen point in such a zone is contradicted and dropped. Below
                    # it the classic-db spot stays as secondary data: thin player data says little about where a beast
                    # isn't (Scorpashi Lasher: 8 sightings, all in the east, and its south-central camp is real).
PER_ZONE = 3        # player-seen spots per zone, and classic-db spots per zone
MOST = 8            # spots per beast in all (player-seen ones take the room first)


def clusters(points: list, r: float = RADIUS) -> list:
    """[(x, y, weight), ...] percent on one map -> [(weight, x, y), ...] heaviest first; x, y one of the points."""
    pts = [p for p in points if 0 <= p[0] <= 100 and 0 <= p[1] <= 100 and p[2] > 0]
    r2 = r * r
    near = [[j for j, q in enumerate(pts) if (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2 <= r2] for p in pts]
    dens = [sum(pts[j][2] for j in nb) for nb in near]
    taken, out = set(), []
    for i in sorted(range(len(pts)), key=lambda i: (-dens[i], -pts[i][2], pts[i][0], pts[i][1])):
        if i in taken:
            continue
        members = [j for j in near[i] if j not in taken]
        taken.update(members)
        w = sum(pts[j][2] for j in members)
        cx = sum(pts[j][0] * pts[j][2] for j in members) / w
        cy = sum(pts[j][1] * pts[j][2] for j in members) / w
        s = min(members, key=lambda j: ((pts[j][0] - cx) ** 2 + (pts[j][1] - cy) ** 2, j))
        out.append((w, pts[s][0], pts[s][1]))
    out.sort(key=lambda c: (-c[0], c[1], c[2]))
    return out


def by_map(points: list) -> dict:
    """[[map, x, y(, weight)], ...] -> {map: [(x, y, weight), ...]}."""
    out = {}
    for p in points:
        w = p[3] if len(p) > 3 else 1
        out.setdefault(int(p[0]), []).append((float(p[1]), float(p[2]), w))
    return out


def beast_spots(player: list, classic: list, stats: dict) -> list:
    """Player-seen and classic-db points ([[map, x, y(, weight)], ...] percent) -> [(map, [(x10, y10, n), ...])]
    with n the sightings of a player-seen spot and 0 for a classic-db one; zones with player data first."""
    P, C = by_map(player), by_map(classic)
    zones = {}
    for m in set(P) | set(C):
        pp = P.get(m, [])
        seen = sum(w for _, _, w in pp)
        ps = clusters(pp)[:PER_ZONE]
        cs = []
        for _, x, y in clusters(C.get(m, [])):
            if any((x - a) ** 2 + (y - b) ** 2 <= NEAR * NEAR for a, b, _ in pp):
                continue
            if seen >= DENSE:
                stats["contradicted"].add(stats["npc"])
                stats["dropped"] += 1
                continue
            if pp:
                stats["unconfirmed"].add(stats["npc"])
            cs.append((0, x, y))
        zones[m] = (seen, ps, cs[:PER_ZONE])
    order = sorted(zones, key=lambda m: (-zones[m][0], -len(zones[m][2]), m))
    keep, left = {}, MOST
    for part in (1, 2):
        for m in order:
            take = zones[m][part][:max(left, 0)]
            left -= len(take)
            keep.setdefault(m, []).extend(take)
    return [(m, [(round(x * 10), round(y * 10), min(int(w), 999)) for w, x, y in keep[m]]) for m in order if keep[m]]


def crowd_positions(maps: dict, offline: bool) -> dict:
    """npc id -> [[map, x, y, sightings], ...] percent: where players' EverlookDB Collector uploads saw each creature
    in WoW Forever, from the site's per-zone dump (/api/v1/crowd/map/{id}: every NPC seen on that map with its cells,
    x and y in tenths of a percent). One request per zone map, about 5 a second, Retry-After honoured; cached for a
    day in tools/.cache/crowd-maps.json (and used as it is when offline or the site can't be reached)."""
    cache = ROOT / "tools" / ".cache" / "crowd-maps.json"
    old = load_json(cache) if cache.exists() else {}
    if offline or old.get("date") == date.today().isoformat():
        data = old.get("maps", {})
    else:
        base, data = API.split("/api/")[0], {}
        for mid in sorted(m for m, (_, _, typ) in maps.items() if typ >= 3):
            for _ in range(4):
                req = urllib.request.Request(f"{base}/api/v1/crowd/map/{mid}", headers={"User-Agent": "everlookpets-gen-data"})
                try:
                    with urllib.request.urlopen(req, timeout=30) as r:
                        data[str(mid)] = [[n["id"], n["cells"]] for n in json.load(r).get("npcs", [])]
                    break
                except urllib.error.HTTPError as e:
                    if e.code != 429:
                        break
                    time.sleep(min(float(e.headers.get("Retry-After") or 10), 120))
                except Exception:  # noqa: BLE001 - network trouble: keep what the cache had for this map
                    if str(mid) in old.get("maps", {}):
                        data[str(mid)] = old["maps"][str(mid)]
                    break
            time.sleep(0.2)
        if data:
            cache.parent.mkdir(exist_ok=True)
            cache.write_text(json.dumps({"date": date.today().isoformat(), "maps": data}), encoding="utf-8")
        else:
            data = old.get("maps", {})
    out = {}
    for mid, npcs in data.items():
        for npc, cells in npcs:
            out.setdefault(int(npc), []).extend([int(mid), x / 10, y / 10, n] for x, y, n in cells)
    return out


def wild_rows(tame: dict, info: dict, data_dir: Path, maps: dict, used: set, stats: dict, offline: bool = False) -> list:
    """D.wild lines: per tameable beast its English name, rank, model and where it spawns."""
    classic = load_json(data_dir / "classicdb.json").get("npcs", {})
    jazz = load_json(data_dir / "jazzman.json").get("beasts", {})
    # where EG Link players met each creature in WoW Forever (CC BY 4.0)
    eg = load_json(data_dir / "eglink.json").get("npcs", {})
    crowd = crowd_positions(maps, offline)
    by_name = {}
    for mid, (name, _, typ) in sorted(maps.items()):
        if typ in (3, 4, 5) and name not in by_name:
            by_name[name] = mid
    def zone_points(points: list) -> list:
        """Only points on a zone's map (or smaller): a point on a continent or the world map isn't a spawn spot
        (the bestiary would list "Eastern Kingdoms" as a zone and send a waypoint there)."""
        return [p for p in points if isinstance(p, list) and len(p) >= 3
                and maps.get(int(p[0]), ("", 0, 3))[2] >= 3]

    rows = []
    for npc in sorted(tame):
        name, rank, display, zone = info.get(npc, ("", 0, 0, ""))
        c = classic.get(str(npc), {})
        if npc not in info:
            name = c.get("name", "")
            rank = {1: 1, 2: 3, 4: 2}.get(c.get("rank", 0), 0)
        # seen in WoW Forever: Forever Hunter Pets (MIT), EG Link (CC BY 4.0) and our Collector, all together
        player = zone_points((jazz.get(str(npc), {}).get("at") or []) + (eg.get(str(npc), {}).get("at") or [])
                             + crowd.get(npc, []))
        old = zone_points(c.get("at") or [])
        stats["npc"] = npc
        stats["raw"][npc] = (player, old)
        groups = beast_spots(player, old, stats)
        src = 1 if any(n for _, pts in groups for _, _, n in pts) else 0
        if src:
            stats["player"] += 1
        elif groups:
            stats["classic_only"] += 1
        places = []
        for m, pts in groups:
            used.add(m)
            places.append("{ " + ", ".join([str(m)] + [f"{x}, {y}, {n}" for x, y, n in pts]) + " }")
        if not places and zone:
            if zone in by_name:
                used.add(by_name[zone])
                places.append(f"{{ {by_name[zone]} }}")
            else:
                places.append(f"{{ {lua_str(zone)} }}")
        rows.append(f"\t[{npc}] = {{ {lua_str(name)}, {rank}, {display}, {src}, {{ {', '.join(places)} }} }},")
    return rows


def check_spots(rows: list, stats: dict) -> int:
    """Every written spot must be one of its beast's raw source points (within rounding): no spot in between."""
    bad = 0
    for line in rows:
        npc = int(re.match(r"\t\[(\d+)\]", line)[1])
        raw = by_map(stats["raw"][npc][0] + stats["raw"][npc][1])
        for g in re.findall(r"\{ (\d+(?:, \d+)+) \}", line):
            v = [int(x) for x in g.split(", ")]
            for i in range(1, len(v) - 2, 3):
                x, y = v[i] / 10, v[i + 1] / 10
                if not any(abs(x - a) <= 0.06 and abs(y - b) <= 0.06 for a, b, _ in raw.get(v[0], [])):
                    bad += 1
                    print(f"spot {v[0]} {x},{y} of {npc} is no source point", file=sys.stderr)
    return bad


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
    stats = {"contradicted": set(), "unconfirmed": set(), "dropped": 0, "player": 0, "classic_only": 0, "raw": {}}
    wild = wild_rows(tame, info, data_dir, maps, used, stats, a.offline)
    bad = check_spots(wild, stats)
    if bad:
        print(f"{bad} spots aren't any source's point: not writing Data.lua", file=sys.stderr)
        return 1
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
        w(f"\t[{f['id']}] = {{ key = {lua_str(f['key'])}, slug = {lua_str(f['petopia'])}, icon = {f['icon']}, "
          f"diet = {f['diet']}, abilities = {{ {abil} }} }},")
    w("}")
    w("D.abilities = {")
    for ab in pets["abilities"]:
        first = spells.get(str(ab["ranks"][0]["spell"]), {})
        ranks = ", ".join(
            f"{{ rank = {r['rank']}, level = {r['level']}, spell = {r['spell']}"
            + (", forever = true" if r.get("forever") else "") + " }"
            for r in ab["ranks"])
        w(f"\t[{lua_str(ab['key'])}] = {{ name = {lua_str(first.get('name') or ab['key'])}, "
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
    w("-- (0 unknown), 1 when WoW Forever players saw it somewhere (Forever Hunter Pets, MIT; EG Link, CC BY 4.0; our")
    w("-- Collector) else 0, { { uiMap, x, y, n, x, y, n... }, ... } } with x and y in tenths of a percent of that map and")
    w("-- n how often players saw it there, or 0 for a classic-db spawn point (GPL-3.0; older data, may be wrong). Player-")
    w("-- seen spots come first. A zone without spots is { uiMap } or { \"name\" } (an instance).")
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
    print(f"spots: {stats['player']} beasts with player-seen spots, {stats['classic_only']} with classic-db spots only; "
          f"{len(stats['contradicted'])} beasts had classic-db spots contradicted by dense player data "
          f"({stats['dropped']} spots dropped), {len(stats['unconfirmed'])} keep classic-db spots players haven't "
          f"confirmed (thin data, marked older)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
