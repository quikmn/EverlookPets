-- EverlookDB Pets: the bestiary's logic. Plain functions over the data tables and a context you pass in (your level,
-- your pet, your wishlist and tames, names in the game's language), so the tests can feed it fake data.
--   B.Entries(D)                    every tameable beast the browser lists, sorted by level (unknown last) then name
--   B.Parse(D, query, abilityName)  "bite 6 cat stranglethorn rare" -> what the search asks for
--   B.Filter(D, entries, f, ctx)    the beasts that match the search and the filter chips
--   B.Chips(D, entry, ctx)          what the beast teaches, each rank marked against your pet
--   B.StillToLearn(D, res, where, free)  your pet's ranks still to get, most worth it first, with beasts and costs
--   B.Missing(D, res, ctx)          the ranks your pet lacks that a tame would teach (world map pins)
local _, ns = ...
local B = {}
ns.Bestiary = B
local L = ns.Logic

local function norm(s)
	local S = ns.UI and ns.UI.Search
	if S then return S.Normalize(s) end
	return (tostring(s or ""):lower():gsub("'", ""))
end
B.Normalize = norm

B.RANK_WORD = { [0] = nil, [1] = "elite", [2] = "rare", [3] = "rare elite" }
B.FAST = 2.0 -- an attack speed below this is "fast attack" (2.0 s is a pet without the Faster Attack trait)

------------------------------------------------------------------------
-- The entries
------------------------------------------------------------------------
local cache
-- One entry per tameable beast: { id, name, family, famKey, lo, hi, rank (0-3), rare, elite, display, zones (uiMap ids
-- or names), spots ({ map, x, y, n } with x and y 0-1 and n how often WoW Forever players saw it there, 0 for a
-- classic-db spawn point: older data, may be wrong; player-seen ones first), spotsFrom (1 WoW Forever players saw it
-- somewhere, 0 classic-db only), teaches
-- (L.BeastTeaches), speed (seconds, 0 unknown), known (we know where it is or what it teaches) }.
function B.Entries(D)
	if cache and cache.D == D then return cache.list, cache.by end
	local list, by = {}, {}
	for id, t in pairs(D.tameable or {}) do
		local fam = D.families[t[1]]
		if fam then
			local w = D.wild and D.wild[id]
			local b = D.beasts and D.beasts[id]
			local name = (w and w[1] ~= "" and w[1]) or (b and b[4] ~= "" and b[4]) or ("#" .. id)
			local rank = w and w[2] or 0
			local e = { id = id, name = name, family = t[1], famKey = fam.key, lo = t[2] or 0, hi = math.max(t[3] or 0, t[2] or 0),
				rank = rank, rare = rank == 2 or rank == 3, elite = rank == 1 or rank == 3, display = w and w[3] or 0,
				spotsFrom = w and w[4] or 0, zones = {}, spots = {}, speed = b and b[6] or 0 }
			for _, g in ipairs(w and w[5] or {}) do
				e.zones[#e.zones + 1] = g[1]
				for i = 2, #g - 2, 3 do
					e.spots[#e.spots + 1] = { map = g[1], x = g[i] / 1000, y = g[i + 1] / 1000, n = g[i + 2] or 0 }
				end
			end
			if #e.zones == 0 and b and b[3] and b[3] ~= 0 then e.zones[1] = b[3] end
			e.teaches = L.BeastTeaches(D, id) or {}
			e.known = #e.zones > 0 or #e.teaches > 0
			list[#list + 1] = e
			by[id] = e
		end
	end
	-- by level; a beast whose level nobody reported yet (lo 0: WoW Forever's new ones) goes last, not first. Among
	-- the same level, one we know teaches something comes before one nobody reported yet.
	table.sort(list, function(a, b)
		local la, lb = a.lo > 0 and a.lo or 999, b.lo > 0 and b.lo or 999
		if la ~= lb then return la < lb end
		local ta, tb = #a.teaches > 0, #b.teaches > 0
		if ta ~= tb then return ta end
		if a.name ~= b.name then return a.name < b.name end
		return a.id < b.id
	end)
	cache = { D = D, list = list, by = by }
	return list, by
end

function B.Get(D, id)
	local _, by = B.Entries(D)
	return by[id]
end

-- A zone's shown name: the game's (mapName(id), in your language), else our English one; an instance is its name.
function B.ZoneName(D, z, mapName)
	if type(z) == "string" then return z end
	local n = mapName and mapName(z)
	if n and n ~= "" then return n end
	local zd = D.zones and D.zones[z]
	return zd and zd[1] or ("map " .. tostring(z))
end

function B.Continent(D, z)
	local zd = type(z) == "number" and D.zones and D.zones[z]
	return zd and zd[2] or nil
end

function B.Fast(e) return e.speed and e.speed > 0 and e.speed < B.FAST end

-- "30-31" or "30"
function B.Levels(e)
	if e.lo <= 0 then return "?" end
	return e.hi > e.lo and (e.lo .. "-" .. e.hi) or tostring(e.lo)
end

------------------------------------------------------------------------
-- Search: "bite 6" (an ability rank), "bite" (any rank of it), "cat" (family), "stranglethorn" (zone), "rare",
-- "elite", "fast", "30" (a level in its range), or any part of a name. Every part must match.
------------------------------------------------------------------------
-- Is s[i] the start of a word (or the end of the string at j)?
local function boundary(s, i) return i < 1 or i > #s or not s:sub(i, i):match("[%w\128-\255]") end

function B.Parse(D, query, abilityName)
	local q = " " .. norm(query) .. " "
	local out = { abilities = {}, levels = {}, words = {} }
	-- ability names (English and the game's), longest first, so "furious howl 2" isn't read as "howl"
	local names = {}
	for key, ab in pairs(D.abilities or {}) do
		names[#names + 1] = { key = key, s = norm(ab.name or key) }
		local loc = abilityName and abilityName(ab)
		if loc and norm(loc) ~= norm(ab.name or key) then names[#names + 1] = { key = key, s = norm(loc) } end
	end
	table.sort(names, function(a, b) if #a.s ~= #b.s then return #a.s > #b.s end return a.s < b.s end)
	for _, n in ipairs(names) do
		local from = 1
		while n.s ~= "" do
			local i, j = q:find(n.s, from, true)
			if not i then break end
			if boundary(q, i - 1) and boundary(q, j + 1) then
				local _, k, num = q:find("^%s*(%d+)", j + 1)
				out.abilities[#out.abilities + 1] = { key = n.key, rank = num and tonumber(num) or nil }
				q = q:sub(1, i - 1) .. " " .. q:sub((k or j) + 1)
				from = i
			else
				from = j + 1
			end
		end
	end
	for w in q:gmatch("[%w\128-\255]+") do
		if w:match("^%d+$") then out.levels[#out.levels + 1] = tonumber(w) else out.words[#out.words + 1] = w end
	end
	out.empty = #out.abilities == 0 and #out.levels == 0 and #out.words == 0
	return out
end

-- Everything a word can find a beast by: name, family (English and the game's), zones, rank, fast.
local function haystack(D, e, ctx)
	local parts = { e.name, e.famKey }
	local fn = ctx.familyName and ctx.familyName(e.family)
	if fn then parts[#parts + 1] = fn end
	for _, z in ipairs(e.zones) do
		parts[#parts + 1] = B.ZoneName(D, z)
		local loc = ctx.mapName and type(z) == "number" and ctx.mapName(z)
		if loc then parts[#parts + 1] = loc end
	end
	if e.rare then parts[#parts + 1] = "rare" end
	if e.elite then parts[#parts + 1] = "elite" end
	if B.Fast(e) then parts[#parts + 1] = "fast" end
	return " " .. norm(table.concat(parts, " ")) .. " "
end

local function teaches(e, key, rank)
	for _, t in ipairs(e.teaches) do
		if t.key == key and (not rank or t.rank == rank) then return true end
	end
	return false
end

-- Does the beast match the parsed search?
function B.Matches(D, e, p, ctx)
	for _, a in ipairs(p.abilities) do if not teaches(e, a.key, a.rank) then return false end end
	for _, n in ipairs(p.levels) do if n < e.lo or n > e.hi then return false end end
	if #p.words > 0 then
		e.hay = e.hay or haystack(D, e, ctx)
		for _, w in ipairs(p.words) do
			-- a word matches the start of a word ("strangle" finds Stranglethorn, "cat" doesn't find "wildcat")
			if not e.hay:find(" " .. w, 1, true) and not e.hay:find("-" .. w, 1, true) then return false end
		end
	end
	return true
end

-- The level window "near my level": what you can tame now or soon.
B.NEAR_BELOW, B.NEAR_ABOVE = 5, 3

-- f = { query, family (id), zone (uiMap id, "here" or "continent"), near, rare, fast, untamed, wish }
-- ctx = { level, zone, continent, tamed = { [npc] = n }, wish = { [npc] = true }, mapName(id), familyName(id),
--   abilityName(ab) }. Beasts we know nothing about (no zone, no ranks) only show up when searched for.
function B.Filter(D, entries, f, ctx)
	f, ctx = f or {}, ctx or {}
	local p = B.Parse(D, f.query or "", ctx.abilityName)
	local lvl = ctx.level or 60
	local zone, cont = f.zone, nil
	if zone == "here" then zone = ctx.zone or -1 elseif zone == "continent" then zone, cont = nil, ctx.continent or -1 end
	local out = {}
	for _, e in ipairs(entries) do
		local ok = (e.known or not p.empty)
			and (not f.family or e.family == f.family)
			and (not f.rare or e.rare)
			and (not f.fast or B.Fast(e))
			and (not f.untamed or not (ctx.tamed and ctx.tamed[e.id]))
			and (not f.wish or (ctx.wish and ctx.wish[e.id]))
			and (not f.near or (e.lo <= lvl + B.NEAR_ABOVE and e.hi >= lvl - B.NEAR_BELOW))
		if ok and zone then
			ok = false
			for _, z in ipairs(e.zones) do if z == zone then ok = true break end end
		end
		if ok and cont then
			ok = false
			for _, z in ipairs(e.zones) do if B.Continent(D, z) == cont then ok = true break end end
		end
		if ok and not p.empty then ok = B.Matches(D, e, p, ctx) end
		if ok then out[#out + 1] = e end
	end
	return out, p
end

------------------------------------------------------------------------
-- What a beast teaches, against your pet
------------------------------------------------------------------------
-- ctx.pet = { familyId, level, have = function(key) -> the rank your pet has (0: none) }.
-- Each chip: { key, rank, spell, state (confirmed/seen/classic), text, rel } where rel is
--   gain   your pet's family learns it and your pet has a lower rank (its level allows this rank)
--   later  a higher rank than your pet has, but its level doesn't allow it yet
--   have   your pet has this rank or a better one
--   other  your pet's family can't learn it (or no pet)
function B.Chips(D, e, ctx)
	local out = {}
	local pet = ctx and ctx.pet
	local fam = pet and D.families[pet.familyId or 0]
	local learns = {}
	for _, k in ipairs(fam and fam.abilities or {}) do learns[k] = true end
	for _, t in ipairs(e.teaches) do
		local ab = D.abilities[t.key]
		local name = (ctx and ctx.abilityName and ab and ctx.abilityName(ab)) or t.key
		local chip = { key = t.key, rank = t.rank, spell = t.spell, state = t.state, text = name .. " " .. t.rank, rel = "other" }
		if learns[t.key] and ab then
			local have = pet.have and pet.have(t.key) or 0
			if have >= t.rank then
				chip.rel = "have"
			else
				local need
				for _, r in ipairs(ab.ranks) do if r.rank == t.rank then need = r.level end end
				chip.rel = (need and pet.level and need > pet.level) and "later" or "gain"
			end
		end
		out[#out + 1] = chip
	end
	local order = { gain = 1, later = 2, have = 3, other = 4 }
	table.sort(out, function(a, b)
		if order[a.rel] ~= order[b.rel] then return order[a.rel] < order[b.rel] end
		if a.key ~= b.key then return a.key < b.key end
		return a.rank < b.rank
	end)
	return out
end

-- Does the beast teach anything your pet would gain (now)?
function B.Teaches(D, e, ctx)
	for _, c in ipairs(B.Chips(D, e, ctx)) do if c.rel == "gain" then return true end end
	return false
end

------------------------------------------------------------------------
-- Your pet: what it can still learn, most worth it first
------------------------------------------------------------------------
-- How each kind of "to do" ranks: what you can do right now and cheaply first.
B.LEARN_ORDER = { train = 1, otherpet = 2, trainer = 3, tame = 4, tamehigh = 5, tameunknown = 6, forever = 7 }

-- The training points a rank costs (nil: not known) and the net cost when the pet already has a lower rank (Beast
-- Training gives back what the lower rank cost).
function B.Cost(D, ab, rank, haveRank)
	local r
	for _, x in ipairs(ab.ranks) do if x.rank == rank then r = x end end
	local cost = r and D.training and D.training[r.spell]
	if not cost then return nil end
	local back = 0
	for _, x in ipairs(ab.ranks) do
		if x.rank == haveRank then back = (D.training and D.training[x.spell]) or 0 end
	end
	return cost, math.max(0, cost - back)
end

-- res = L.Evaluate's result, where = { level, zone, continent }, free = training points free (nil: unknown).
-- Returns the rows that aren't done, each with: kind (B.LEARN_ORDER key), gain (ranks gained), cost, net, fits
-- (enough points; nil when unknown), beasts (the 3 best to tame: you can tame them, nearest zone, confirmed first),
-- beastCount. Sorted: kind, then most ranks gained, then cheapest, then name.
function B.StillToLearn(D, res, where, free)
	local out = {}
	for _, row in ipairs(res and res.rows or {}) do
		if row.state ~= "trained" and row.state ~= "locked" and row.target then
			local item = { row = row, gain = row.target.rank - (row.haveRank or 0) }
			item.cost, item.net = B.Cost(D, row.ability, row.target.rank, row.haveRank or 0)
			if item.net and free then item.fits = item.net <= free end
			local kind = row.state
			if kind == "tame" or kind == "forever" then
				local top, all = L.Teachers(D, row.target.spell, where, 3, "near")
				item.beasts, item.beastCount = top, all or 0
				if kind == "tame" then
					if #top == 0 then kind = "tameunknown"
					elseif top[1].tooHigh then kind = "tamehigh" end
				end
			end
			item.kind = kind
			out[#out + 1] = item
		end
	end
	table.sort(out, function(a, b)
		local ka, kb = B.LEARN_ORDER[a.kind] or 9, B.LEARN_ORDER[b.kind] or 9
		if ka ~= kb then return ka < kb end
		if a.gain ~= b.gain then return a.gain > b.gain end
		local ca, cb = a.net or 9999, b.net or 9999
		if ca ~= cb then return ca < cb end
		return (a.row.name or "") < (b.row.name or "")
	end)
	return out
end

-- The ranks your pet lacks that a beast teaches: { [spell] = row }, for the world map pins. Only ranks its level
-- allows, that you don't know yourself (then it's just training), and not sold by pet trainers.
function B.Missing(D, res, hunterKnows)
	local out = {}
	for _, row in ipairs(res and res.rows or {}) do
		local ab = row.ability
		if ab and not ab.trainer and row.best then
			for _, r in ipairs(ab.ranks) do
				if r.rank > (row.haveRank or 0) and r.rank <= row.best.rank and not (hunterKnows and hunterKnows(r.spell)) then
					out[r.spell] = row
				end
			end
		end
	end
	return out
end

-- The beasts on one map that teach a rank in `missing` (B.Missing), tameable at your level: { { entry, spot,
-- ranks = { { key, rank, state } } } }, one per spot.
function B.PinsOn(D, map, missing, level)
	local out = {}
	if not map then return out end
	for _, e in ipairs((B.Entries(D))) do
		if e.lo <= (level or 60) then
			local ranks
			for _, t in ipairs(e.teaches) do
				if missing[t.spell] then
					ranks = ranks or {}
					ranks[#ranks + 1] = t
				end
			end
			if ranks then
				for _, s in ipairs(e.spots) do
					if s.map == map then out[#out + 1] = { entry = e, spot = s, ranks = ranks } end
				end
			end
		end
	end
	return out
end

-- A spot from classic-db (no WoW Forever player has seen the beast there): older data, may be wrong.
function B.OldSpot(s) return s ~= nil and (s.n or 0) == 0 end

-- The best of `spots` (all on one map, or all without your position): a lone sighting (seen once) is an outlier
-- as long as a spot seen more often is in the same zone, so it is skipped then; of the rest the nearest to (x, y),
-- or without a position the most seen.
local function pick(spots, x, y)
	local dense = false
	for _, s in ipairs(spots) do if (s.n or 0) > 1 then dense = true end end
	local best, bestD
	for _, s in ipairs(spots) do
		if not (dense and s.n == 1) then
			local d = x and ((s.x - x) ^ 2 + (s.y - y) ^ 2) or -(s.n or 0)
			if not bestD or d < bestD then best, bestD = s, d end
		end
	end
	return best
end

-- The spot to send you to: where WoW Forever players saw the beast before classic-db's older data. The best
-- player-seen spot on your map (pick), else on your continent; only then classic-db's on your map or continent; then
-- anywhere, player-seen first. where = { map, x, y, continent }.
function B.BestSpot(D, e, where)
	where = where or {}
	local function among(test, old)
		local out = {}
		for _, s in ipairs(e.spots) do
			if B.OldSpot(s) == old and test(s) then out[#out + 1] = s end
		end
		return out
	end
	local onMap = function(s) return where.map ~= nil and s.map == where.map end
	local onContinent = function(s) return where.continent ~= nil and B.Continent(D, s.map) == where.continent end
	local anywhere = function() return true end
	-- player-seen on your map, then on your continent; classic-db on your map, then your continent; then anywhere
	for _, t in ipairs({ { onMap, false }, { onContinent, false }, { onMap, true }, { onContinent, true },
		{ anywhere, false }, { anywhere, true } }) do
		local list = among(t[1], t[2])
		if #list > 0 then
			local here = t[1] == onMap and where.x
			return pick(list, here and where.x or nil, here and where.y or nil)
		end
	end
	return nil
end
