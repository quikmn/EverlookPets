-- Offline tests for Everlook Pets: the rank logic and the bestiary's search, filters, chips, "still to learn" and map
-- pins on fake data, then the whole addon loaded in TOC order against wowmock.lua with a fake hunter and pet: what it
-- shows, when it speaks up in chat, the badge, the chat commands, the tameable tooltip lines, the Bestiary and beast
-- pages, the wishlist and near alerts, "tamed by you", waypoints and the world map pins.
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
-- The bestiary browser's logic (Bestiary.lua), on fake data
------------------------------------------------------------------------
local Bst = ns.Bestiary
local CLAW = { name = "Claw", petopia = "claw", trainer = false, forever = false,
	ranks = { { rank = 1, level = 1, spell = 501 }, { rank = 2, level = 8, spell = 502 }, { rank = 3, level = 16, spell = 503 } } }
local HOWL = { name = "Furious Howl", petopia = "furioushowl", trainer = false, forever = false,
	ranks = { { rank = 1, level = 10, spell = 601 }, { rank = 2, level = 24, spell = 602 } } }
local BD = {
	foods = FAKE.foods,
	families = {
		[1] = { key = "Wolf", icon = 1, diet = 1, abilities = { "Bite", "Furious Howl", "Growl" } },
		[2] = { key = "Cat", icon = 2, diet = 3, abilities = { "Bite", "Claw", "Growl", "Dash" } },
	},
	abilities = { Bite = BITE, Claw = CLAW, Growl = GROWL, Dash = DASH, ["Furious Howl"] = HOWL },
	zones = { [10] = { "Elwynn Forest", 1 }, [11] = { "Stranglethorn Vale", 1 }, [20] = { "Durotar", 2 } },
	tameable = {
		[1] = { 2, 9, 10 }, [2] = { 2, 30, 31 }, [3] = { 1, 12, 13 }, [4] = { 2, 37, 37 }, [5] = { 1, 1, 2 }, [6] = { 2, 14, 15 },
	},
	wild = {
		[1] = { "Prowler", 0, 100, 1, { { 10, 450, 500, 470, 520 } } },
		[2] = { "Stranglethorn Tiger", 0, 101, 0, { { 11, 300, 140 } } },
		[3] = { "Gray Wolf", 0, 102, 0, { { 20, 400, 400 } } },
		[4] = { "Broken Tooth", 2, 103, 0, { { 11, 500, 500 } } },
		[5] = { "Raptor", 0, 104, 0, {} },                     -- nothing known: hidden until searched
		[6] = { "Elwynn Cat", 0, 105, 0, { { 10, 100, 100 } } },
	},
	beasts = {
		[1] = { 9, 10, 10, "Prowler", { 102, 3, 502, 2 }, 1.5 },
		[2] = { 30, 31, 11, "Stranglethorn Tiger", { 104, 1 }, 2.0 },
		[3] = { 12, 13, 20, "Gray Wolf", { 103, 3, 601, 2 }, 0 },
		[4] = { 37, 37, 11, "Broken Tooth", { 104, 3 }, 1.0 },
		[6] = { 14, 15, 10, "Elwynn Cat", { 103, 1 }, 0 },
	},
	teachers = { [102] = { 1 }, [103] = { 3, 6 }, [104] = { 4, 2 }, [502] = { 1 }, [601] = { 3 } },
	training = { [101] = 1, [102] = 4, [103] = 7, [104] = 10, [502] = 4, [503] = 7 },
}

step("bestiary: entries from the data, sorted by level", function()
	local list, by = Bst.Entries(BD)
	eq(#list, 6, "every tameable beast with a family")
	eq(list[1].name, "Raptor"); eq(list[2].name, "Prowler")
	local p = by[1]
	eq(p.famKey, "Cat"); eq(p.display, 100); eq(#p.spots, 2); eq(p.spots[1].map, 10)
	check(math.abs(p.spots[1].x - 0.45) < 1e-9 and math.abs(p.spots[1].y - 0.5) < 1e-9, "spot in 0-1")
	check(Bst.Fast(p), "1.5 s is fast"); check(not Bst.Fast(by[2]), "2.0 s isn't")
	check(by[4].rare and not by[4].elite, "rare")
	check(not by[5].known, "nothing known about the raptor")
	eq(Bst.Levels(by[2]), "30-31"); eq(Bst.Levels(by[4]), "37")
	eq(Bst.ZoneName(BD, 11), "Stranglethorn Vale")
	eq(Bst.ZoneName(BD, 11, function() return "Vallée de Strangleronce" end), "Vallée de Strangleronce")
	eq(Bst.ZoneName(BD, "Wailing Caverns"), "Wailing Caverns")
end)

step("bestiary: search words (ability rank, ability, family, zone, rare, level, name)", function()
	local p = Bst.Parse(BD, "Bite 3 cat stranglethorn")
	eq(#p.abilities, 1); eq(p.abilities[1].key, "Bite"); eq(p.abilities[1].rank, 3)
	eq(table.concat(p.words, ","), "cat,stranglethorn")
	p = Bst.Parse(BD, "furious howl 2")
	eq(p.abilities[1].key, "Furious Howl", "two-word ability"); eq(p.abilities[1].rank, 2)
	p = Bst.Parse(BD, "biss 3", function(ab) return ab.name == "Bite" and "Biss" or nil end)
	eq(p.abilities[1].key, "Bite", "the game's own name for it"); eq(p.abilities[1].rank, 3)
	p = Bst.Parse(BD, "bitey 30")
	eq(#p.abilities, 0, "not inside another word"); eq(p.levels[1], 30); eq(p.words[1], "bitey")
	local list = Bst.Entries(BD)
	local function names(f, ctx)
		local t = {}
		for _, e in ipairs((Bst.Filter(BD, list, f, ctx or {}))) do t[#t + 1] = e.name end
		return table.concat(t, ",")
	end
	eq(names({}), "Prowler,Gray Wolf,Elwynn Cat,Stranglethorn Tiger,Broken Tooth", "the unknown raptor stays out")
	eq(names({ query = "raptor" }), "Raptor", "until you search for it")
	eq(names({ query = "bite 3" }), "Gray Wolf,Elwynn Cat")
	eq(names({ query = "bite" }), "Prowler,Gray Wolf,Elwynn Cat,Stranglethorn Tiger,Broken Tooth")
	eq(names({ query = "cat" }), "Prowler,Elwynn Cat,Stranglethorn Tiger,Broken Tooth", "family, and Elwynn Cat by name")
	eq(names({ query = "strangle" }), "Stranglethorn Tiger,Broken Tooth", "zone, from a word's start")
	eq(names({ query = "rare" }), "Broken Tooth")
	eq(names({ query = "fast" }), "Prowler,Broken Tooth")
	eq(names({ query = "13" }), "Gray Wolf", "a level in its range")
	eq(names({ query = "bite 4 rare" }), "Broken Tooth")
	eq(names({ query = "tiger 31" }), "Stranglethorn Tiger")
	eq(names({ query = "nothing like it" }), "")
end)

step("bestiary: filter chips (family, zone, near your level, rare, fast, untamed, wishlist)", function()
	local list = Bst.Entries(BD)
	local function names(f, ctx)
		local t = {}
		for _, e in ipairs((Bst.Filter(BD, list, f, ctx or {}))) do t[#t + 1] = e.name end
		return table.concat(t, ",")
	end
	eq(names({ family = 1 }), "Gray Wolf")
	eq(names({ zone = 10 }), "Prowler,Elwynn Cat")
	eq(names({ zone = "here" }, { zone = 11 }), "Stranglethorn Tiger,Broken Tooth")
	eq(names({ zone = "continent" }, { continent = 2 }), "Gray Wolf")
	eq(names({ near = true }, { level = 12 }), "Prowler,Gray Wolf,Elwynn Cat", "7 to 15")
	eq(names({ rare = true }), "Broken Tooth")
	eq(names({ fast = true }), "Prowler,Broken Tooth")
	eq(names({ untamed = true }, { tamed = { [1] = 1, [3] = 2 } }), "Elwynn Cat,Stranglethorn Tiger,Broken Tooth")
	eq(names({ wish = true }, { wish = { [4] = true } }), "Broken Tooth")
	eq(names({ wish = true, query = "tiger" }, { wish = { [4] = true } }), "", "chips and words together")
	eq(names({ family = 2, near = true, query = "elwynn" }, { level = 11 }), "Prowler,Elwynn Cat")
end)

step("bestiary: rank chips against your pet", function()
	local e = Bst.Get(BD, 3) -- Gray Wolf: Bite 2 (confirmed), Furious Howl 2 (seen)
	local cat = { pet = { familyId = 2, level = 16, have = function(k) return k == "Bite" and 1 or 0 end } }
	local chips = Bst.Chips(BD, e, cat)
	eq(chips[1].text, "Bite 3"); eq(chips[1].rel, "gain"); eq(chips[1].state, "confirmed")
	eq(chips[2].text, "Furious Howl 1"); eq(chips[2].rel, "other", "cats don't howl")
	local lowCat = { pet = { familyId = 2, level = 10, have = function() return 1 end } }
	eq(Bst.Chips(BD, e, lowCat)[1].rel, "later", "rank 3 needs pet level 16")
	local strongCat = { pet = { familyId = 2, level = 40, have = function() return 4 end } }
	eq(Bst.Chips(BD, e, strongCat)[1].rel, "have")
	eq(Bst.Chips(BD, e, {})[1].rel, "other", "no pet")
	check(Bst.Teaches(BD, e, cat), "it teaches the cat something")
	local named = Bst.Chips(BD, e, { abilityName = function(ab) return ab.name:upper() end })
	eq(named[1].text, "BITE 3", "the game's names")
end)

step("your pet: still to learn, most worth it first, with the 3 nearest beasts and costs", function()
	-- a level 16 cat in Elwynn (zone 10, continent 1), Bite 1 and Claw 1; you know Claw 2
	local res = ns.Logic.Evaluate(BD, { familyId = 2, petLevel = 16, playerLevel = 16,
		petKnows = knows(set(101, 501, 201, 202, 203)), hunterKnows = knows(set(502)) })
	local items = Bst.StillToLearn(BD, res, { level = 16, zone = 10, continent = 1 }, 5)
	eq(items[1].row.key, "Claw", "you know Claw 2: train it first"); eq(items[1].kind, "train")
	eq(items[1].cost, 4); eq(items[1].net, 4 - 0, "Claw 1 has no known cost"); check(items[1].fits, "4 of 5 points")
	eq(items[2].row.key, "Bite"); eq(items[2].kind, "tame"); eq(items[2].gain, 2, "Bite 1 to 3")
	eq(items[2].cost, 7); eq(items[2].net, 6, "7 minus Bite 1's 1"); eq(items[2].fits, false, "6 is more than 5")
	-- Bite 3: Elwynn Cat (your zone, classic) before Gray Wolf (Durotar, confirmed): nearer first
	eq(items[2].beasts[1].name, "Elwynn Cat"); eq(items[2].beasts[2].name, "Gray Wolf"); eq(items[2].beastCount, 2)
	-- the Where? order still puts confirmed first
	eq(ns.Logic.Teachers(BD, 103, { level = 16, zone = 10, continent = 1 }, 3)[1].name, "Gray Wolf")
	for _, it in ipairs(items) do check(it.row.state ~= "trained" and it.row.state ~= "locked", "only what's left") end
	-- costs: none known
	eq(Bst.Cost(BD, DASH, 1, 0), nil)
	-- a tame whose beasts are all too high for you comes after one you can do
	local res2 = ns.Logic.Evaluate(BD, { familyId = 2, petLevel = 24, playerLevel = 24, petKnows = knows(set(101, 501, 502, 503, 201, 202, 203)) })
	local items2 = Bst.StillToLearn(BD, res2, { level = 24 }, nil)
	eq(items2[1].row.key, "Bite"); eq(items2[1].kind, "tamehigh", "Bite 4: the only beasts are level 30 and 37")
	eq(items2[1].fits, nil, "points unknown")
end)

step("map pins: beasts on a map that teach what your pet lacks", function()
	local res = ns.Logic.Evaluate(BD, { familyId = 2, petLevel = 16, playerLevel = 16, petKnows = knows(set(101, 501)) })
	local missing = Bst.Missing(BD, res)
	check(missing[102] and missing[103] and missing[502] and missing[503], "Bite 2-3 and Claw 2-3")
	check(not missing[104], "Bite 4 is above the pet's level"); check(not missing[202], "Growl is sold by trainers")
	local pins = Bst.PinsOn(BD, 10, missing, 16)
	eq(#pins, 3, "Prowler's two spots and Elwynn Cat's one")
	eq(pins[1].entry.name, "Prowler"); eq(#pins[1].ranks, 2)
	eq(#Bst.PinsOn(BD, 11, missing, 16), 0, "Stranglethorn's beasts teach nothing it lacks")
	eq(#Bst.PinsOn(BD, 10, Bst.Missing(BD, res, function(s) return s == 102 or s == 103 or s == 502 or s == 503 end), 16), 0,
		"ranks you know yourself are training, not a tame")
	eq(#Bst.PinsOn(BD, 10, missing, 9), 2, "at level 9 only the Prowler (9) can be tamed")
	-- the waypoint spot: nearest on your map, else on your continent, else the first
	local prowler = Bst.Get(BD, 1)
	eq(Bst.BestSpot(BD, prowler, { map = 10, x = 0.48, y = 0.53 }).x, 0.47)
	eq(Bst.BestSpot(BD, prowler, { map = 11, continent = 1 }).x, 0.45)
	eq(Bst.BestSpot(BD, Bst.Get(BD, 5), {}), nil, "no spot")
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
	eq(ns.db.minimap, "auto", "minimap back to automatic")
	check(ns.ShowMinimapButton(), "auto without Everlook Bar: shown")
	MOCK.loaded.EverlookBar = true
	check(not ns.ShowMinimapButton(), "auto with Everlook Bar: off (its plugin shows the count)")
	slash("minimap on")
	check(ns.ShowMinimapButton() and ns.db.minimap == true, "switched on by hand: shown even with Everlook Bar")
	MOCK.loaded.EverlookBar = nil
	ns.db.minimap = "auto"
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

step("bestiary page: search the real data, chips, the wishlist star and command", function()
	local Br = ns.Browser
	slash("beasts bite 3")
	check(ns.app:IsShown(), "window open")
	eq(ns.app.current, "bestiary")
	eq(Br.filter.query, "bite 3")
	local items = Br.Items()
	check(#items >= 3, "beasts that teach Bite 3: " .. #items)
	for _, e in ipairs(items) do
		local ok = false
		for _, t in ipairs(e.teaches) do if t.key == "Bite" and t.rank == 3 then ok = true end end
		check(ok, e.name .. " teaches Bite 3")
	end
	eq(Br.list.total, #items, "the cards list them")
	-- Greater Tarantula: Bite 3 confirmed, and Rufus (Bite 2, level 16) would gain it
	local spider = ns.Bestiary.Get(ns.Data, 505)
	local chips = Br.ChipList(spider, Br.Ctx())
	eq(chips[1].text, "Bite 3")
	eq(chips[1].edge, ns.app.T.ok, "confirmed: green edge")
	eq(chips[1].color[1], 1, "your pet would gain it: gold")
	check(strip(Br.Title(spider)):find("Greater Tarantula  level 19-20", 1, true), strip(Br.Title(spider)))
	check(strip(Br.Sub(spider)):find("Spider · Redridge Mountains", 1, true), strip(Br.Sub(spider)))
	-- the chips
	Br.filter.query, Br.filter.rare = "", true
	local rares = Br.Items()
	check(#rares > 5, "rare beasts: " .. #rares)
	for _, e in ipairs(rares) do check(e.rare, e.name .. " is rare") end
	Br.filter.rare, Br.filter.wish = nil, true
	eq(#Br.Items(), 0, "empty wishlist")
	ns.SetWished(505, true)
	ns.SetWished(14279, true)
	eq(#Br.Items(), 2, "two starred")
	Br.filter.wish = nil
	mark = #MOCK.log
	slash("wishlist")
	local out = logSince(mark)
	check(has(out, "Greater Tarantula, level 19-20, Redridge Mountains"), table.concat(out, " / "))
	check(has(out, "Creepthess"), table.concat(out, " / "))
	-- the star on a card
	Br.filter.query = "greater tarantula"
	Br.list:Refresh()
	local row
	for _, r in ipairs(Br.list.rows) do if r.item and r.item.id == 505 then row = r end end
	check(row, "Greater Tarantula's card")
	row.star.__scripts.OnClick(row.star)
	check(not ns.IsWished(505), "star off")
	row.star.__scripts.OnClick(row.star)
	check(ns.IsWished(505), "star on")
	Br.filter.query = ""
end)

step("beast page: facts, what it teaches with costs, waypoints (the game's and TomTom's)", function()
	local Br = ns.Browser
	check(Br.OpenBeast(505), "opens")
	eq(ns.app.current, "beast")
	local nav = ns.app.window.navButtons
	check(not nav.beast:IsShown(), "no sidebar entry of its own")
	check(nav.bestiary.bar:IsShown(), "Bestiary stays lit")
	local facts = strip(Br.Facts(Br.current))
	check(facts:find("Attack speed  2.0 s attack", 1, true), facts)
	check(facts:find("Eats  Meat", 1, true), facts)
	check(facts:find("Where  Redridge Mountains", 1, true), facts)
	check(facts:find("Tamed by you  not yet", 1, true), facts)
	check(facts:find("Wishlist  yes", 1, true), facts)
	local rows = Br.TeachRows(Br.current, Br.Ctx())
	eq(rows[1].chip.text, "Bite 3")
	eq(rows[1].cost, 7, "Bite 3 costs 7")
	eq(rows[1].net, 3, "minus Bite 2's 4")
	eq(Br.teachList.total, #rows)
	eq(Br.spotList.total, #Br.current.spots)
	-- the one filled button: Set waypoint (the game's own waypoint, super-tracked)
	MOCK.waypoint, MOCK.superTracked = nil, nil
	mark = #MOCK.log
	Br.beastButtons.buttons[1].__scripts.OnClick(Br.beastButtons.buttons[1])
	check(MOCK.waypoint and MOCK.waypoint.uiMapID == 1433, "waypoint in Redridge")
	eq(MOCK.superTracked, true)
	eq(#logSince(mark), 0, "no chat line for a waypoint: " .. table.concat(logSince(mark), " / "))
	check(ns.Browser.waypointNote and ns.Browser.waypointNote.text:find("Waypoint: Greater Tarantula, Redridge Mountains", 1, true), "the page says it")
	-- TomTom when it is loaded
	TomTom = { AddWaypoint = function(self, m, x, y, opt) MOCK.tt = { m, x, y, opt.title }; return {} end }
	local how = Br.Waypoint(Br.current, Br.current.spots[2])
	eq(how, "tomtom")
	eq(MOCK.tt[1], 1433); eq(MOCK.tt[4], "Greater Tarantula")
	TomTom = nil
	-- the wishlist button
	Br.beastButtons.buttons[2].__scripts.OnClick(Br.beastButtons.buttons[2])
	check(not ns.IsWished(505), "removed")
	eq(Br.beastButtons.buttons[2]:GetText(), "Add to wishlist")
	ns.SetWished(505, true)
	-- the site link
	Br.beastButtons.buttons[3].__scripts.OnClick(Br.beastButtons.buttons[3])
	-- the model (on) and with models off
	ns.db.models = false
	ns.app:Refresh()
	ns.db.models = true
	-- back
	ns.app:ShowSection("bestiary")
	eq(ns.app.current, "bestiary")
	check(not ns.Browser.OpenBeast(999999), "unknown beast")
end)

step("your pet page: still to learn, most worth it first, with beasts and training points", function()
	local items = ns.Options.LearnItems()
	check(#items > 0, "something to learn")
	for i = 2, #items do
		check(ns.Bestiary.LEARN_ORDER[items[i - 1].kind] <= ns.Bestiary.LEARN_ORDER[items[i].kind], "sorted by kind")
	end
	local line = strip(ns.Options.PointsLine())
	check(line:find("75 training points free", 1, true), line)
	local bite
	for _, it in ipairs(items) do if it.row.key == "Bite" then bite = it end end
	check(bite, "Bite is still to learn")
	eq(bite.row.target.rank, 3); eq(bite.cost, 7); eq(bite.net, 3); check(bite.fits, "3 of 75 points")
	check(#bite.beasts >= 1 and #bite.beasts <= 3, "up to 3 beasts")
	for _, b in ipairs(bite.beasts) do check(not b.tooHigh, b.name .. " can be tamed at 20") end
	check(strip(ns.Options.LearnTitle(bite)):find("Bite 3  your pet has 2 · 3 TP", 1, true), strip(ns.Options.LearnTitle(bite)))
	local chips = ns.Options.LearnChips(bite)
	check(#chips >= #bite.beasts, "a chip per beast")
	chips[1].onClick(chips[1])
	eq(ns.app.current, "beast", "a beast chip opens its page")
	eq(ns.Browser.current.id, bite.beasts[1].id)
	ns.app:ShowSection("pet")
	eq(ns.Options.learn.total, #items, "the cards on the pet page")
end)

step("near alert: rare and wishlisted beasts, once in 5 minutes, with a sound", function()
	MOCK.sounds = 0
	MOCK.units.nameplate1 = { guid = "Creature-0-1-0-1-14279-0000AAAA", class = "rare" }
	mark = #MOCK.log
	MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	local out = logSince(mark)
	eq(#out, 1, table.concat(out, " / "))
	check(out[1]:find("Creepthess (rare Spider, level", 1, true) and out[1]:find("on your wishlist", 1, true), out[1])
	check(not out[1]:find("/tar ", 1, true), "no /tar to retype: " .. out[1])
	check(out[1]:find("|Haddon:EverlookPets:beast:14279|h[Beast page]|h", 1, true), "a beast page link: " .. out[1])
	check(out[1]:find("Key Bindings > AddOns > Everlook Pets", 1, true), "says once how to target it with a key")
	eq(MOCK.sounds, 1, "a sound")
	eq(MOCK.lastSound, ns.Alerts.SOUND_SOFT, "a soft one by default")
	-- the key binding's secure button targets that beast
	eq(EverlookPetsTargetButton:GetAttribute("type"), "macro")
	eq(EverlookPetsTargetButton:GetAttribute("macrotext"), "/targetexact Creepthess")
	-- the links work: the beast page, a waypoint (no chat line when it is set)
	check(ns.Alerts.OnLink("addon:EverlookPets:beast:505"), "link handled")
	eq(ns.app.current, "beast"); eq(ns.Browser.current.id, 505)
	ns.app:Close()
	MOCK.waypoint = nil
	local before = #MOCK.log
	check(ns.Alerts.OnLink("addon:EverlookPets:wp:505"), "waypoint link handled")
	check(MOCK.waypoint and MOCK.waypoint.uiMapID == 1433, "waypoint set from the link")
	eq(#MOCK.log, before, "no chat line for the waypoint")
	check(not ns.Alerts.OnLink("addon:OtherAddon:wp:505"), "another addon's link is not ours")
	MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	eq(#logSince(mark), 1, "once in 5 minutes")
	-- a normal beast on your wishlist: your target
	MOCK.units.target = { guid = "Creature-0-1-0-1-505-0000BBBB", class = "normal" }
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	out = logSince(mark)
	check(has(out, "Greater Tarantula (Spider, level 19-20) is near, and it's on your wishlist"), table.concat(out, " / "))
	-- neither rare nor wished: quiet
	MOCK.units.mouseover = { guid = "Creature-0-1-0-1-1131-0000CCCC", class = "normal" }
	MOCK.Fire("UPDATE_MOUSEOVER_UNIT")
	eq(#logSince(mark), 2, "a plain wolf says nothing")
	-- a rare that isn't tameable: quiet
	MOCK.units.mouseover = { guid = "Creature-0-1-0-1-61-0000CCCC", class = "rare" }
	MOCK.Fire("UPDATE_MOUSEOVER_UNIT")
	eq(#logSince(mark), 2, "not tameable")
	-- the setting off; dead ones
	MOCK.time = MOCK.time + 400
	ns.db.wishAlert = false
	MOCK.Fire("PLAYER_TARGET_CHANGED")
	eq(#logSince(mark), 2, "wishlist alert off")
	ns.db.wishAlert = true
	MOCK.units.nameplate1.dead = true
	MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	eq(#logSince(mark), 2, "dead")
	ns.db.alertSound = false
	MOCK.units.nameplate1.dead = nil
	MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	eq(#logSince(mark), 3, "alive again")
	eq(MOCK.sounds, 2, "no sound when off")
	ns.db.alertSound = true
	-- the loud one, when picked; an alert in combat changes the target key's beast after combat
	ns.db.alertLoud = true
	MOCK.time = MOCK.time + 400
	MOCK.combat = true
	MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	eq(MOCK.lastSound, ns.Alerts.SOUND_LOUD, "raid warning when picked")
	MOCK.combat = false
	MOCK.Fire("PLAYER_REGEN_ENABLED")
	eq(EverlookPetsTargetButton:GetAttribute("macrotext"), "/targetexact Creepthess", "set after combat")
	ns.db.alertLoud = false
	-- hidden values (combat, instances): skipped, no error
	MOCK.time = MOCK.time + 400
	MOCK.units.nameplate2 = { guid = MOCK.Secret("Creature-0-1-0-1-14279-0000AAAA"), class = "rare" }
	MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
	MOCK.units.nameplate3 = { guid = "Creature-0-1-0-1-14279-0000AAAA", class = "rare", dead = MOCK.Secret(false) }
	MOCK.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
	eq(#logSince(mark), 4, "secret guid or dead state: skipped")
	for _, l in ipairs(MOCK.log) do check(not l:find("ERRORHANDLER", 1, true), l) end
	-- the line itself, too high for you
	local line = ns.Alerts.NearLine(14279, "rare", 1, false)
	check(line:find("Too high for you until level", 1, true), line)
	eq(ns.Alerts.NearLine(505, "normal", 60, false), nil, "not rare, not wished")
end)

step("tamed by you: your pet's own beast, and Tame Beast followed by a new pet", function()
	MOCK.petGUID = "Pet-0-4372-1-14-681-0200ABCDEF" -- Young Stranglethorn Tiger
	ns:Update()
	eq(ns.cdb.tamed[681], 1, "the pet you have")
	MOCK.units.target = { guid = "Creature-0-1-0-1-1131-0000DDDD" }
	MOCK.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-1", 1515)
	MOCK.petGUID = "Pet-0-4372-1-14-1131-0200ABCDEF"
	MOCK.Fire("UNIT_PET", "player")
	flush()
	eq(ns.cdb.tamed[1131], 1, "the tame")
	-- another spell, or a pet much later: not a tame
	MOCK.units.target = { guid = "Creature-0-1-0-1-505-0000EEEE" }
	MOCK.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "cast-2", 6197)
	MOCK.Fire("UNIT_PET", "player")
	eq(ns.cdb.tamed[505], nil, "Eagle Eye isn't Tame Beast")
	eq(ns.PetNpcId("Player-1-0ABC"), nil)
	-- the bestiary knows
	local Br = ns.Browser
	Br.filter.untamed = true
	for _, e in ipairs(Br.Items()) do check(e.id ~= 681 and e.id ~= 1131, "untamed only: " .. e.name) end
	Br.filter.untamed = nil
	check(strip(Br.Title(ns.Bestiary.Get(ns.Data, 681))):find("tamed by you", 1, true), "card says so")
	local lines = ns.TameLines(681, "Cat", 20)
	check(lines.tamed, "tooltip knows")
	MOCK.petGUID = nil
	ns:Update()
end)

step("world map pins: beasts that teach what your pet lacks, the switch on the map", function()
	local MP = ns.MapPins
	check(MP.provider, "a data provider on the world map")
	check(MP.switch, "the switch")
	WorldMapFrame.mapID = 1433 -- Redridge: Greater Tarantula teaches Bite 3, which Rufus lacks
	WorldMapFrame:Show()
	MP:Refresh()
	local found
	for _, pin in ipairs(WorldMapFrame.pins) do
		if pin.info.entry.id == 505 then found = pin end
		for _, t in ipairs(pin.info.ranks) do check(t.rank > 0, "a rank") end
		check(pin.info.entry.lo <= ns.state.playerLevel, pin.info.entry.name .. " can be tamed")
	end
	check(found, "Greater Tarantula pinned (" .. #WorldMapFrame.pins .. " pins)")
	check(found.normalizedX > 0 and found.normalizedX < 1, "placed on the map")
	found:OnMouseEnter()
	check(has(MOCK.tip, "Bite 3"), table.concat(MOCK.tip, " / "))
	found.__scripts.OnMouseUp(found, "LeftButton")
	eq(ns.Browser.current.id, 505, "a click opens its page")
	-- Elwynn's map has no Bite 3 teacher Rufus can use? Whatever it has, every pin teaches something missing
	MP.switch.__scripts.OnClick(MP.switch)
	eq(ns.db.mapPins, false)
	eq(#WorldMapFrame.pins, 0, "off: no pins")
	eq(MP.switch:GetText(), "Tameable beasts: off")
	MP.switch.__scripts.OnClick(MP.switch)
	check(#WorldMapFrame.pins > 0, "on again")
	check(MP:Status():find("ready", 1, true), MP:Status())
	WorldMapFrame:Hide()
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
