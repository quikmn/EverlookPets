-- Everlook Pets: core. Names, saved settings, events, and reading the game: your pet, what it knows, what you know.
-- Every game call goes through ns.Call (missing function or an error gives nil) and every value through ns.Num or
-- ns.Str (secret values and odd types give nil), so a change in the client never breaks the addon.
local ADDON, ns = ...

------------------------------------------------------------------------
-- The name. Renaming the addon: change these lines, the .toc Title and SavedVariables lines, and (if the folder
-- changes) the .toc file name and the folder.
------------------------------------------------------------------------
ns.NAME = "Everlook Pets"
ns.SLASH = "/epets"
ns.SLASH_ID = "EVERLOOKPETS"
ns.PREFIX = "EverlookPets" -- global frame names and the LibDataBroker name
ns.SAVED = "EverlookPetsDB"          -- settings (account)
ns.SAVED_CHAR = "EverlookPetsCharDB" -- your pets and what was already announced (per character)
ns.ADDON = ADDON
ns.ICON = "Interface\\Icons\\Ability_Hunter_BeastTaming"

local UI = LibStub("EverlookUI-1")
ns.UI = UI
ns.Util = UI.Util

------------------------------------------------------------------------
-- Safe values and calls
------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end

-- A plain number, or nil (secret, nil, NaN or not a number).
function ns.Num(v)
	if v == nil or issecret(v) or type(v) ~= "number" or v ~= v then return nil end
	return v
end

-- A plain string, or nil.
function ns.Str(v)
	if v == nil or issecret(v) or type(v) ~= "string" then return nil end
	return v
end

-- A plain boolean, or nil.
function ns.Bool(v)
	if v == nil or issecret(v) or type(v) ~= "boolean" then return nil end
	return v
end

local function after(ok, ...)
	if ok then return ... end
	return nil
end
-- Calls a game function if it exists; nil when it doesn't or when it errors.
function ns.Call(fn, ...)
	if type(fn) ~= "function" then return nil end
	return after(pcall(fn, ...))
end

local function api(ns_, name) local t = _G[ns_]; return type(t) == "table" and t[name] or nil end
ns.api = api

function ns:Print(msg)
	if ns.app then ns.app:Print(msg) else DEFAULT_CHAT_FRAME:AddMessage(ns.NAME .. ": " .. tostring(msg)) end
end

------------------------------------------------------------------------
-- Saved settings
------------------------------------------------------------------------
ns.DEFAULTS = {
	chat = true,        -- a chat line when something becomes actionable
	lagWarn = 3,        -- say so when the pet is this many levels below you (0: never)
	minimap = "auto",   -- the minimap button: true, false, or "auto" (shown unless Everlook Bar is loaded: its plugin shows the same)
	angle = 200,        -- where the minimap button sits around the minimap (degrees)
	tooltip = true,     -- "Tameable" lines on beasts' tooltips
	showLocked = true,  -- list abilities that open at a higher pet level
	rareAlert = true,   -- a chat line when a rare tameable beast is near
	wishAlert = true,   -- ... and when a beast on your wishlist is
	alertSound = true,  -- with a sound (a soft one: the map ping)
	alertLoud = false,  -- ... the raid warning sound instead
	models = true,      -- 3D models on the beast page
	mapPins = true,     -- "Tameable beasts" pins on the world map
}
-- wishlist: { [npc id] = true } (the bestiary's star); tamed: { [npc id] = times } (your own tames, for "tamed by you")
ns.CHAR_DEFAULTS = { pets = {}, alerted = {}, unseen = {}, lagNoted = {}, wishlist = {}, tamed = {} }

local function fill(dst, defaults)
	for k, v in pairs(defaults) do
		if dst[k] == nil then dst[k] = type(v) == "table" and {} or v end
	end
	return dst
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}
frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		local ok, err = pcall(fn, event, ...)
		if not ok then local h = geterrorhandler and geterrorhandler(); if h then h(err) end end
	end
end)

-- Runs fn(event, ...) on the event. An event this client doesn't know is skipped quietly.
function ns.On(event, fn)
	if not handlers[event] then
		if not pcall(frame.RegisterEvent, frame, event) then return false end
		handlers[event] = {}
	end
	table.insert(handlers[event], fn)
	return true
end

------------------------------------------------------------------------
-- Reading the game
------------------------------------------------------------------------
local function bank(name, fallback)
	local e = Enum and Enum.SpellBookSpellBank
	local v = e and e[name]
	if v == nil then return fallback end
	return v
end

function ns.IsHunter()
	local _, class = ns.Call(UnitClass, "player")
	return ns.Str(class) == "HUNTER"
end

-- The family id for a family name the game gave (localized name: match it through our data's English keys first,
-- then through the pet's own family id).
local function familyIdOf(name, id)
	id = ns.Num(id)
	if id and ns.Data.families[id] then return id end
	for fid, f in pairs(ns.Data.families) do
		if f.key == name then return fid end
	end
	return nil
end

-- Your active pet, or nil. Fields may be nil when the game doesn't say.
function ns.ReadPet()
	if not ns.Call(UnitExists, "pet") then return nil end
	local p = { knows = {} }
	p.name = ns.Str((ns.Call(UnitName, "pet")))
	local famName, famId = ns.Call(UnitCreatureFamily, "pet")
	p.familyName = ns.Str(famName)
	p.familyId = familyIdOf(p.familyName, famId)
	p.level = ns.Num((ns.Call(UnitLevel, "pet")))
	local happy, dmg, rate = ns.Call(api("C_PetInfo", "GetPetHappiness"))
	p.happiness, p.damagePct, p.loyaltyRate = ns.Num(happy), ns.Num(dmg), ns.Num(rate)
	p.loyalty = ns.Str((ns.Call(api("C_PetInfo", "GetPetLoyalty"))))
	local total, used = ns.Call(api("C_PetInfo", "GetPetTrainingPoints"))
	p.tpTotal, p.tpUsed = ns.Num(total), ns.Num(used)
	local foods = ns.Call(api("C_PetInfo", "GetPetFoodTypes"))
	if type(foods) == "table" then
		p.foods = {}
		for _, f in ipairs(foods) do if ns.Str(f) then p.foods[#p.foods + 1] = f end end
	end
	-- the pet's spellbook: every spell it knows, by id
	local n = ns.Num((ns.Call(api("C_SpellBook", "HasPetSpells"))))
	local get = api("C_SpellBook", "GetSpellBookItemInfo")
	local petBank = bank("Pet", 1)
	for i = 1, n or 0 do
		local info = ns.Call(get, i, petBank)
		if type(info) == "table" then
			local id = ns.Num(info.spellID) or ns.Num(info.actionID)
			if id then p.knows[id] = true end
		end
	end
	p.spellCount = n or 0
	p.guid = ns.Str((ns.Call(UnitGUID, "pet")))
	p.npc = ns.PetNpcId(p.guid)
	-- the game's name for its family, in your language
	if p.familyId and p.familyName then
		ns.familyNames = ns.familyNames or {}
		ns.familyNames[p.familyId] = p.familyName
	end
	return p
end

-- Does the pet know this spell? Its spellbook first, then the game's own check.
function ns.PetKnows(p, spell)
	if p and p.knows[spell] then return true end
	return ns.Call(api("C_SpellBook", "IsSpellKnown"), spell, bank("Pet", 1)) == true
end

-- Do you (the hunter) know this rank, so Beast Training can teach it?
function ns.HunterKnows(spell)
	return ns.Call(api("C_SpellBook", "IsSpellKnown"), spell, bank("Player", 0)) == true
end

-- The pet's key in your saved pets: name and family.
function ns.PetKey(p) return tostring(p.name or "?") .. "|" .. tostring(p.familyId or 0) end

-- Remember what one of your pets knows (only our abilities' spells), for "another pet knows it". guid: the pet's
-- GUID when it is out (kept from before when not given), so a renamed pet is found again.
local function remember(key, name, familyId, level, spells, guid)
	local keep = {}
	for id in pairs(spells) do if ns.rankOf[id] then keep[id] = true end end
	local old = ns.cdb.pets[key]
	ns.cdb.pets[key] = { name = name, family = familyId, level = level, spells = keep, guid = guid or (old and old.guid) }
end

-- Everything saved per pet, by its key (name|family).
local function perPet() return { ns.cdb.pets, ns.cdb.alerted, ns.cdb.unseen, ns.cdb.lagNoted } end

-- A pet's saved entries move to its new key (you renamed it). What the new key already has stays.
function ns.MovePet(old, new)
	if old == new then return end
	for _, t in ipairs(perPet()) do
		if t[old] ~= nil and t[new] == nil then t[new] = t[old] end
		t[old] = nil
	end
end

-- The pet out now under another key with the same GUID: it was renamed. Move its entries over.
function ns.FollowRename(p, key)
	if not (p and p.guid and ns.cdb) then return end
	local olds = {}
	for k, rec in pairs(ns.cdb.pets) do
		if k ~= key and type(rec) == "table" and rec.guid == p.guid then olds[#olds + 1] = k end
	end
	for _, k in ipairs(olds) do ns.MovePet(k, key) end
end

-- Your stabled and active pets as the stable shows them (only while it is open, or after it was opened).
function ns.ReadStable()
	local seen, any = {}, false
	for _, fn in ipairs({ "GetActivePetList", "GetStabledPetList" }) do
		local list = ns.Call(api("C_StableInfo", fn))
		if type(list) == "table" then
			for _, info in ipairs(list) do
				local name = type(info) == "table" and ns.Str(info.name)
				if name then
					any = true
					local fid = familyIdOf(ns.Str(info.familyName), nil)
					local spells = {}
					for _, id in ipairs(type(info.petAbilities) == "table" and info.petAbilities or {}) do
						if ns.Num(id) then spells[id] = true end
					end
					local key = name .. "|" .. tostring(fid or 0)
					seen[key] = true
					remember(key, name, fid, ns.Num(info.level), spells)
				end
			end
		end
	end
	-- a pet you no longer have (abandoned, or renamed elsewhere) stops counting, and what was said about it goes
	if any then
		local out = ns.state.pet and ns.state.pet.key
		if out then seen[out] = true end -- the pet out now always stays
		for _, t in ipairs(perPet()) do
			local gone = {}
			for key in pairs(t) do if not seen[key] then gone[#gone + 1] = key end end
			for _, key in ipairs(gone) do t[key] = nil end
		end
	end
end

-- The name of another of your pets that knows this spell, or nil.
function ns.OtherPetKnows(currentKey, spell)
	for key, pet in pairs(ns.cdb.pets) do
		if key ~= currentKey and pet.spells and pet.spells[spell] then return pet.name end
	end
	return nil
end

-- The ability's name in the game's language (our English name if the game has none).
function ns.AbilityName(ab)
	return ns.Str((ns.Call(api("C_Spell", "GetSpellName"), ab.ranks[1].spell))) or ab.name
end

-- Where you are, for "beasts near you": { level, zone (uiMap id), continent (uiMap id) }; nil fields when unknown.
function ns.Where()
	local out = { level = ns.Num((ns.Call(UnitLevel, "player"))) }
	local map = ns.Num((ns.Call(api("C_Map", "GetBestMapForUnit"), "player")))
	local info = api("C_Map", "GetMapInfo")
	-- walk up to the zone (type 3) and the continent (type 2) the map belongs to
	for _ = 1, 6 do
		if not map then break end
		local z = ns.Data.zones and ns.Data.zones[map]
		if z and not out.zone then out.zone, out.continent = map, z[2] end
		local mi = ns.Call(info, map)
		if type(mi) ~= "table" then break end
		if mi.mapType == 3 and not out.zone then out.zone = map end
		if mi.mapType == 2 then out.continent = out.continent or map; break end
		map = ns.Num(mi.parentMapID)
	end
	return out
end

-- Where exactly you are: { map, x, y (0-1), zone, continent, level }; nil fields when unknown.
function ns.Here()
	local w = ns.Where()
	local map = ns.Num((ns.Call(api("C_Map", "GetBestMapForUnit"), "player")))
	w.map = map
	local pos = map and ns.Call(api("C_Map", "GetPlayerMapPosition"), map, "player")
	if type(pos) == "table" and not issecret(pos) and type(pos.GetXY) == "function" then
		local x, y = ns.Call(pos.GetXY, pos)
		w.x, w.y = ns.Num(x), ns.Num(y)
	end
	return w
end

-- A map's name in your language (the game's), or nil.
function ns.MapName(id)
	if type(id) ~= "number" then return nil end
	local mi = ns.Call(api("C_Map", "GetMapInfo"), id)
	return type(mi) == "table" and ns.Str(mi.name) or nil
end

-- A family's name in your language when the game told us (your pets), else our English one.
function ns.FamilyName(id)
	local f = ns.Data.families[id or 0]
	if not f then return nil end
	return ns.familyNames and ns.familyNames[id] or f.key
end

-- A waypoint to map x, y (0-1): TomTom's when TomTom is loaded, else the game's own (the map pin and the arrow on
-- your screen). Returns "tomtom", "game" or nil (this map takes no waypoint).
function ns.SetWaypoint(map, x, y, title)
	if not (map and x and y) then return nil end
	local tt = _G.TomTom
	if type(tt) == "table" and type(tt.AddWaypoint) == "function" then
		local ok = pcall(tt.AddWaypoint, tt, map, x, y, { title = title, from = ns.NAME, persistent = false })
		if ok then return "tomtom" end
	end
	if ns.Call(api("C_Map", "CanSetUserWaypointOnMap"), map) ~= true then return nil end
	local P = _G.UiMapPoint
	local point = type(P) == "table" and ns.Call(P.CreateFromCoordinates, map, x, y)
	if not point then return nil end
	if ns.Call(api("C_Map", "SetUserWaypoint"), point) == false then return nil end
	ns.Call(api("C_SuperTrack", "SetSuperTrackedUserWaypoint"), true)
	return "game"
end

-- The npc id a pet came from: a tamed pet's GUID keeps it ("Pet-0-4372-1-14-3068-0200ABCDEF" -> 3068).
function ns.PetNpcId(guid)
	if type(guid) ~= "string" or issecret(guid) then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind ~= "Pet" and kind ~= "Creature" then return nil end
	return tonumber(id)
end

-- "Tamed by you": a tame of npc id (n more times; 0 just marks it, for a pet we see that we didn't watch you tame).
function ns.RecordTame(npc, n)
	if not (npc and ns.cdb and ns.cdb.tamed) then return end
	if not (ns.Data.tameable[npc] or (ns.Data.beasts and ns.Data.beasts[npc])) then return end
	ns.cdb.tamed[npc] = math.max(1, (ns.cdb.tamed[npc] or 0) + (n or 1))
end

-- Is the minimap button wanted? "auto": yes, unless Everlook Bar is loaded (its bar plugin shows the same count).
function ns.ShowMinimapButton()
	local v = ns.db and ns.db.minimap
	if v == "auto" or v == nil then
		local loaded = ns.Call(api("C_AddOns", "IsAddOnLoaded"), "EverlookBar") or ns.Call(_G.IsAddOnLoaded, "EverlookBar")
		return not loaded
	end
	return v == true
end

function ns.IsWished(npc) return ns.cdb and ns.cdb.wishlist and ns.cdb.wishlist[npc] and true or false end
function ns.SetWished(npc, on)
	if not (npc and ns.cdb) then return end
	ns.cdb.wishlist[npc] = on and true or nil
end

function ns.AbilityIcon(ab, rank)
	local spell = (rank and rank.spell) or ab.ranks[1].spell
	return ns.Num((ns.Call(api("C_Spell", "GetSpellTexture"), spell))) or ab.icon
end

------------------------------------------------------------------------
-- The state everything shows: ns.state = { hunter, playerLevel, pet, result }
------------------------------------------------------------------------
ns.state = { hunter = false }

function ns:Update()
	local st = { hunter = ns.IsHunter(), playerLevel = ns.Num((ns.Call(UnitLevel, "player"))) }
	if st.hunter then
		local p = ns.ReadPet()
		st.pet = p
		if p then
			local key = ns.PetKey(p)
			p.key = key
			ns.FollowRename(p, key)
			if p.familyId then remember(key, p.name, p.familyId, p.level, p.knows, p.guid) end
			-- a pet you have came from a tame of yours: "tamed by you" in the bestiary
			if p.npc and ns.cdb and not ns.cdb.tamed[p.npc] then ns.RecordTame(p.npc, 0) end
			st.result = ns.Logic.Evaluate(ns.Data, {
				familyId = p.familyId, petLevel = p.level or 1, playerLevel = st.playerLevel,
				petKnows = function(spell) return ns.PetKnows(p, spell) end,
				hunterKnows = ns.HunterKnows,
				otherPet = function(spell) return ns.OtherPetKnows(key, spell) end,
				nameOf = ns.AbilityName,
			})
		end
	end
	ns.state = st
	if ns.Alerts then ns.Alerts:Check(st) end
	if ns.app and ns.app:IsShown() then ns.app:Refresh() end
	-- the world map's pins wait for the end of a fight (nobody plans a tame mid-combat)
	if ns.MapPins then
		if ns.Call(InCombatLockdown) then ns.pinsDirty = true else ns.pinsDirty = false; ns.MapPins:Refresh() end
	end
	ns.updates = (ns.updates or 0) + 1 -- tests
end

-- Many events come in bursts (a level up fires five): update once, a moment later.
local queued = false
function ns:Queue()
	if queued then return end
	queued = true
	C_Timer.After(0.5, function() queued = false; ns:Update() end)
end

-- Events that fire all through a fight (happiness, the pet bar, spells) and change nothing to do mid-fight: in
-- combat they only mark the state stale, and it is read once when combat ends.
local combatDirty = false
function ns:QueueLater()
	if ns.Call(InCombatLockdown) then combatDirty = true return end
	ns:Queue()
end
function ns.OnCombatEnd()
	if combatDirty then
		combatDirty = false
		ns:Queue()
	elseif ns.pinsDirty and ns.MapPins then
		ns.pinsDirty = false
		ns.MapPins:Refresh()
	end
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------
-- spell id -> { ability, rank } for every rank we know of
ns.rankOf = {}
for key, ab in pairs(ns.Data.abilities) do
	for _, r in ipairs(ab.ranks) do ns.rankOf[r.spell] = { key = key, rank = r.rank } end
end

ns.On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	_G[ns.SAVED] = fill(type(_G[ns.SAVED]) == "table" and _G[ns.SAVED] or {}, ns.DEFAULTS)
	_G[ns.SAVED_CHAR] = fill(type(_G[ns.SAVED_CHAR]) == "table" and _G[ns.SAVED_CHAR] or {}, ns.CHAR_DEFAULTS)
	ns.db, ns.cdb = _G[ns.SAVED], _G[ns.SAVED_CHAR]
	-- 2026-11-19: the minimap button's default became "auto" (off while Everlook Bar is loaded). Saved settings from
	-- before have the old default written in (true); a switched-off button (false) stays off.
	if (tonumber(ns.db.version) or 1) < 2 then
		if ns.db.minimap == true then ns.db.minimap = "auto" end
		ns.db.version = 2
	end
	if ns.OnLoaded then ns.OnLoaded() end
end)

-- Other classes stop here: no pet events, no alerts, no plugin, no map pins (MapPins.lua), no tooltip lines. The
-- Bestiary (/epets beasts) still works for everyone; its data is part of the addon's files.
ns.On("PLAYER_LOGIN", function()
	if not ns.IsHunter() then return end
	ns.state.hunter = true
	if ns.Alerts then ns.Alerts:StartWatching(); ns.Alerts:SetupBroker() end
	local function queue() ns:Queue() end
	local function later() ns:QueueLater() end
	local function petOrPlayer(_, unit) if unit == "pet" or unit == "player" then ns:Queue() end end
	ns.On("UNIT_PET", petOrPlayer)
	ns.On("UNIT_LEVEL", petOrPlayer)
	ns.On("UNIT_HAPPINESS", function(_, unit) if unit == "pet" or unit == "player" then ns:QueueLater() end end)
	ns.On("UNIT_PET_TRAINING_POINTS", petOrPlayer)
	for _, e in ipairs({ "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_SKILL_LINE" }) do ns.On(e, queue) end
	for _, e in ipairs({ "SPELLS_CHANGED", "PET_BAR_UPDATE" }) do ns.On(e, later) end
	ns.On("PLAYER_REGEN_ENABLED", function() ns.OnCombatEnd() end)
	-- Tame Beast (1515) on a target, then a new pet: that beast is tamed by you
	local pending
	ns.On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, _, spell)
		if unit ~= "player" or ns.Num(spell) ~= 1515 then return end
		local npc = ns.NpcId and ns.NpcId(ns.Str((ns.Call(UnitGUID, "target"))))
		pending = npc and { npc = npc, at = ns.Num((ns.Call(GetTime))) or 0 } or nil
	end)
	ns.On("UNIT_PET", function(_, unit)
		if unit ~= "player" or not pending then return end
		local now = ns.Num((ns.Call(GetTime))) or 0
		if now - pending.at <= 30 and ns.Call(UnitExists, "pet") then
			local npc = ns.PetNpcId((ns.Call(UnitGUID, "pet")))
			if npc == nil or npc == pending.npc then ns.RecordTame(pending.npc, 1) end
			pending = nil
		end
	end)
	local function stable() ns.ReadStable(); ns:Queue() end
	ns.On("PET_STABLE_SHOW", stable)
	ns.On("PET_STABLE_UPDATE", stable)
	-- the pet's spellbook fills a little after login
	C_Timer.After(3, function() ns:Update() end)
end)
