-- EverlookDB Pets: the level-up card. When a hunter levels up, what became possible at the new level, on one calm
-- card near the top of the screen (never over the action bars, no sound, not modal, movable, closes on its button
-- or Escape and never closes another window):
--   For your pet   ranks of your pet's family that opened at this level and that it lacks: teach it now (you know
--                  the rank), learn it from another of your pets, or tame a beast that knows it (the best one to
--                  tame at your level, your continent first, with a Pin to its nearest spawn spot)
--   At the hunter trainer   the class spells and ranks trainable from this level (Trainers.lua)
--   At a pet trainer        the trainer-sold ranks (Growl, Cower, Great Stamina...) that opened
-- Each part is a setting (LU.Pick, LU.Sections): only "For your pet" is on by default; the trainer parts and the
-- hunter trainer's pin are ticked in Settings. The chat line follows the same choices.
-- In combat the card waits until the fight ends. Nothing new: no card. A setting gives one chat line instead.
-- The plain functions (LU.HunterSpells, LU.PetNews, LU.Trainer, LU.Compute) take the data and a context, so the tests
-- can feed them fake data; the frame is built the first time it shows.
local _, ns = ...
local UI = ns.UI
local U = UI.Util
local L = ns.Logic
local B = ns.Bestiary
local LU = {}
ns.LevelUp = LU

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end
local MUTED, GOLD, GREEN, RED = "|cff8d94a3", "|cffffd200", "|cff62cf88", "|cffef5d5d"

------------------------------------------------------------------------
-- What's new (plain functions)
------------------------------------------------------------------------
-- The hunter trainer's spells for levels prev+1 .. level that you don't know yet. A rank whose lower ranks don't
-- come from the trainer (a talent's: Aimed Shot, Counterattack) shows only when you know one of them.
-- Returns { { spell, rank, cost, icon, name, level } } by name.
function LU.HunterSpells(D, level, prev, hunterKnows)
	local out = {}
	hunterKnows = hunterKnows or function() return false end
	for lvl = (prev or level - 1) + 1, level do
		for _, s in ipairs(D.hunterSpells and D.hunterSpells[lvl] or {}) do
			local ok = not hunterKnows(s[1])
			if ok and s[6] then
				ok = false
				for _, id in ipairs(s[6]) do if hunterKnows(id) then ok = true break end end
			end
			if ok then out[#out + 1] = { spell = s[1], rank = s[2], cost = s[3], icon = s[4], name = s[5], level = lvl } end
		end
	end
	table.sort(out, function(a, b) if a.name ~= b.name then return a.name < b.name end return a.rank < b.rank end)
	return out
end

-- The lowest level a known teacher of this rank can be tamed at (0: no beast with a known level).
local function lowestTeacher(D, spell)
	local lo
	for _, id in ipairs(D.teachers and D.teachers[spell] or {}) do
		local b = D.beasts and D.beasts[id]
		local l = b and b[1] or 0
		if l > 0 and (not lo or l < lo) then lo = l end
	end
	return lo or 0
end
LU.LowestTeacher = lowestTeacher

-- When a rank becomes yours to get: a pet trainer's from its level; a tame's from its level and the level of the
-- lowest beast that teaches it (you can't tame above your level).
function LU.OpensAt(D, ab, r)
	if ab.trainer then return r.level end
	return math.max(r.level, lowestTeacher(D, r.spell))
end

LU.ORDER = { teach = 1, otherpet = 2, tame = 3, tameunknown = 4 }

-- Your pet's ranks that opened at this level. s = { level, prev, familyId, petName, petLevel, petKnows(spell),
-- hunterKnows(spell), otherPet(spell) -> name, free (training points, nil unknown), where = { level, zone, continent,
-- map, x, y } }. Returns pet (for your pet: teach, otherpet, tame, tameunknown; most worth it first) and trainer (ranks
-- to buy from a pet trainer). Each item: { kind, key, ab, rank (the data's rank), name, have, gain, cost, net, fits,
-- petLow (your pet is below the rank's level), beasts (L.Teachers, best first), beast (the bestiary entry to pin),
-- spot, beastCount }. Only abilities your pet's family learns; per ability the highest rank that opened.
function LU.PetNews(D, s)
	local pet, trainer = {}, {}
	local fam = D.families[s.familyId or 0]
	if not fam then return pet, trainer end
	local level, prev = s.level, s.prev or (s.level - 1)
	local petKnows = s.petKnows or function() return false end
	local hunterKnows = s.hunterKnows or function() return false end
	local otherPet = s.otherPet or function() return nil end
	local where = s.where or {}
	for _, key in ipairs(fam.abilities) do
		local ab = D.abilities[key]
		if ab then
			local have = L.HighestKnown(ab, petKnows)
			local haveN = have and have.rank or 0
			local pick
			for _, r in ipairs(ab.ranks) do
				if r.rank > haveN then
					local opens = LU.OpensAt(D, ab, r)
					-- you already know it (another pet): it opens for your pet with its level
					if hunterKnows(r.spell) then opens = r.level end
					if opens > prev and opens <= level and (not pick or r.rank > pick.rank) then pick = r end
				end
			end
			if pick then
				local item = { key = key, ab = ab, rank = pick, name = s.nameOf and s.nameOf(ab) or ab.name, have = haveN,
					gain = pick.rank - haveN, petLow = s.petLevel ~= nil and s.petLevel < pick.level }
				item.cost, item.net = B.Cost(D, ab, pick.rank, haveN)
				if item.net and s.free then item.fits = item.net <= s.free end
				if hunterKnows(pick.spell) then
					item.kind = "teach"
				elseif ab.trainer then
					item.kind = "trainer"
				else
					local other = otherPet(pick.spell)
					if other then
						item.kind, item.otherName = "otherpet", other
					else
						local top, all = L.Teachers(D, pick.spell, { level = level, zone = where.zone, continent = where.continent }, 3, "near")
						item.beasts, item.beastCount = top, all or 0
						-- the one to pin: the best you can tame now that has a known spawn spot
						for _, t in ipairs(top) do
							local e = not t.tooHigh and B.Get(D, t.id)
							if e and #e.spots > 0 then item.beast, item.spot = e, B.BestSpot(D, e, where) break end
						end
						if not item.beast and top[1] and not top[1].tooHigh then item.beast = B.Get(D, top[1].id) end
						item.kind = (#top > 0 and not top[1].tooHigh) and "tame" or "tameunknown"
						-- new in WoW Forever and nobody has reported a beast: nothing to send you to
						if item.kind == "tameunknown" and (ab.forever or pick.forever) and #top == 0 then item.kind = nil end
					end
				end
				if item.kind == "trainer" then trainer[#trainer + 1] = item
				elseif item.kind then pet[#pet + 1] = item end
			end
		end
	end
	table.sort(pet, function(a, b)
		local ka, kb = LU.ORDER[a.kind] or 9, LU.ORDER[b.kind] or 9
		if ka ~= kb then return ka < kb end
		if a.gain ~= b.gain then return a.gain > b.gain end
		local ca, cb = a.net or 9999, b.net or 9999
		if ca ~= cb then return ca < cb end
		return a.name < b.name
	end)
	table.sort(trainer, function(a, b) return a.name < b.name end)
	return pet, trainer
end

-- The nearest trainer of a kind ("hunter" or "pet") for your faction ("a", "h"; nil: any) that teaches up to
-- `level`. here = { map, x, y, continent }; pos(map, x, y) -> continent id, cx, cy (world-ish coordinates; nil when
-- the game can't say). Order: on your map (nearest), else on your continent (nearest when pos knows, else the data's
-- order), else any. Returns { npc, side, map, x, y (0-1), continent, top, name, zone } or nil.
function LU.Trainer(D, kind, level, here, faction, pos)
	here = here or {}
	local hc, hx, hy
	if pos and here.map and here.x then hc, hx, hy = pos(here.map, here.x, here.y) end
	local best, bestKey
	for i, t in ipairs(D.trainerNpcs or {}) do
		if t[1] == kind and (t[3] == "n" or not faction or t[3] == faction) and (t[8] or 60) >= (level or 1) then
			local x, y = t[5] / 1000, t[6] / 1000
			local tier, d = 3, i
			if here.map and t[4] == here.map and here.x then
				tier, d = 0, (x - here.x) ^ 2 + (y - here.y) ^ 2
			elseif here.continent and t[7] == here.continent then
				tier = 1
				local tc, tx, ty
				if pos and hc then tc, tx, ty = pos(t[4], x, y) end
				if tc and tc == hc and tx then d = (tx - hx) ^ 2 + (ty - hy) ^ 2 else tier = 2 end
			end
			if not bestKey or tier < bestKey[1] or (tier == bestKey[1] and d < bestKey[2]) then
				best, bestKey = { npc = t[2], side = t[3], map = t[4], x = x, y = y, continent = t[7], top = t[8], name = t[9], zone = t[10] }, { tier, d }
			end
		end
	end
	return best
end

-- Everything for the card. s as LU.PetNews takes, plus faction and pos (LU.Trainer). Returns { level, prev, hunter
-- (LU.HunterSpells), pet, trainer (LU.PetNews), hunterTrainer, petTrainer (LU.Trainer), lag (text or nil),
-- petName, empty (nothing new) }.
function LU.Compute(D, s)
	local out = { level = s.level, prev = s.prev or (s.level - 1), petName = s.petName, multi = s.multi }
	out.hunter = LU.HunterSpells(D, s.level, out.prev, s.hunterKnows)
	if s.targets then
		out.pet, out.trainer = LU.TargetNews(D, s)
	else
		out.pet, out.trainer = LU.PetNews(D, s)
	end
	if #out.hunter > 0 then out.hunterTrainer = LU.Trainer(D, "hunter", s.level, s.where, s.faction, s.pos) end
	if #out.trainer > 0 then out.petTrainer = LU.Trainer(D, "pet", s.level, s.where, s.faction, s.pos) end
	out.lag = s.lag
	out.empty = #out.hunter == 0 and #out.pet == 0 and #out.trainer == 0
	return out
end

------------------------------------------------------------------------
-- Which families "For your pet" covers (Settings: My current pet's family, These families, All families)
------------------------------------------------------------------------
LU.FAMILY_MODES = { "current", "these", "all" }

-- The pets the part is about. mode: "current" | "these" | "all"; chosen: { [family id] = true } ("these");
-- pets: your saved pets { [key] = { name, family, level, spells } }; cur: the pet out now { key, familyId, name,
-- level, knows(spell) } or nil; lastKey: the key of the last pet you had out.
-- Returns { { familyId, key, name, level, knows(spell), current } }: "current" gives the pet out (else the last one
-- out, else nothing); the others one per family, the pet out first, then families you have a pet of, then by name.
-- A family with no pet of yours has no key: every rank that opens counts as one it lacks.
function LU.Targets(D, mode, chosen, pets, cur, lastKey)
	pets = pets or {}
	local function fromRec(key, rec)
		local spells = type(rec.spells) == "table" and rec.spells or {}
		return { familyId = rec.family, key = key, name = rec.name, level = rec.level, knows = function(spell) return spells[spell] == true end }
	end
	if mode ~= "these" and mode ~= "all" then
		if cur and cur.familyId and D.families[cur.familyId] then
			return { { familyId = cur.familyId, key = cur.key, name = cur.name, level = cur.level, knows = cur.knows, current = true } }
		end
		local rec = lastKey and pets[lastKey]
		if type(rec) == "table" and rec.family and D.families[rec.family] then return { fromRec(lastKey, rec) } end
		return {}
	end
	-- your best pet of each family (the one out, else the highest level)
	local best = {}
	for key, rec in pairs(pets) do
		if type(rec) == "table" and rec.family then
			local b = best[rec.family]
			if not b or (rec.level or 0) > (b.level or 0) or ((rec.level or 0) == (b.level or 0) and key < b.key) then
				best[rec.family] = fromRec(key, rec)
			end
		end
	end
	if cur and cur.familyId then
		best[cur.familyId] = { familyId = cur.familyId, key = cur.key, name = cur.name, level = cur.level, knows = cur.knows, current = true }
	end
	local out = {}
	for fid in pairs(D.families) do
		if mode == "all" or (chosen and chosen[fid]) then
			out[#out + 1] = best[fid] or { familyId = fid }
		end
	end
	table.sort(out, function(a, b)
		if (a.current or false) ~= (b.current or false) then return a.current == true end
		if (a.key ~= nil) ~= (b.key ~= nil) then return a.key ~= nil end
		return D.families[a.familyId].key < D.families[b.familyId].key
	end)
	return out
end

-- "Bat, Boar, Wolf" (three at most, then "+N").
function LU.FamilyList(names)
	if #names <= 3 then return table.concat(names, ", ") end
	return ("%s, %s, %s +%d"):format(names[1], names[2], names[3], #names - 3)
end

-- LU.PetNews for each of s.targets (LU.Targets), in their order. Each item knows its family (famId, famName with
-- s.multi) and its pet (petName). The pet trainer's ranks: the first target's, when it is a pet of yours.
function LU.TargetNews(D, s)
	local pet, trainer, shared = {}, {}, {}
	for i, t in ipairs(s.targets) do
		local ss = {}
		for k, v in pairs(s) do ss[k] = v end
		ss.familyId, ss.petName, ss.petLevel, ss.petKnows = t.familyId, t.name, t.level, t.knows
		if not t.current then ss.free = nil end
		ss.otherPet = function(spell)
			for key, rec in pairs(s.pets or {}) do
				if key ~= t.key and type(rec) == "table" and type(rec.spells) == "table" and rec.spells[spell] then return rec.name end
			end
			return nil
		end
		local p, tr = LU.PetNews(D, ss)
		local famName = s.familyName and s.familyName(t.familyId) or D.families[t.familyId].key
		for _, it in ipairs(p) do
			it.famId, it.petName = t.familyId, t.name
			if s.multi then it.famName = famName end
			if t.key then
				pet[#pet + 1] = it
			elseif it.kind == "tame" or it.kind == "tameunknown" then
				-- a family you have no pet of: only a beast to tame is news (you'd teach the ranks you know to a new pet
				-- anyway), and a rank many families share is one row: "Bat, Boar, Wolf: Bite rank 6"
				local id = it.key .. "#" .. it.rank.rank
				local same = shared[id]
				if same then
					same.fams[#same.fams + 1] = famName
					same.famName = LU.FamilyList(same.fams)
				else
					it.fams = { famName }
					shared[id] = it
					pet[#pet + 1] = it
				end
			end
		end
		if i == 1 and t.key then trainer = tr end
	end
	return pet, trainer
end

-- Only the parts of the card you ticked (Settings, under the level-up card): opt = { pet, petTrainer, hunter,
-- hunterPin } (nil: the defaults, only your pet's new ranks). A copy of c without the parts that are off; empty again
-- when nothing ticked is left. c.hunterPin: the hunter trainer's pin (the card's primary button) is wanted.
LU.SECTION_DEFAULTS = { pet = true, petTrainer = false, hunter = false, hunterPin = false }
function LU.Pick(c, opt)
	if not c then return nil end
	opt = opt or LU.SECTION_DEFAULTS
	local out = {}
	for k, v in pairs(c) do out[k] = v end
	if not opt.pet then out.pet, out.lag = {}, nil end
	if not opt.petTrainer then out.trainer, out.petTrainer = {}, nil end
	if not opt.hunter then out.hunter, out.hunterTrainer = {}, nil end
	out.hunterPin = (opt.hunter and opt.hunterPin and out.hunterTrainer) and true or false
	out.empty = #out.hunter == 0 and #out.pet == 0 and #out.trainer == 0
	return out
end

-- The parts you ticked, from the saved settings.
function LU.Sections()
	local db = ns.db or {}
	local d = LU.SECTION_DEFAULTS
	local function pick(k, key) if db[key] == nil then return d[k] end return db[key] and true or false end
	return { pet = pick("pet", "levelPet"), petTrainer = pick("petTrainer", "levelPetTrainer"),
		hunter = pick("hunter", "levelHunter"), hunterPin = pick("hunterPin", "levelHunterPin") }
end

------------------------------------------------------------------------
-- What the rows say
------------------------------------------------------------------------
local function petWord(c, it)
	if it and it.famName then return it.petName or ("a " .. it.famName) end
	return (it and it.petName) or c.petName or "your pet"
end

local function levels(t)
	if not t or (t.lo or 0) <= 0 then return "level ?" end
	return "level " .. (t.hi > t.lo and (t.lo .. "-" .. t.hi) or tostring(t.lo))
end

-- The title of a "for your pet" row.
function LU.PetTitle(it, c)
	if it.famName then
		return ("%s%s:|r %s rank %d%s"):format(GOLD, it.famName, it.name, it.rank.rank, it.petName and (MUTED .. " for " .. it.petName .. "|r") or "")
	end
	return ("%sNew:|r %s rank %d %sfor %s|r"):format(GOLD, it.name, it.rank.rank, MUTED, petWord(c, it))
end

-- The line under it: what to do.
function LU.PetSub(it, c)
	local s
	if it.kind == "teach" then
		s = ("You know it: teach it to %s with Beast Training"):format(petWord(c, it))
		if it.net then s = s .. (" (%d TP%s)"):format(it.net, it.fits == false and (", " .. RED .. "more than it has free|r") or "") end
	elseif it.kind == "otherpet" then
		s = ("%s knows it: fight with that pet to learn it, then teach %s"):format(it.otherName, petWord(c, it))
	elseif it.kind == "tame" then
		local t = it.beasts[1]
		local zone = t.zone and t.zone ~= 0 and B.ZoneName(ns.Data, t.zone, ns.MapName) or nil
		local name = t.name ~= "" and t.name or "beast"
		s = ("Tame %s %s (%s%s) to learn it"):format(name:match("^[AEIOUaeiou]") and "an" or "a", name, levels(t), zone and (", " .. zone) or "")
	else
		s = "Tame a beast that knows it" .. MUTED .. ((it.beasts and it.beasts[1]) and (" (from level " .. it.beasts[1].lo .. ")") or " (no beast reported yet)") .. "|r"
	end
	if it.petLow then s = s .. MUTED .. (" · once %s is level %d|r"):format(petWord(c, it), it.rank.level) end
	return s
end

function LU.HunterTitle(h)
	local name = ns.Str((ns.Call(ns.api("C_Spell", "GetSpellName"), h.spell))) or h.name
	return name .. (h.rank > 0 and (MUTED .. "  rank " .. h.rank .. "|r") or "")
end

-- 14000 -> "1g 40s"
function LU.Money(c)
	c = c or 0
	local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
	local t = {}
	if g > 0 then t[#t + 1] = g .. "g" end
	if s > 0 then t[#t + 1] = s .. "s" end
	if cp > 0 or #t == 0 then t[#t + 1] = cp .. "c" end
	return table.concat(t, " ")
end

function LU.TrainerLine(t)
	if not t then return "No trainer known for your faction." end
	return ("%s, %s %.1f, %.1f"):format(t.name, B.ZoneName(ns.Data, t.map, ns.MapName) or t.zone, t.x * 100, t.y * 100)
end

-- "Level 40! Claw 6, Bite 7 for Shadowclaw; 2 at a pet trainer" (the chat line without its hint; the Recent page).
function LU.Summary(c)
	local parts = {}
	if #c.pet > 0 then
		local names = {}
		for i, it in ipairs(c.pet) do
			if i > 3 then names[#names] = names[#names] .. (" and %d more"):format(#c.pet - 3) break end
			names[#names + 1] = (it.famName and (it.famName .. ": ") or "") .. ("%s %d"):format(it.name, it.rank.rank)
		end
		parts[#parts + 1] = table.concat(names, ", ") .. (c.multi and "" or (" for " .. petWord(c)))
	end
	if #c.hunter > 0 then parts[#parts + 1] = ("%d new at the hunter trainer"):format(#c.hunter) end
	if #c.trainer > 0 then parts[#parts + 1] = ("%d at a pet trainer"):format(#c.trainer) end
	return ("Level %d! %s"):format(c.level, table.concat(parts, "; "))
end

-- The one chat line (the "chat instead" setting).
function LU.ChatLine(c)
	return ("%s. %s levelup shows them."):format(LU.Summary(c), ns.SLASH)
end

-- Every rank on the card, one plain line each (the Recent page's tooltip keeps the ones the card had no room for).
function LU.Lines(c)
	local out = {}
	for _, it in ipairs(c.pet or {}) do
		local who = it.petName or (not c.multi and c.petName) or nil
		out[#out + 1] = (it.famName and (it.famName .. ": ") or "") .. ("%s rank %d"):format(it.name, it.rank.rank)
			.. (who and (" for " .. who) or "")
	end
	for _, it in ipairs(c.trainer or {}) do out[#out + 1] = ("%s rank %d (pet trainer)"):format(it.name, it.rank.rank) end
	for _, h in ipairs(c.hunter or {}) do out[#out + 1] = (h.name or "?") .. ((h.rank or 0) > 0 and (" rank " .. h.rank) or "") .. " (hunter trainer)" end
	return out
end

------------------------------------------------------------------------
-- Reading the game for it
------------------------------------------------------------------------
function LU.Faction()
	local f = ns.Str((ns.Call(_G.UnitFactionGroup, "player")))
	return f == "Alliance" and "a" or f == "Horde" and "h" or nil
end

-- A map position as continent coordinates (yards), when the game can say.
function LU.Pos(map, x, y)
	local P = _G.CreateVector2D
	local vec = type(P) == "function" and ns.Call(P, x, y)
	if not vec then return nil end
	local cont, w = ns.Call(ns.api("C_Map", "GetWorldPosFromMapPos"), map, vec)
	cont = ns.Num(cont)
	if not (cont and type(w) == "table" and type(w.GetXY) == "function") then return nil end
	local wx, wy = ns.Call(w.GetXY, w)
	wx, wy = ns.Num(wx), ns.Num(wy)
	if not (wx and wy) then return nil end
	return cont, wx, wy
end

-- The card's content for `level` (default: yours now), from the state as it is.
function LU.Build(level, prev)
	local st = ns.state
	level = level or st.playerLevel
	if not (st.hunter and level) then return nil end
	local p = st.pet
	local here = ns.Here()
	local s = { level = level, prev = prev or (level - 1), hunterKnows = ns.HunterKnows, where = here,
		faction = LU.Faction(), pos = LU.Pos, nameOf = ns.AbilityName, familyName = ns.FamilyName }
	local cur
	if p and p.familyId and st.result and st.result.family then
		cur = { key = p.key, familyId = p.familyId, name = p.name, level = p.level, knows = function(spell) return ns.PetKnows(p, spell) end }
		s.petName = p.name
		if p.tpTotal then s.free = p.tpTotal - (p.tpUsed or 0) end
		s.lag = L.LagText(st.result.lag, ns.db and ns.db.lagWarn)
	end
	local mode = ns.db and ns.db.levelFamilies or "current"
	s.multi = mode == "these" or mode == "all"
	s.pets = ns.cdb and ns.cdb.pets or {}
	s.targets = LU.Targets(ns.Data, mode, ns.db and ns.db.levelFamilyList, s.pets, cur, ns.cdb and ns.cdb.lastPet)
	-- no pet out: the last one you had out
	if not cur and not s.multi and s.targets[1] then s.petName = s.targets[1].name end
	return LU.Compute(ns.Data, s)
end

------------------------------------------------------------------------
-- The card
------------------------------------------------------------------------
local W, PAD, ROW, SROW = 530, 16, 42, 24
local card, T

local function savePos(f)
	if not ns.db then return end
	local point, _, rel, x, y = f:GetPoint(1)
	if point then ns.db.levelCardPos = { point, rel or point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
end

local function place(f)
	f:ClearAllPoints()
	local p = ns.db and ns.db.levelCardPos
	if type(p) == "table" and p[1] then
		f:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	else
		-- top centre, under the minimap's height and well away from the action bars
		f:SetPoint("TOP", UIParent, "TOP", 0, -80)
	end
end

local function makeCard()
	if card then return card end
	T = (ns.app and ns.app.T) or UI.Theme
	local f = CreateFrame("Frame", ns.PREFIX .. "LevelCard", UIParent)
	f.eluiTheme = T
	f:SetSize(W, 200)
	f:SetFrameStrata("HIGH")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); savePos(self) end)
	f:Hide()
	UI.WindowChrome(f, T)
	UI.CloseButton(f, T)
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(28, 28)
	icon:SetPoint("TOPLEFT", PAD, -14)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.icon = icon
	f.title = UI.Text(f, T.fontHuge, T.text)
	f.title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 1)
	f.title:SetPoint("RIGHT", -40, 0)
	f.title:SetWordWrap(false)
	f.sub = UI.Text(f, T.fontSmall + 1, T.muted)
	f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
	f.sub:SetPoint("RIGHT", -40, 0)
	f.sub:SetWordWrap(false)
	f.body = CreateFrame("Frame", nil, f)
	f.body:SetPoint("TOPLEFT", PAD, -56)
	f.body:SetSize(W - 2 * PAD, 10)
	f.heads, f.rows, f.srows, f.infos = {}, {}, {}, {}
	f.note = UI.Text(f, T.fontSmall + 1, T.muted)
	f.note:SetWidth(W - 2 * PAD)
	f.hint = UI.Text(f, T.fontSmall, T.muted)
	f.hint:SetText("Missed it? " .. ns.SLASH .. " recent")
	f.primary = UI.Button(f, "Pin nearest trainer", function() LU.PinTrainer() end, 150, "accent")
	f.primary:SetPoint("BOTTOMRIGHT", -PAD, 14)
	f.open = UI.Button(f, "Open in " .. ns.NAME, function() LU.OpenPage() end, 170)
	UI.CloseOnEscape(f)
	card = f
	LU.frame = f
	return f
end

local function head(f, i)
	local h = f.heads[i]
	if h then return h end
	h = CreateFrame("Frame", nil, f.body)
	h:SetSize(W - 2 * PAD, 20)
	h.text = UI.Text(h, T.font, T.gold)
	h.text:SetPoint("LEFT", 0, 0)
	h.extra = UI.Text(h, T.fontSmall + 1, T.muted)
	h.extra:SetPoint("LEFT", h.text, "RIGHT", 8, 0)
	h.extra:SetPoint("RIGHT", -70, 0)
	h.extra:SetWordWrap(false)
	h.pin = UI.Button(h, "Pin", function(b) if b.onPin then b.onPin() end end, 56)
	h.pin:SetHeight(20)
	h.pin:SetPoint("RIGHT", 0, 0)
	f.heads[i] = h
	return h
end

-- A row card: icon, title, the line under it, a plain Pin button on the right.
local function row(f, i)
	local r = f.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, f.body)
	r:SetSize(W - 2 * PAD, ROW)
	r.bg = U.Solid(r, "BACKGROUND", rgba(T.surface))
	r.bg:SetAllPoints()
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(26, 26)
	r.icon:SetPoint("LEFT", 8, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.pin = UI.Button(r, "Pin", function() if r.onPin then r.onPin() end end, 56)
	r.pin:SetHeight(22)
	r.pin:SetPoint("RIGHT", -8, 0)
	r.title = UI.Text(r, T.font, T.text)
	r.title:SetWordWrap(false)
	r.sub = UI.Text(r, T.fontSmall + 1, T.muted)
	r.sub:SetWordWrap(false)
	-- the text runs up to Pin, or to the edge when there is no Pin
	function r:Fit()
		local right = self.pin:IsShown() and -70 or -10
		if self.right == right then return end
		self.right = right
		self.title:ClearAllPoints()
		self.title:SetPoint("TOPLEFT", 42, -7)
		self.title:SetPoint("RIGHT", right, 0)
		self.sub:ClearAllPoints()
		self.sub:SetPoint("TOPLEFT", self.title, "BOTTOMLEFT", 0, -3)
		self.sub:SetPoint("RIGHT", right, 0)
	end
	r:Fit()
	r:SetScript("OnEnter", function(self)
		self.bg:SetVertexColor(rgba(T.surfaceHi))
		if self.tip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			for li, line in ipairs(self.tip) do
				if li == 1 then GameTooltip:AddLine(line, 1, 1, 1) else GameTooltip:AddLine(line, nil, nil, nil, true) end
			end
			GameTooltip:Show()
		end
	end)
	r:SetScript("OnLeave", function(self) self.bg:SetVertexColor(rgba(T.surface)); GameTooltip:Hide() end)
	r:SetScript("OnClick", function(self) if self.onOpen then self.onOpen() end end)
	f.rows[i] = r
	return r
end

-- A small row for a trainer spell: icon, name and rank, its cost on the right.
local function srow(f, i)
	local r = f.srows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, f.body)
	r:SetSize((W - 2 * PAD) / 2 - 4, SROW)
	r.icon = r:CreateTexture(nil, "ARTWORK")
	r.icon:SetSize(18, 18)
	r.icon:SetPoint("LEFT", 2, 0)
	r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	r.text = UI.Text(r, T.font, T.text)
	r.text:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
	r.text:SetPoint("RIGHT", -2, 0)
	r.text:SetWordWrap(false)
	f.srows[i] = r
	return r
end

-- A muted line that wraps (where the trainer is, what the ranks cost).
local function info(f, i)
	local t = f.infos[i]
	if t then return t end
	t = UI.Text(f.body, T.fontSmall + 1, T.muted)
	t:SetWidth(W - 2 * PAD)
	f.infos[i] = t
	return t
end

LU.MAX_PET, LU.MAX_SPELLS, LU.MAX_TRAINER = 4, 8, 6 -- the card stays clear of the action bars

-- Fills the card from LU.Build's content.
function LU.Fill(c)
	local f = makeCard()
	f.content = c
	f.icon:SetTexture(ns.ICON)
	f.title:SetText(("Level %d!"):format(c.level))
	f.sub:SetText(c.petName and ("Here's what's new for you and " .. c.petName) or "Here's what's new for you and your pet")
	for _, x in ipairs(f.heads) do x:Hide() end
	for _, x in ipairs(f.rows) do x:Hide(); x.onPin, x.onOpen, x.tip = nil, nil, nil end
	for _, x in ipairs(f.srows) do x:Hide() end
	for _, x in ipairs(f.infos) do x:Hide() end
	local y, nh, nr, ns_, ni = 0, 0, 0, 0, 0
	local function note(text)
		ni = ni + 1
		local t = info(f, ni)
		t:SetText(text)
		t:ClearAllPoints()
		t:SetPoint("TOPLEFT", 0, -y)
		t:Show()
		y = y + math.max(14, math.ceil((t:GetStringHeight() or 12) + 2)) + 4
	end
	-- two columns of small rows: { icon, text }
	local function grid(list, max)
		local col = 0
		for i, d in ipairs(list) do
			if i > max then break end
			ns_ = ns_ + 1
			local r = srow(f, ns_)
			r.icon:SetTexture(d.icon)
			r.text:SetText(d.text)
			r:ClearAllPoints()
			r:SetPoint("TOPLEFT", col * ((W - 2 * PAD) / 2 + 4), -y)
			r:Show()
			col = col + 1
			if col == 2 then col, y = 0, y + SROW end
		end
		if col == 1 then y = y + SROW end
		if #list > max then note(("+%d more"):format(#list - max)) end
	end
	local function header(text, extra, onPin)
		nh = nh + 1
		local h = head(f, nh)
		h.text:SetText(text)
		h.extra:SetText(extra or "")
		h.pin.onPin = onPin
		h.pin:SetShown(onPin ~= nil)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", 0, -y)
		h:Show()
		y = y + 24
	end
	if #c.pet > 0 or c.lag then
		header(c.multi and "New ranks for your pets" or ("For " .. (c.petName or "your pet")))
		if c.lag then
			nr = nr + 1
			local r = row(f, nr)
			r.icon:SetTexture(ns.ICON)
			r.title:SetText("|cffff9f40" .. c.lag .. "|r")
			r.sub:SetText("Pets learn faster from kills near their own level.")
			r.pin:Hide()
			r:Fit()
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:Show()
			y = y + ROW + 4
		end
		local room = LU.MAX_PET - (c.lag and 1 or 0)
		for i, it in ipairs(c.pet) do
			if i > room then break end
			nr = nr + 1
			local r = row(f, nr)
			r.icon:SetTexture(ns.AbilityIcon(it.ab, it.rank))
			r.title:SetText(LU.PetTitle(it, c))
			r.sub:SetText(LU.PetSub(it, c))
			r.item = it
			if it.kind == "tame" and it.beast and it.spot then
				r.onPin = function() LU.PinBeast(it) end
				r.pin:Show()
			else
				r.pin:Hide()
			end
			r:Fit()
			r.onOpen = function()
				if it.beast then ns.Browser.OpenBeast(it.beast) elseif it.kind == "tame" or it.kind == "tameunknown" then ns.Browser.OpenSearch(it.name .. " " .. it.rank.rank) else LU.OpenPage() end
			end
			local tip = { it.name .. " rank " .. it.rank.rank, (L.Describe({ state = it.kind == "teach" and "train" or it.kind == "otherpet" and "otherpet" or "tame",
				target = it.rank, haveRank = it.have, otherName = it.otherName })) }
			for _, t in ipairs(it.beasts or {}) do tip[#tip + 1] = "  " .. L.TeacherLine(t) .. (t.tooHigh and (RED .. "  (level " .. t.lo .. "+)|r") or "") end
			if (it.beastCount or 0) > #(it.beasts or {}) then tip[#tip + 1] = ("  %d more beasts teach it (the Bestiary lists them)"):format(it.beastCount - #it.beasts) end
			if it.cost then tip[#tip + 1] = ("%d training points%s"):format(it.cost, (it.net and it.net ~= it.cost) and (" (" .. it.net .. " for your pet)") or "") end
			tip[#tip + 1] = MUTED .. "Click for the beast's page; Pin sets a waypoint to its nearest spawn spot.|r"
			r.tip = tip
			r:ClearAllPoints(); r:SetPoint("TOPLEFT", 0, -y); r:Show()
			y = y + ROW + 4
		end
		if #c.pet > room then
			header(MUTED .. ("and %d more · %s recent|r"):format(#c.pet - room, ns.SLASH))
		end
		y = y + 6
	end
	if #c.hunter > 0 then
		header("At the hunter trainer")
		local list, total = {}, 0
		for _, h in ipairs(c.hunter) do
			total = total + (h.cost or 0)
			list[#list + 1] = { icon = ns.Num((ns.Call(ns.api("C_Spell", "GetSpellTexture"), h.spell))) or (h.icon ~= 0 and h.icon) or ns.ICON,
				text = LU.HunterTitle(h) }
		end
		grid(list, LU.MAX_SPELLS)
		note((c.hunterTrainer and ("Nearest: " .. LU.TrainerLine(c.hunterTrainer)) or "No hunter trainer known for your faction")
			.. (" · %s in all"):format(LU.Money(total)))
		y = y + 8
	end
	if #c.trainer > 0 then
		header("At a pet trainer", nil, (c.petTrainer and c.hunterPin) and function() LU.PinTrainer("pet") end or nil)
		local list = {}
		for _, it in ipairs(c.trainer) do
			list[#list + 1] = { icon = ns.AbilityIcon(it.ab, it.rank), text = it.name .. MUTED .. "  rank " .. it.rank.rank .. "|r" }
		end
		grid(list, LU.MAX_TRAINER)
		note((c.petTrainer and ("Nearest: " .. LU.TrainerLine(c.petTrainer) .. ". ") or "")
			.. ("Buy them, then teach them to %s with Beast Training."):format(petWord(c)))
		y = y + 6
	end
	f.body:SetHeight(math.max(10, y))
	f.note:ClearAllPoints()
	f.note:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -2)
	f.note:SetText(f.noteText or "")
	local noteH = (f.noteText and f.noteText ~= "") and 18 or 0
	f.hint:ClearAllPoints()
	f.hint:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -noteH - 2)
	-- the one primary button: a trainer to go to (the hunter trainer's first, else the pet trainer's)
	local hunterTr = c.hunterPin and c.hunterTrainer or nil
	local tr = hunterTr or c.petTrainer
	f.primary:SetShown(tr ~= nil)
	f.primary:SetText(hunterTr and "Pin nearest trainer" or "Pin pet trainer")
	f.open:ClearAllPoints()
	if tr then f.open:SetPoint("RIGHT", f.primary, "LEFT", -8, 0) else f.open:SetPoint("BOTTOMRIGHT", -PAD, 14) end
	f:SetHeight(56 + y + noteH + 16 + 52)
	return f
end

function LU.SetNote(text, ok)
	local f = card
	if not f then return end
	f.noteText = text and ((ok and GREEN or MUTED) .. text .. "|r") or nil
	if f.content then LU.Fill(f.content) end
end

function LU.PinBeast(it)
	if not (it and it.beast) then return nil end
	local how, _, text = ns.Browser.Waypoint(it.beast, it.spot)
	LU.SetNote(text, how ~= nil)
	return how, text
end

-- A waypoint to the nearest hunter trainer (kind "pet": the pet trainer). Returns how and the line said.
function LU.PinTrainer(kind)
	local c = card and card.content
	if not c then return nil end
	local t = (kind == "pet" and c.petTrainer) or (kind ~= "pet" and ((c.hunterPin and c.hunterTrainer) or c.petTrainer))
	if not t then return nil end
	local how = ns.SetWaypoint(t.map, t.x, t.y, t.name)
	local where = LU.TrainerLine(t)
	local text = (how == "tomtom" and ("TomTom waypoint: " .. where .. "."))
		or (how == "game" and ("Waypoint: " .. where .. " (on your map and screen)."))
		or ("This map takes no waypoint. " .. where .. ".")
	LU.SetNote(text, how ~= nil)
	return how, text
end

-- "Open in EverlookDB Pets": the Your pet page (what it can still learn, with every beast).
function LU.OpenPage()
	if ns.app then ns.app:Open("pet") end
end

------------------------------------------------------------------------
-- When it shows
------------------------------------------------------------------------
-- Shows what's new at `level` (default: yours now): the card, or the chat line when that setting is on. Nothing
-- new: nothing (forced, from /epets levelup: one line saying so). In combat it waits for the fight to end.
-- Returns "card", "chat", "none", "waiting" or nil (not a hunter).
function LU.Show(level, forced)
	if not (ns.state and ns.state.hunter) then
		if forced then ns:Print("the level-up card is for hunters.") end
		return nil
	end
	if ns.Call(InCombatLockdown) then
		LU.pending = { level = level, forced = forced }
		return "waiting"
	end
	LU.pending = nil
	local c = LU.Pick(LU.Build(level), LU.Sections())
	if not c then return nil end
	LU.last = c
	if c.empty then
		if forced then ns:Print(("level %d: nothing new for you or your pet at this level (in the parts of the card you have on: Settings, Level up)."):format(c.level)) end
		return "none"
	end
	if not forced and ns.db.levelChat then
		ns.Tell("levelup", LU.Summary(c), { level = c.level, more = LU.Lines(c) })
		return "chat"
	end
	if not forced and not ns.db.levelCard then return "none" end
	-- the Recent page keeps what the card showed (not when you asked for it: /epets levelup, Show card)
	if not forced then ns.Recent.Add("levelup", LU.Summary(c), { level = c.level, more = LU.Lines(c) }) end
	if card then card.noteText = nil end
	local f = LU.Fill(c)
	place(f)
	f:Show()
	return "card"
end

function LU.Hide() if card then card:Hide() end end

-- PLAYER_LEVEL_UP (level): the pet's level, your spells and the trainer's list settle a moment later, so the card
-- reads the state once it has (Core's update runs half a second after the burst).
function LU.OnLevelUp(level)
	if not ns.IsHunter() then return end
	level = ns.Num(level)
	C_Timer.After(1.5, function()
		ns:Update()
		LU.Show(level)
	end)
end

function LU.OnCombatEnd()
	local p = LU.pending
	if not p then return end
	LU.pending = nil
	C_Timer.After(1, function() LU.Show(p.level, p.forced) end)
end

ns.On("PLAYER_LOGIN", function()
	if not ns.IsHunter() then return end
	ns.On("PLAYER_LEVEL_UP", function(_, level) LU.OnLevelUp(level) end)
	ns.On("PLAYER_REGEN_ENABLED", function() LU.OnCombatEnd() end)
end)
