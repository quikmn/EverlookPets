-- Everlook Pets: the rank logic. Plain functions over plain tables (no game calls), so the tests can feed it fake
-- data. Core.lua reads the game and hands these functions what the pet and the hunter know.
local _, ns = ...
local L = {}
ns.Logic = L

L.SITE = "https://everlookdb.com/pets.html"
L.PETOPIA = "https://www.wow-petopia.com/classic/"

-- The site's pet page for a family, with its level slider set ("pets.html?family=cat&level=48").
function L.SiteLink(fam, level)
	local q = {}
	if fam and fam.petopia then q[#q + 1] = "family=" .. fam.petopia end
	if type(level) == "number" and level >= 1 and level <= 60 then q[#q + 1] = "level=" .. level end
	return L.SITE .. (#q > 0 and ("?" .. table.concat(q, "&")) or "")
end

-- Petopia's list of beasts that know one rank ("abilities.php#bite7"), or its whole family page.
function L.PetopiaRank(ab, rank) return L.PETOPIA .. "abilities.php#" .. ab.petopia .. (rank or "") end
function L.PetopiaFamily(fam) return L.PETOPIA .. "family.php?id=" .. fam.petopia end

-- The highest rank a pet of `level` can have (nil: none yet), and the first rank it can't have yet (nil: maxed).
function L.RankWindow(ab, level)
	local best, nxt
	for _, r in ipairs(ab.ranks) do
		if r.level <= level then
			if not best or r.rank > best.rank then best = r end
		elseif not nxt or r.rank < nxt.rank then
			nxt = r
		end
	end
	return best, nxt
end

-- The highest rank whose spell known(spellID) says is known, no higher than maxRank (if given).
function L.HighestKnown(ab, known, maxRank)
	local top
	for _, r in ipairs(ab.ranks) do
		if (not maxRank or r.rank <= maxRank) and known(r.spell) then
			if not top or r.rank > top.rank then top = r end
		end
	end
	return top
end

local function no() return false end

-- One ability for one pet. k = { petKnows(spell), hunterKnows(spell), otherPet(spell) -> the name of another of your
-- pets that knows it, or nil }. Returns a row: state, have (the pet's rank), best (its level allows), next, target
-- (the rank the advice is about), actionable (something to do now).
-- States, in the order they are checked:
--   locked    the pet's level allows no rank yet
--   trained   the pet has the best rank its level allows
--   train     you (the hunter) know a better rank than the pet has: teach it with Beast Training
--   trainer   a pet trainer sells it (Growl, Cower, Great Stamina, Natural Armor, resistances)
--   otherpet  another of your pets knows a better rank: learn it from that pet, then teach it
--   forever   new in WoW Forever: the game files don't say how it is learned
--   tame      tame a beast that knows the rank, learn it from that beast, then teach it
function L.Ability(ab, petLevel, k)
	local petKnows, hunterKnows, otherPet = k.petKnows or no, k.hunterKnows or no, k.otherPet or no
	local best, nxt = L.RankWindow(ab, petLevel or 1)
	local have = L.HighestKnown(ab, petKnows)
	local haveN = have and have.rank or 0
	local row = { ability = ab, best = best, next = nxt, have = have, haveRank = haveN }
	if not best then
		row.state = "locked"
		return row
	end
	if haveN >= best.rank then
		row.state = "trained"
		return row
	end
	row.actionable = true
	local h = L.HighestKnown(ab, hunterKnows, best.rank)
	if h and h.rank > haveN then
		row.state, row.target = "train", h
		return row
	end
	if ab.trainer then
		row.state, row.target = "trainer", best
		return row
	end
	local o, oname
	for _, r in ipairs(ab.ranks) do
		if r.rank > haveN and r.rank <= best.rank then
			local n = otherPet(r.spell)
			if n and (not o or r.rank > o.rank) then o, oname = r, n end
		end
	end
	if o then
		row.state, row.target, row.otherName = "otherpet", o, oname
		return row
	end
	if ab.forever or best.forever then
		row.state, row.target, row.actionable = "forever", best, false
		return row
	end
	row.state, row.target = "tame", best
	return row
end

-- Actionable first (the order they'd be done in), then the rest.
L.ORDER = { train = 1, trainer = 2, otherpet = 3, tame = 4, forever = 5, trained = 6, locked = 7 }

-- Every ability the pet's family can learn. s = { familyId, petLevel, playerLevel, petKnows, hunterKnows, otherPet,
-- nameOf(ab) -> the shown name }. Returns { family, rows, todo (actionable rows), lag (levels below you) }.
function L.Evaluate(D, s)
	local fam = D.families[s.familyId or 0]
	local out = { family = fam, rows = {}, todo = 0 }
	if s.playerLevel and s.petLevel then out.lag = s.playerLevel - s.petLevel end
	if not fam then return out end
	for _, key in ipairs(fam.abilities) do
		local ab = D.abilities[key]
		if ab then
			local row = L.Ability(ab, s.petLevel, s)
			-- new in WoW Forever, but players have seen beasts that teach it: tame one
			if row.state == "forever" and D.teachers and D.teachers[row.target.spell] then
				row.state, row.actionable = "tame", true
			end
			row.key = key
			row.name = s.nameOf and s.nameOf(ab) or ab.name
			out.rows[#out.rows + 1] = row
			if row.actionable then out.todo = out.todo + 1 end
		end
	end
	table.sort(out.rows, function(a, b)
		local oa, ob = L.ORDER[a.state], L.ORDER[b.state]
		if oa ~= ob then return oa < ob end
		return a.name < b.name
	end)
	return out
end

-- What a row says. Returns the status line and a longer "how" line.
function L.Describe(row)
	local st, t, n = row.state, row.target, row.next
	local have = row.haveRank > 0 and ("rank " .. row.haveRank) or "none"
	if st == "locked" then
		return ("Opens at pet level %d"):format(n.level), "Your pet learns rank 1 from that level on."
	elseif st == "trained" then
		local s = ("Trained: rank %d"):format(row.haveRank)
		if n then return s .. (" · rank %d at pet level %d"):format(n.rank, n.level), "Your pet has the best rank its level allows." end
		return s .. " · highest rank", "Your pet has the highest rank there is."
	elseif st == "train" then
		return ("Train now: you know rank %d, your pet has %s"):format(t.rank, have),
			"Open Beast Training (in your spellbook) and teach it. It costs training points."
	elseif st == "trainer" then
		return ("Buy rank %d from a pet trainer (your pet has %s)"):format(t.rank, have),
			"Pet trainers in the capital cities sell it; then teach it with Beast Training."
	elseif st == "otherpet" then
		return ("%s knows rank %d: learn it from that pet"):format(row.otherName, t.rank),
			"Fight with that pet until you learn the ability, then teach it to this one with Beast Training."
	elseif st == "forever" then
		return ("Rank %d: new in WoW Forever"):format(t.rank),
			"The game files don't say how it is learned yet; EverlookDB's pet page has the latest."
	end
	return ("Tame a beast that knows rank %d (your pet has %s)"):format(t.rank, have),
		"Tame a beast that knows it, fight with it until you learn it, then teach your pet with Beast Training. Where? lists the beasts."
end

-- One chat line for a row that just became something to do.
function L.ChatLine(row)
	local st, t = row.state, row.target
	if st == "train" then return ("%s rank %d: you know it, teach it with Beast Training."):format(row.name, t.rank) end
	if st == "trainer" then return ("%s rank %d is open: buy it from a pet trainer."):format(row.name, t.rank) end
	if st == "otherpet" then return ("%s rank %d: %s knows it, learn it from that pet."):format(row.name, t.rank, row.otherName) end
	return ("%s rank %d is open: tame a beast that knows it (/epets, Where? lists them)."):format(row.name, t.rank)
end

-- Rows that just became something to do. prev = { [ability key] = "tame:7" } from the last check (nil: never
-- checked). Returns the new rows and the new map to keep.
function L.Diff(prev, rows)
	local now, news = {}, {}
	for _, row in ipairs(rows) do
		if row.actionable then
			local sig = row.state .. ":" .. row.target.rank
			now[row.key] = sig
			if not prev or prev[row.key] ~= sig then news[#news + 1] = row end
		end
	end
	return news, now
end

-- "Your pet is 5 levels below you", when it is at least `warn` levels behind (warn 0: never).
function L.LagText(lag, warn)
	if not lag or not warn or warn <= 0 or lag < warn then return nil end
	return ("Your pet is %d level%s below you"):format(lag, lag == 1 and "" or "s")
end

-- The foods a diet mask allows, as the site names them.
function L.Foods(D, mask)
	local out = {}
	for i, name in ipairs(D.foods) do
		if mask and math.floor(mask / 2 ^ (i - 1)) % 2 == 1 then out[#out + 1] = name end
	end
	return out
end

------------------------------------------------------------------------
-- Who teaches what (D.beasts, D.teachers, D.zones from EverlookDB's bestiary; see tools/gen_data.py)
------------------------------------------------------------------------
L.STATE = { [3] = "confirmed", [2] = "seen", [1] = "classic" }
L.STATE_LABEL = { confirmed = "confirmed", seen = "seen in WoW Forever", classic = "classic data" }
L.NPC_URL = "https://everlookdb.com/npc.html?id="

-- spell id -> { key, rank } for every pet ability rank, built once from D.abilities
local rankIndex
function L.RankOf(D, spell)
	if not rankIndex or rankIndex.D ~= D then
		rankIndex = { D = D, by = {} }
		for key, ab in pairs(D.abilities) do
			for _, r in ipairs(ab.ranks) do rankIndex.by[r.spell] = { key = key, rank = r.rank } end
		end
	end
	return rankIndex.by[spell]
end

-- What one beast teaches: { { spell, key, rank, state }, ... } sorted by ability then rank, or nil.
function L.BeastTeaches(D, npcId)
	local b = D.beasts and D.beasts[npcId]
	if not b or not b[5] then return nil end
	local out = {}
	for i = 1, #b[5], 2 do
		local spell, st = b[5][i], b[5][i + 1]
		local r = L.RankOf(D, spell)
		if r then out[#out + 1] = { spell = spell, key = r.key, rank = r.rank, state = L.STATE[st] or "classic", n = st } end
	end
	table.sort(out, function(a, b2) if a.key ~= b2.key then return a.key < b2.key end return a.rank < b2.rank end)
	return #out > 0 and out or nil
end

-- "Bite 2 · Claw 3" and the weakest state among them (what the whole line can be trusted as), or nil.
-- nameOf(ab) gives the ability's shown name (the game's language); default its English name.
function L.TeachesText(D, npcId, nameOf)
	local list = L.BeastTeaches(D, npcId)
	if not list then return nil end
	local parts, weakest = {}, 3
	for _, t in ipairs(list) do
		local ab = D.abilities[t.key]
		parts[#parts + 1] = ((nameOf and ab and nameOf(ab)) or t.key) .. " " .. t.rank
		if t.n < weakest then weakest = t.n end
	end
	return table.concat(parts, " · "), L.STATE[weakest]
end

-- The beasts to tame for one rank, best first, at most n (default 5). where = { level, zone, continent } (any may be
-- nil). Order: one you can tame at your level before one too high for you, then confirmed before seen before
-- classic data, then in your zone, then your continent, then nearest your level.
function L.Teachers(D, spell, where, n)
	local ids = D.teachers and D.teachers[spell]
	if not ids then return {} end
	where = where or {}
	local lvl = where.level or 60
	local out = {}
	for _, id in ipairs(ids) do
		local b = D.beasts[id]
		if b then
			local st = 1
			for i = 1, #(b[5] or {}), 2 do if b[5][i] == spell then st = b[5][i + 1] end end
			local zone = D.zones and D.zones[b[3]]
			local place = (where.zone and b[3] == where.zone) and 0
				or (where.continent and zone and zone[2] == where.continent) and 1 or 2
			local lo, hi = b[1] or 0, b[2] or 0
			local tooHigh = lo > lvl
			local dist = tooHigh and (lo - lvl) or math.max(0, lvl - hi)
			out[#out + 1] = { id = id, name = b[4], lo = lo, hi = hi, zone = b[3], zoneName = zone and zone[1] or nil,
				state = L.STATE[st] or "classic", n = st, place = place, tooHigh = tooHigh, dist = dist, speed = b[6] }
		end
	end
	table.sort(out, function(a, b)
		if a.tooHigh ~= b.tooHigh then return not a.tooHigh end
		if a.n ~= b.n then return a.n > b.n end
		if a.place ~= b.place then return a.place < b.place end
		if a.dist ~= b.dist then return a.dist < b.dist end
		return a.id < b.id
	end)
	local top = {}
	for i = 1, math.min(n or 5, #out) do top[i] = out[i] end
	return top, #out
end

-- "Prowler  9-10 · Elwynn Forest · seen in WoW Forever"
function L.TeacherLine(t)
	local lv = t.lo > 0 and (t.hi > t.lo and (t.lo .. "-" .. t.hi) or tostring(t.lo)) or "?"
	return ("%s  %s%s · %s"):format(t.name ~= "" and t.name or ("#" .. t.id), lv, t.zoneName and (" · " .. t.zoneName) or "",
		L.STATE_LABEL[t.state] or t.state)
end
