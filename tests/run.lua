-- Offline tests for Everlook Pets: the rank logic on fake data, then the whole addon loaded in TOC order against
-- wowmock.lua with a fake hunter and pet: what it shows, when it speaks up in chat, the badge, the chat commands and
-- the tameable tooltip lines.
local ROOT = ...
local ADDON = "EverlookPets"
local ns = {}
local failures, passes = {}, 0

local function step(name, fn)
	local ok, err = pcall(fn)
	if ok then passes = passes + 1; print("  ok   " .. name)
	else failures[#failures + 1] = name .. ": " .. tostring(err); print("  FAIL " .. name .. "\n         " .. tostring(err)) end
end
local function check(cond, msg) if not cond then error(msg, 2) end end
local function eq(a, b, what) if a ~= b then error((what or "value") .. ": expected " .. tostring(b) .. ", got " .. tostring(a), 2) end end
local function flush() MOCK.RunTimers() end
local function slash(msg) SlashCmdList.EVERLOOKPETS(msg) end
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function logSince(n)
	local out = {}
	for i = n + 1, #MOCK.log do out[#out + 1] = strip(MOCK.log[i]) end
	return out
end
local function has(lines, s)
	for _, l in ipairs(lines) do if l:find(s, 1, true) then return true end end
	return false
end
local function set(...) local t = {}; for _, v in ipairs({ ... }) do t[v] = true end; return t end

-- Taint guard: our own files may only write these globals.
local ALLOWED = { EverlookPetsDB = true, EverlookPetsCharDB = true, SLASH_EVERLOOKPETS1 = true, SLASH_EVERLOOKPETS2 = true }
local globalWrites, missingReads = {}, {}
local addonEnv = setmetatable({}, {
	__index = function(_, k) local v = _G[k]; if v == nil then missingReads[k] = true end; return v end,
	__newindex = function(_, k, v) globalWrites[k] = true; _G[k] = v end,
})

step("load TOC files", function()
	local toc = assert(io.open(ROOT .. "/EverlookPets.toc")):read("*a")
	for line in toc:gmatch("[^\r\n]+") do
		if not line:match("^%s*#") and line:match("%.lua%s*$") then
			local rel = line:gsub("\\", "/"):gsub("%s+$", "")
			local chunk, err = loadfile(ROOT .. "/" .. rel)
			if not chunk then error("syntax: " .. err) end
			if not rel:find("^Libs/") then setfenv(chunk, addonEnv) end
			chunk(ADDON, ns)
		end
	end
	check(ns.Logic and ns.Data and ns.app, "addon tables missing")
end)

------------------------------------------------------------------------
-- The rank logic, on fake data
------------------------------------------------------------------------
local L = ns.Logic
local BITE = { name = "Bite", petopia = "bite", trainer = false, forever = false,
	ranks = { { rank = 1, level = 1, spell = 101 }, { rank = 2, level = 8, spell = 102 }, { rank = 3, level = 16, spell = 103 }, { rank = 4, level = 24, spell = 104 } } }
local GROWL = { name = "Growl", petopia = "growl", trainer = true, forever = false,
	ranks = { { rank = 1, level = 1, spell = 201 }, { rank = 2, level = 10, spell = 202 }, { rank = 3, level = 20, spell = 203 } } }
local DASH = { name = "Dash", petopia = "dash", trainer = false, forever = false,
	ranks = { { rank = 1, level = 30, spell = 301 }, { rank = 2, level = 40, spell = 302 } } }
local PINCH = { name = "Pinch", petopia = "pinch", trainer = false, forever = true,
	ranks = { { rank = 1, level = 12, spell = 401, forever = true }, { rank = 2, level = 24, spell = 402, forever = true } } }
local FAKE = {
	foods = { "Meat", "Fish", "Cheese", "Bread", "Fungus", "Fruit", "Raw meat", "Raw fish" },
	families = { [2] = { key = "Cat", petopia = "cat", diet = 3, abilities = { "Bite", "Growl", "Dash", "Pinch", "Missing" } } },
	abilities = { Bite = BITE, Growl = GROWL, Dash = DASH, Pinch = PINCH },
}
local function knows(t) return function(spell) return t[spell] == true end end

step("logic: rank window (best for the level, the next one)", function()
	local best, nxt = L.RankWindow(BITE, 10)
	eq(best.rank, 2, "best at 10"); eq(nxt.rank, 3, "next at 10")
	best, nxt = L.RankWindow(BITE, 24)
	eq(best.rank, 4, "best at 24"); eq(nxt, nil, "maxed")
	best, nxt = L.RankWindow(DASH, 20)
	eq(best, nil, "nothing yet"); eq(nxt.rank, 1)
	eq(L.HighestKnown(BITE, knows(set(101, 103))).rank, 3, "highest known")
	eq(L.HighestKnown(BITE, knows(set(101, 103)), 2).rank, 1, "capped")
end)

step("logic: each state and what it says", function()
	local r = L.Ability(DASH, 20, {})
	eq(r.state, "locked"); check(not r.actionable, "locked isn't actionable")
	check(L.Describe(r):find("Opens at pet level 30", 1, true), L.Describe(r))

	r = L.Ability(BITE, 10, { petKnows = knows(set(101, 102)) })
	eq(r.state, "trained"); eq(r.haveRank, 2)
	check(L.Describe(r):find("rank 3 at pet level 16", 1, true), L.Describe(r))
	r = L.Ability(BITE, 30, { petKnows = knows(set(104)) })
	check(L.Describe(r):find("highest rank", 1, true), "maxed text")

	r = L.Ability(BITE, 10, { petKnows = knows(set(101)), hunterKnows = knows(set(101, 102)) })
	eq(r.state, "train"); eq(r.target.rank, 2); check(r.actionable, "train is actionable")
	check(L.Describe(r):find("Train now: you know rank 2, your pet has rank 1", 1, true), L.Describe(r))

	-- the hunter knows rank 3 but the pet is too low for it: nothing to train beyond rank 2
	r = L.Ability(BITE, 10, { petKnows = knows(set(102)), hunterKnows = knows(set(103)) })
	eq(r.state, "trained", "rank 3 waits for pet level 16")
	r = L.Ability(BITE, 10, { petKnows = knows(set(101)), hunterKnows = knows(set(103)) })
	eq(r.state, "tame", "a rank the pet can't use yet doesn't count")

	r = L.Ability(GROWL, 10, { petKnows = knows(set(201)) })
	eq(r.state, "trainer"); eq(r.target.rank, 2)
	check(L.Describe(r):find("Buy rank 2 from a pet trainer (your pet has rank 1)", 1, true), L.Describe(r))
	r = L.Ability(GROWL, 10, { petKnows = knows(set(201)), hunterKnows = knows(set(202)) })
	eq(r.state, "train", "bought already: train it")

	r = L.Ability(BITE, 10, { petKnows = knows(set(101)), otherPet = function(s) return s == 102 and "Fang" or nil end })
	eq(r.state, "otherpet"); eq(r.otherName, "Fang"); eq(r.target.rank, 2)

	r = L.Ability(BITE, 10, { petKnows = knows(set(101)) })
	eq(r.state, "tame"); eq(r.target.rank, 2); check(r.actionable)
	check(L.Describe(r):find("Tame a beast that knows rank 2 (your pet has rank 1)", 1, true), L.Describe(r))
	r = L.Ability(BITE, 10, {})
	check(L.Describe(r):find("your pet has none", 1, true), "none")

	r = L.Ability(PINCH, 12, {})
	eq(r.state, "forever"); check(not r.actionable, "forever isn't actionable: we don't know how")
end)

step("logic: a pet's whole family, things to do first, links", function()
	local res = L.Evaluate(FAKE, { familyId = 2, petLevel = 10, playerLevel = 15,
		petKnows = knows(set(101, 201)), hunterKnows = knows(set()), otherPet = function() return nil end })
	eq(#res.rows, 4, "unknown ability names are skipped")
	eq(res.rows[1].state, "trainer"); eq(res.rows[2].state, "tame"); eq(res.rows[4].state, "locked")
	eq(res.todo, 2); eq(res.lag, 5)
	eq(L.Evaluate(FAKE, { familyId = 99, petLevel = 1 }).family, nil, "unknown family")
	eq(L.PetopiaRank(BITE, 7), "https://www.wow-petopia.com/classic/abilities.php#bite7")
	eq(L.SiteLink(FAKE.families[2], 48), "https://everlookdb.com/pets.html?family=cat&level=48")
	eq(L.SiteLink(nil, nil), "https://everlookdb.com/pets.html")
	eq(table.concat(L.Foods(FAKE, 3), ","), "Meat,Fish")
	eq(table.concat(L.Foods(FAKE, 48), ","), "Fungus,Fruit")
end)

step("logic: alerts only for what changed", function()
	local s = { familyId = 2, petLevel = 10, petKnows = knows(set(101, 201)) }
	local res = L.Evaluate(FAKE, s)
	local news, now = L.Diff(nil, res.rows)
	eq(#news, 2, "first look: both")
	news = L.Diff(now, L.Evaluate(FAKE, s).rows)
	eq(#news, 0, "nothing changed: quiet")
	s.petLevel = 16 -- Bite rank 3 opens: tame:2 becomes tame:3
	news, now = L.Diff(now, L.Evaluate(FAKE, s).rows)
	eq(#news, 1); eq(news[1].key, "Bite"); eq(news[1].target.rank, 3)
	check(L.ChatLine(news[1]):find("Bite rank 3 is open: tame a beast", 1, true), L.ChatLine(news[1]))
	eq(L.LagText(5, 3), "Your pet is 5 levels below you")
	eq(L.LagText(1, 1), "Your pet is 1 level below you")
	eq(L.LagText(2, 3), nil); eq(L.LagText(9, 0), nil, "0 means never")
end)

step("bestiary: who teaches a rank, best for you first", function()
	local NEW = { name = "Swipe", petopia = "swipe", trainer = false, forever = true,
		ranks = { { rank = 1, level = 12, spell = 301, forever = true } } }
	local D = {
		abilities = { Bite = BITE, Swipe = NEW },
		families = { [2] = { key = "Cat", abilities = { "Bite", "Swipe" } } },
		zones = { [10] = { "Elwynn Forest", 1 }, [11] = { "Westfall", 1 }, [20] = { "Durotar", 2 } },
		beasts = {
			[1] = { 15, 16, 20, "Far Cat", { 103, 3 }, 1.5 },            -- confirmed, other continent
			[2] = { 14, 15, 11, "Near Cat", { 103, 1, 101, 2 }, 2.0 },     -- classic, same continent
			[3] = { 15, 15, 10, "Here Cat", { 103, 2, 104, 3 }, 0 },       -- seen, your zone
			[4] = { 30, 31, 10, "Big Cat", { 103, 3 }, 0 },               -- confirmed but too high for you
			[5] = { 16, 16, 10, "Zone Cat", { 103, 3 }, 0 },              -- confirmed, your zone
		},
		teachers = { [103] = { 1, 4, 5, 3, 2 }, [301] = { 3 } },
	}
	local top, all = L.Teachers(D, 103, { level = 16, zone = 10, continent = 1 }, 5)
	eq(all, 5, "all known")
	eq(top[1].name, "Zone Cat", "confirmed and in your zone first")
	eq(top[2].name, "Far Cat", "then confirmed elsewhere")
	eq(top[3].name, "Here Cat", "then seen")
	eq(top[4].name, "Near Cat", "then classic")
	eq(top[5].name, "Big Cat", "too high for you last")
	check(top[5].tooHigh, "flagged too high")
	eq(top[2].zoneName, "Durotar")
	eq(L.TeacherLine(top[3]), "Here Cat  15 · Elwynn Forest · seen in WoW Forever")
	eq(#L.Teachers(D, 103, nil, 2), 2, "at most n")
	eq(#L.Teachers(D, 999), 0, "nobody known")
	-- one beast: "Teaches" text and the weakest state it rests on
	local text, st = L.TeachesText(D, 2)
	eq(text, "Bite 1 · Bite 3"); eq(st, "classic")
	text, st = L.TeachesText(D, 5, function(ab) return ab.name:upper() end)
	eq(text, "BITE 3"); eq(st, "confirmed")
	eq(L.TeachesText(D, 99), nil, "unknown beast")
	-- a Forever-only rank that players have seen taught becomes a tame to do
	local res = L.Evaluate(D, { familyId = 2, petLevel = 16, playerLevel = 16 })
	for _, r in ipairs(res.rows) do
		if r.key == "Swipe" then eq(r.state, "tame", "forever rank with a known beast"); check(r.actionable, "actionable") end
	end
	D.teachers[301] = nil
	res = L.Evaluate(D, { familyId = 2, petLevel = 16, playerLevel = 16 })
	for _, r in ipairs(res.rows) do if r.key == "Swipe" then eq(r.state, "forever", "no beast known") end end
end)

------------------------------------------------------------------------
-- The addon in the (fake) game, with the real data
------------------------------------------------------------------------
-- Rufus, a level 10 cat: Bite 1, Claw 2, Growl 2, Cower 1 (spell ids from Data.lua)
MOCK.pet = { name = "Rufus", family = "Cat", familyId = 2, level = 10, knows = set(17253, 16828, 14916, 1742) }

local function row(key)
	for _, r in ipairs(ns.state.result.rows) do if r.key == key then return r end end
end

step("data: generated file is sane", function()
	local D = ns.Data
	check(D.families[2] and D.families[2].key == "Cat", "cat")
	eq(D.abilities.Bite.ranks[7].spell, 17260, "Bite 7")
	eq(D.abilities.Bite.ranks[7].level, 48, "Bite 7 level")
	check(D.abilities.Growl.trainer and not D.abilities.Bite.trainer, "trainer flags")
	local n = 0
	for _ in pairs(D.tameable) do n = n + 1 end
	check(n > 500, "tameable beasts: " .. n)
end)

local mark
step("login: reads the pet, one summary line in chat", function()
	mark = #MOCK.log
	MOCK.Fire("ADDON_LOADED", ADDON)
	MOCK.loggedIn = true
	MOCK.Fire("PLAYER_LOGIN")
	MOCK.Fire("PLAYER_ENTERING_WORLD")
	flush()
	check(EverlookPetsDB == ns.db and EverlookPetsCharDB == ns.cdb, "saved variables bound")
	local st = ns.state
	check(st.hunter, "hunter")
	eq(st.pet.name, "Rufus"); eq(st.pet.level, 10); eq(st.result.family.key, "Cat")
	eq(row("Bite").state, "tame"); eq(row("Bite").target.rank, 2)
	eq(row("Claw").state, "trained")
	eq(row("Growl").state, "trained")
	eq(row("Great Stamina").state, "trainer")
	eq(row("Dash").state, "locked")
	eq(st.result.todo, 3, "Bite to tame, Great Stamina and Natural Armor to buy")
	eq(st.result.lag, 10)
	local out = logSince(mark)
	check(has(out, "Rufus: 3 things to do"), "summary line: " .. table.concat(out, " / "))
	check(has(out, "Your pet is 10 levels below you"), "lag line")
	eq(ns.Alerts:Unseen(), 3, "badge")
	check(ns.Alerts:Summary():find("3 new", 1, true), ns.Alerts:Summary())
end)

step("taint guard: only our own globals written", function()
	for k in pairs(globalWrites) do check(ALLOWED[k], "wrote global " .. k) end
end)

step("no reads of globals the client doesn't have", function()
	for k in pairs(missingReads) do error("read missing global " .. k) end
end)

step("quiet when nothing changed; one line when you learn a rank", function()
	mark = #MOCK.log
	ns:Update()
	eq(#logSince(mark), 0, "no repeat")
	MOCK.hunterKnows[17255] = true -- you learned Bite 2 (from another beast)
	MOCK.Fire("SPELLS_CHANGED")
	flush()
	eq(row("Bite").state, "train")
	local out = logSince(mark)
	eq(#out, 1, "one line: " .. table.concat(out, " / "))
	check(has(out, "Rufus: Bite rank 2: you know it, teach it with Beast Training."), out[1])
end)

step("pet levels up: new ranks open, said once", function()
	MOCK.pet.knows[17255] = true -- trained Bite 2
	MOCK.pet.level = 12
	mark = #MOCK.log
	MOCK.Fire("UNIT_LEVEL", "pet")
	flush()
	local out = logSince(mark)
	-- Great Stamina and Natural Armor go from rank 1 to rank 2 at 12: two lines
	eq(#out, 2, table.concat(out, " / "))
	check(has(out, "Great Stamina rank 2 is open: buy it from a pet trainer."), out[1])
	mark = #MOCK.log
	MOCK.Fire("UNIT_LEVEL", "pet")
	flush()
	eq(#logSince(mark), 0, "said once")
end)

step("another of your pets knows a rank (from the stable)", function()
	MOCK.stabled = { { name = "Fang", familyName = "Cat", level = 20, petAbilities = { 17256 } } } -- Bite 3
	MOCK.stableActive = { { name = "Rufus", familyName = "Cat", level = 12, petAbilities = { 17253, 17255 } } }
	MOCK.pet.level = 16
	MOCK.Fire("PET_STABLE_SHOW")
	flush()
	eq(row("Bite").state, "otherpet"); eq(row("Bite").otherName, "Fang")
	-- Fang abandoned: the stable no longer lists it
	MOCK.stabled = {}
	MOCK.Fire("PET_STABLE_UPDATE")
	flush()
	eq(row("Bite").state, "tame")
end)

step("opening the window clears the badge; rows and links", function()
	check(ns.Alerts:Unseen() > 0, "something new before")
	slash("")
	check(ns.app:IsShown(), "window open")
	eq(ns.Alerts:Unseen(), 0, "seen")
	local rows = ns.Options.Rows()
	check(#rows > 5, "rows listed")
	local tip = ns.Options.RowTooltip(row("Bite"))
	-- beasts that teach Bite 3 are known, so the tooltip names them instead of linking Petopia
	check(has(tip, "Taught by"), table.concat(tip, " / "))
	check(not has(tip, "Petopia:"), table.concat(tip, " / "))
	check(has(tip, "EverlookDB: https://everlookdb.com/pets.html?family=cat&level=16"), table.concat(tip, " / "))
	ns.db.showLocked = false
	for _, r in ipairs(ns.Options.Rows()) do check(r.state ~= "locked", "locked hidden") end
	ns.db.showLocked = true
	slash("")
	check(not ns.app:IsShown(), "bare command toggles")
end)

step("chat commands: help, check, a setting, status, a typo", function()
	mark = #MOCK.log
	slash("help")
	local out = logSince(mark)
	check(has(out, "/epets check"), "help lists check")
	mark = #MOCK.log
	slash("check")
	out = logSince(mark)
	check(has(out, "Bite: Tame a beast that knows rank 3"), table.concat(out, " / "))
	slash("lag 5")
	eq(ns.db.lagWarn, 5)
	slash("minimap off")
	eq(ns.db.minimap, false)
	mark = #MOCK.log
	slash("status")
	check(has(logSince(mark), "Rufus, level 16"), "status line")
	mark = #MOCK.log
	slash("chek")
	check(has(logSince(mark), "Did you mean /epets check"), table.concat(logSince(mark), " / "))
	mark = #MOCK.log
	slash("reset")
	check(has(logSince(mark), "again within 10"), "reset asks first")
	slash("reset")
	eq(ns.db.lagWarn, 3, "reset done")
	eq(ns.db.minimap, true)
end)

step("tooltip: tameable beasts", function()
	eq(ns.NpcId("Creature-0-1-0-1-681-0000ABCDEF"), 681)
	eq(ns.NpcId("Player-1-0ABC"), nil)
	eq(ns.NpcId(nil), nil)
	local any
	for id in pairs(ns.Data.tameable) do any = id break end
	local lines = ns.TameLines(any, nil, 60)
	check(lines and lines.label == "Tameable", "tameable line")
	check(lines.learns ~= "", "family abilities")
	local cat = ns.TameLines(681, "Cat", 20) -- Young Stranglethorn Tiger, level 30-31
	if cat then
		eq(cat.value, "Cat"); eq(cat.note, "level 30-31"); eq(cat.tooHigh, 30)
		check(cat.learns:find("Bite", 1, true) and not cat.learns:find("Growl", 1, true), cat.learns)
	end
	eq(ns.TameLines(999999, nil, 60), nil, "not tameable")
	-- 505 Greater Tarantula: its tames (EG Link, BeastScout) agree on Bite 3
	local spider = ns.TameLines(505, "Spider", 20)
	check(spider and spider.teaches, "teaches line")
	check(spider.teaches:find("Bite 3", 1, true), spider.teaches)
	eq(spider.teachesFrom, "confirmed")
end)

step("Where? lists the beasts for the rank from the real data, the site only when none is known", function()
	local bite = row("Bite")
	eq(bite.state, "tame"); eq(bite.target.rank, 3)
	local lines, url = ns.Options:ShowWhere(bite)
	check(lines and #lines >= 2, "a list")
	check(lines[1]:find("Bite rank 3", 1, true), lines[1])
	check(url:find("https://everlookdb.com/npc.html?id=", 1, true), url)
	local top = ns.Logic.Teachers(ns.Data, bite.target.spell, ns.Where(), 6)
	check(strip(lines[2]):find(top[1].name, 1, true), strip(lines[2]))
	-- the mock puts you in map 1424 (Hillsbrad Foothills): its continent is known from the data
	local w = ns.Where()
	eq(w.level, MOCK.level or w.level)
	if ns.Data.zones[1424] then eq(w.zone, 1424); eq(w.continent, ns.Data.zones[1424][2]) end
	-- no beast known: the site's pet page
	local saved = ns.Data.teachers[bite.target.spell]
	ns.Data.teachers[bite.target.spell] = nil
	local none, site = ns.Options:ShowWhere(bite)
	eq(none, nil)
	check(site:find("https://everlookdb.com/pets.html", 1, true), site)
	ns.Data.teachers[bite.target.spell] = saved
	local tip = ns.Options.RowTooltip(bite)
	check(has(tip, "Taught by"), table.concat(tip, " / "))
end)

step("no pet, then not a hunter", function()
	local saved = MOCK.pet
	MOCK.pet = nil
	ns:Update()
	eq(ns.state.pet, nil)
	check(ns.Alerts:Summary():find("No pet", 1, true), ns.Alerts:Summary())
	MOCK.pet = saved
	MOCK.class = "MAGE"
	ns:Update()
	check(not ns.state.hunter, "mage")
	eq(ns.Alerts:Summary(), "Hunters only")
	MOCK.class = "HUNTER"
	ns:Update()
end)

step("after everything: still no reads of missing globals, no stray writes", function()
	for k in pairs(missingReads) do error("read missing global " .. k) end
	for k in pairs(globalWrites) do check(ALLOWED[k], "wrote global " .. k) end
end)

print(("%d passed, %d failed"):format(passes, #failures))
return #failures
