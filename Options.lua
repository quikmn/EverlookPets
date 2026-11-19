-- Everlook Pets: the window (/epets), its settings (also from chat) and the chat commands.
-- Pages: "Your pet" (status, what it can still learn best first, every ability with what to do next), "Bestiary"
-- and the beast page (Browser.lua), "Settings", "Data and links".
local ADDON, ns = ...
local UI = ns.UI
local Logic = ns.Logic
local O = {}
ns.Options = O

local app = UI:NewApp({
	name = ns.NAME,
	addon = ADDON,
	slash = ns.SLASH,
	aliases = { "/everlookpets" },
	feedbackURL = "https://everlookdb.com/everlook-pets.html#feedback",
	frameName = ns.PREFIX,
	tagline = "Your hunter pet's abilities: what it has, what its level allows, and how to get the next rank.",
	position = function() return ns.db end,
	onShow = function() ns:Update(); ns.Alerts:MarkSeen(); ns.Browser.LightBestiary() end,
})
ns.app = app
local T = app.T

local function hexOf(c) return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
local COLORS = {
	train = hexOf(T.ok), trainer = "|cffffd200", otherpet = "|cffffd200", tame = "|cffffd200",
	forever = hexOf(T.accent), trained = hexOf(T.text), locked = hexOf(T.muted),
}

------------------------------------------------------------------------
-- Settings (window and chat)
------------------------------------------------------------------------
app:Setting({ key = "chat", type = "bool", label = "Tell me in chat when something becomes actionable",
	desc = "One line when a new rank opens for your pet or you learned a rank it lacks; once per change.",
	keywords = { "alert", "announce", "message", "notify" },
	get = function() return ns.db.chat end, set = function(v) ns.db.chat = v end })
app:Setting({ key = "lag", type = "number", label = "Note when my pet is this many levels below me (0 = never)", min = 0, max = 10,
	keywords = { "behind", "level", "lag", "catch up" },
	get = function() return ns.db.lagWarn end, set = function(v) ns.db.lagWarn = v end,
	after = function() ns:Update() end })
app:Setting({ key = "minimap", type = "bool", label = "Minimap button (with a count of what's new)",
	keywords = { "icon", "badge", "button" },
	get = function() return ns.db.minimap end, set = function(v) ns.db.minimap = v end,
	after = function() ns.Alerts:Draw() end })
app:Setting({ key = "tooltip", type = "bool", label = "Show \"Tameable\" on wild beasts' tooltips",
	desc = "The beast's family, its level and what its family learns.",
	keywords = { "tame", "beast", "mouseover" },
	get = function() return ns.db.tooltip end, set = function(v) ns.db.tooltip = v end })
app:Setting({ key = "rare", type = "bool", label = "Tell me when a rare tameable beast is near",
	desc = "One chat line (once in 5 minutes per beast) when its nameplate, your target or your mouse-over shows it. Turn on enemy nameplates to hear about it from afar.",
	keywords = { "rare", "alert", "nameplate", "spawn", "camp" },
	get = function() return ns.db.rareAlert end, set = function(v) ns.db.rareAlert = v end })
app:Setting({ key = "wish", type = "bool", label = "Tell me when a beast on my wishlist is near",
	desc = "Star beasts on the Bestiary page; you hear about them the same way as rare ones.",
	keywords = { "wishlist", "star", "favorite", "alert" },
	get = function() return ns.db.wishAlert end, set = function(v) ns.db.wishAlert = v end })
app:Setting({ key = "sound", type = "bool", label = "Play a sound with those lines",
	keywords = { "sound", "audio", "warning" },
	get = function() return ns.db.alertSound end, set = function(v) ns.db.alertSound = v end })
app:Setting({ key = "models", type = "bool", label = "3D model on the beast page",
	desc = "Off saves a little memory and time when you open a beast's page.",
	keywords = { "model", "3d", "performance", "picture" },
	get = function() return ns.db.models end, set = function(v) ns.db.models = v end })
app:Setting({ key = "map", type = "bool", label = "Tameable beasts on the world map",
	desc = "Pins for beasts that teach a rank your pet lacks and that you can tame at your level; the edge colour says how sure the rank is. The world map has the same switch.",
	keywords = { "map", "pins", "world map", "spawn", "where" },
	get = function() return ns.db.mapPins end, set = function(v) ns.db.mapPins = v end,
	after = function() if ns.MapPins then ns.MapPins:Refresh() end end })
app:Setting({ key = "locked", type = "bool", label = "List abilities that open at a higher pet level",
	keywords = { "later", "future", "hide" },
	get = function() return ns.db.showLocked end, set = function(v) ns.db.showLocked = v end,
	after = function() app:Refresh() end })

------------------------------------------------------------------------
-- Links (an addon can't open a browser: a window with the address to copy)
------------------------------------------------------------------------
local linkWin
function O:ShowLink(intro, url)
	if not linkWin then linkWin = UI.LinkWindow(ns.PREFIX .. "LinkWindow", T, intro, url) end
	linkWin:SetLink(intro .. "\nPress Ctrl+C to copy, then paste it in your browser.", url)
	linkWin:SetHeight(132)
	linkWin.box:ClearAllPoints()
	linkWin.box:SetPoint("TOP", 0, -54)
	linkWin:Hide()
	linkWin:Show()
end

local function siteURL()
	local st = ns.state
	local fam = st.result and st.result.family
	return Logic.SiteLink(fam, st.pet and st.pet.level)
end

------------------------------------------------------------------------
-- Page: your pet
------------------------------------------------------------------------
local HAPPY = { "Unhappy", "Content", "Happy" }

local function petLine(f) return function() local p = ns.state.pet; return p and f(p) or "-" end end

-- The rows the ability list shows.
function O.Rows()
	local res = ns.state.result
	local out = {}
	for _, row in ipairs(res and res.rows or {}) do
		if ns.db.showLocked or row.state ~= "locked" then out[#out + 1] = row end
	end
	return out
end

function O.RowTitle(row)
	return row.name .. (row.haveRank > 0 and ("  |cff8d94a3rank " .. row.haveRank .. "|r") or "")
end

function O.RowDetail(row)
	local status = Logic.Describe(row)
	return (COLORS[row.state] or "") .. status .. "|r"
end

function O.RowTooltip(row)
	local status, how = Logic.Describe(row)
	local lines = { row.name, status, how }
	local fam = ns.state.result and ns.state.result.family
	if row.next then lines[#lines + 1] = ("Next: rank %d at pet level %d."):format(row.next.rank, row.next.level) end
	if row.state == "tame" or row.state == "forever" then
		local top, all = Logic.Teachers(ns.Data, row.target.spell, ns.Where(), 3)
		if #top > 0 then
			lines[#lines + 1] = ("Taught by (%d known; Where? for more):"):format(all)
			for _, t in ipairs(top) do lines[#lines + 1] = "  " .. Logic.TeacherLine(t) end
		elseif row.state == "tame" then
			lines[#lines + 1] = "Petopia: " .. Logic.PetopiaRank(row.ability, row.target.rank)
		end
		lines[#lines + 1] = "EverlookDB: " .. Logic.SiteLink(fam, row.target.level)
	end
	return lines
end

-- Where?: the best beasts for the rank, near your level and where you are; the site's link when none is known.
-- Returns what it showed (for the tests): the lines and the link.
function O:ShowWhere(row)
	local t = row.target
	local top, all = Logic.Teachers(ns.Data, t.spell, ns.Where(), 6)
	if #top == 0 then
		local url = Logic.SiteLink(ns.state.result and ns.state.result.family, t.level)
		self:ShowLink(("No beast known yet for %s rank %d. EverlookDB's pet page has the latest."):format(row.name, t.rank), url)
		return nil, url
	end
	local lines = { ("|cffffd100%s rank %d|r: %d beast%s known, best for you first"):format(row.name, t.rank, all, all == 1 and "" or "s") }
	for _, b in ipairs(top) do
		local c = b.state == "confirmed" and "|cff62cf88" or b.state == "seen" and "|cffffffff" or "|cff8d94a3"
		lines[#lines + 1] = c .. Logic.TeacherLine(b) .. "|r" .. (b.tooHigh and ("  |cffef5d5d(level " .. b.lo .. "+)|r") or "")
	end
	lines[#lines + 1] = "The first one's EverlookDB page (map and spawns):"
	local url = Logic.NPC_URL .. top[1].id
	self:ShowLink(table.concat(lines, "\n"), url)
	-- the link window is sized for one line: make room for the list
	if linkWin then
		linkWin:SetHeight(110 + 14 * #lines)
		linkWin.box:ClearAllPoints()
		linkWin.box:SetPoint("BOTTOM", 0, 50)
	end
	return lines, url
end

------------------------------------------------------------------------
-- Your pet: what it can still learn (Bestiary.lua sorts it)
------------------------------------------------------------------------
function O.FreePoints()
	local p = ns.state.pet
	if not (p and p.tpTotal) then return nil end
	return p.tpTotal - (p.tpUsed or 0)
end

function O.LearnItems()
	return ns.Bestiary.StillToLearn(ns.Data, ns.state.result, ns.Where(), O.FreePoints())
end

-- "75 training points free. Next: Bite 4 costs 10 (3 for your pet, which has rank 3)."
function O.PointsLine()
	local st = ns.state
	if not (st.pet and st.result and st.result.family) then return "" end
	local free = O.FreePoints()
	local s = free and (("%d training point%s free."):format(free, free == 1 and "" or "s")) or "Training points: not known."
	for _, it in ipairs(O.LearnItems()) do
		if it.cost then
			s = s .. (" Next: %s %d costs %d"):format(it.row.name, it.row.target.rank, it.cost)
			if it.net and it.net ~= it.cost then s = s .. (" (%d for your pet, which has rank %d)"):format(it.net, it.row.haveRank) end
			if it.fits == false then s = s .. ", |cffef5d5dmore than you have|r" end
			return s .. "."
		end
	end
	return s .. " What these ranks cost isn't known yet."
end

function O.LearnTitle(it)
	local row = it.row
	local s = ("%s %d"):format(row.name, row.target.rank)
	s = s .. "  |cff8d94a3" .. (row.haveRank > 0 and ("your pet has " .. row.haveRank) or "new for your pet")
	if it.cost then s = s .. " · " .. (it.net or it.cost) .. " TP" end
	s = s .. "|r"
	if it.fits == false then s = s .. "  |cffef5d5d(not enough points)|r" end
	return s
end

function O.LearnSub(it)
	local s = (COLORS[it.row.state] or "") .. (Logic.Describe(it.row)) .. "|r"
	if it.row.state == "tame" and (it.beastCount or 0) == 0 then s = s .. "  |cff8d94a3(no beast known yet)|r" end
	return s
end

function O.LearnChips(it)
	local out = {}
	for _, b in ipairs(it.beasts or {}) do
		local edge = (b.state == "confirmed" and T.ok) or (b.state == "seen" and T.text) or T.border
		local lv = b.lo > 0 and (b.hi > b.lo and (b.lo .. "-" .. b.hi) or tostring(b.lo)) or "?"
		local zone = b.zone and b.zone ~= 0 and ns.Bestiary.ZoneName(ns.Data, b.zone, ns.MapName) or nil
		out[#out + 1] = { text = b.name .. " " .. lv .. (zone and (" · " .. zone) or ""), edge = edge,
			color = b.tooHigh and T.danger or T.text,
			tip = { b.name, Logic.TeacherLine(b), b.tooHigh and ("Too high for you until level " .. b.lo) or "Click for its page." },
			onClick = function() ns.Browser.OpenBeast(b.id) end }
	end
	if it.beastCount and it.beastCount > #out then
		out[#out + 1] = { text = ("+%d more"):format(it.beastCount - #out), color = T.muted, edge = T.border,
			tip = { "Every beast that teaches it", "Opens the Bestiary with this rank searched." },
			onClick = function() ns.Browser.OpenSearch(it.row.name .. " " .. it.row.target.rank) end }
	end
	return out
end

app:Section("pet", "Your pet", function(stack)
	UI.Header(stack, "Your pet")
	UI.Note(stack, function()
		local st = ns.state
		if not st.hunter then return "Everlook Pets is for hunters: log in on a hunter to see your pet." end
		if not st.pet then return "No pet out. Call your pet to see its abilities." end
		if not (st.result and st.result.family) then return "This pet's family isn't in our data." end
		local lag = Logic.LagText(st.result.lag, ns.db.lagWarn)
		if lag then return "|cffff9f40" .. lag .. ".|r Pets learn faster from kills near their own level." end
		return "Pets can't be above your level; a pet that keeps up learns its new ranks as you level."
	end)
	UI.Stat(stack, "Name and family", petLine(function(p) return (p.name or "?") .. "  |cff8d94a3" .. (p.familyName or "") .. "|r" end))
	UI.Stat(stack, "Level", function()
		local st = ns.state
		if not st.pet then return "-" end
		return (st.pet.level or "?") .. "  |cff8d94a3(you: " .. (st.playerLevel or "?") .. ")|r"
	end)
	UI.Stat(stack, "Loyalty", petLine(function(p)
		local s = p.loyalty or "-"
		if p.loyaltyRate and p.loyaltyRate > 0 then s = s .. "  |cff62cf88(gaining)|r" elseif p.loyaltyRate and p.loyaltyRate < 0 then s = s .. "  |cffef5d5d(losing)|r" end
		return s
	end))
	UI.Stat(stack, "Training points", petLine(function(p)
		if not p.tpTotal then return "-" end
		return (p.tpTotal - (p.tpUsed or 0)) .. " free  |cff8d94a3(" .. (p.tpUsed or 0) .. " of " .. p.tpTotal .. " used)|r"
	end))
	UI.Stat(stack, "Happiness", petLine(function(p)
		local s = HAPPY[p.happiness or 0] or "-"
		if p.damagePct then s = s .. "  |cff8d94a3(" .. p.damagePct .. "% damage)|r" end
		return s
	end))
	UI.Stat(stack, "Eats", petLine(function(p)
		if p.foods and #p.foods > 0 then return table.concat(p.foods, ", ") end
		local fam = ns.Data.families[p.familyId or 0]
		return fam and table.concat(Logic.Foods(ns.Data, fam.diet), ", ") or "-"
	end))
	-- the page's one filled button
	UI.ButtonRow(stack, {
		{ label = "This family on EverlookDB", width = 200, style = "accent",
			desc = "The site's pet page for your pet's family at its level: every rank, and beasts to tame near that level.",
			keywords = { "site", "link", "web" },
			onClick = function() O:ShowLink("EverlookDB: this family's abilities and beasts to tame.", siteURL()) end },
		{ label = "Petopia", width = 110,
			desc = "Petopia's page for your pet's family: which beasts know which ranks.",
			onClick = function()
				local fam = ns.state.result and ns.state.result.family
				O:ShowLink("Petopia: this family's beasts and the ranks they know.", fam and Logic.PetopiaFamily(fam) or Logic.PETOPIA)
			end },
	})

	UI.Header(stack, "Still to learn", "Most worth it first: what you can do right now, then the biggest jump in rank, then the fewest "
		.. "training points. For a tame, the 3 nearest beasts you can tame (confirmed first); click one for its page.")
	UI.Note(stack, O.PointsLine)
	O.learn = ns.Cards(stack, {
		items = O.LearnItems,
		icon = function(it) return ns.AbilityIcon(it.row.ability, it.row.target) end,
		title = O.LearnTitle,
		sub = O.LearnSub,
		chips = O.LearnChips,
		tooltip = function(it) return O.RowTooltip(it.row) end,
		onClick = function(it) ns.Browser.OpenSearch(it.row.name .. " " .. it.row.target.rank) end,
		buttons = {
			{ label = "Where?", width = 70, shown = function(it) return it.row.state == "tame" or it.row.state == "forever" end,
				onClick = function(it) O:ShowWhere(it.row) end },
		},
		empty = function()
			local st = ns.state
			if not (st.pet and st.result and st.result.family) then return "Call your pet to see what it can still learn." end
			return "Nothing: every ability is as good as your pet's level allows."
		end,
		page = 30,
	})

	UI.Header(stack, "Every ability", "What your pet has, the best rank its level allows, and how to get it. Things to do come first; hover a row for more.")
	O.list = UI.List(stack, {
		rowHeight = 44,
		items = O.Rows,
		icon = function(row) return ns.AbilityIcon(row.ability, row.have or row.target or row.best) end,
		title = O.RowTitle,
		detail = O.RowDetail,
		tooltip = O.RowTooltip,
		empty = "Nothing to show yet.",
		buttons = {
			{ label = "Where?", width = 70, shown = function(row) return row.state == "tame" or row.state == "forever" end,
				onClick = function(row) O:ShowWhere(row) end },
		},
	})
end)

------------------------------------------------------------------------
-- Page: bestiary (Browser.lua)
------------------------------------------------------------------------
ns.Browser.AddBestiary(app)

------------------------------------------------------------------------
-- Page: settings
------------------------------------------------------------------------
app:Section("settings", "Settings", function(stack)
	UI.Header(stack, "Alerts")
	app:Widget(stack, "chat")
	app:Widget(stack, "lag")
	app:Widget(stack, "minimap")
	UI.Header(stack, "Beasts near you")
	app:Widget(stack, "rare")
	app:Widget(stack, "wish")
	app:Widget(stack, "sound")
	UI.Header(stack, "Window, map and tooltips")
	app:Widget(stack, "locked")
	app:Widget(stack, "models")
	app:Widget(stack, "map")
	app:Widget(stack, "tooltip")
	UI.Header(stack, "Chat commands")
	UI.Note(stack, ns.SLASH .. "  this window\n" .. ns.SLASH .. " check  what to do now, in chat\n" .. ns.SLASH
		.. " chat off, lag 5, minimap off, tooltip off  change a setting\n" .. ns.SLASH .. " get  every setting\n"
		.. ns.SLASH .. " beasts <words>  the Bestiary with that search (bite 6, cat, rare)\n" .. ns.SLASH .. " wishlist  your starred beasts\n"
		.. ns.SLASH .. " search <words>  find a setting\n" .. ns.SLASH .. " status, version, help")
end)

------------------------------------------------------------------------
-- Page: data and links
------------------------------------------------------------------------
app:Section("data", "Data and links", function(stack)
	UI.Header(stack, "Where the data comes from")
	UI.Note(stack, "Families, diets, abilities and the pet level each rank needs: EverlookDB's pet data, from the WoW Forever "
		.. "game files (build " .. (ns.Data.build or "?") .. "). Tameable beasts: EverlookDB (the game's tameable flag, classic-db levels).")
	UI.Note(stack, "Which beast teaches which rank: EverlookDB's bestiary. It comes from hunters' tames in WoW Forever (EG Link by "
		.. "Efficient Games, Forever Hunter Pets, BeastScout) and, where nobody has reported a beast yet, classic data (VMaNGOS). "
		.. "Each rank says how sure it is: |cff62cf88confirmed|r (two sources agree, or several tames), seen in WoW Forever "
		.. "(one source), or |cff8d94a3classic data|r (WoW Forever may differ). The game files WoW Forever ships don't have it.")
	UI.Note(stack, "Where beasts spawn: where WoW Forever players found them (Forever Hunter Pets, MIT), else classic-db's "
		.. "spawn points (Classic 1.12, GPL-3.0). Models, names, levels and rare or elite: the game's data on EverlookDB. Training "
		.. "point costs: Beast Training as Forever Hunter Pets (MIT) and EG Link players (CC BY 4.0) read it. Tamed by you "
		.. "and your wishlist stay on your computer, per character.")
	UI.CopyBox(stack, "EverlookDB pets", function() return siteURL() end)
	UI.CopyBox(stack, "Petopia abilities", Logic.PETOPIA .. "abilities.php")
end)

------------------------------------------------------------------------
-- Chat commands
------------------------------------------------------------------------
app:Command("check", "check", "what to do for your pet now, in chat", function()
	local st = ns.state
	if not st.hunter then ns:Print("for hunters only.") return end
	if not st.pet then ns:Print("no pet out.") return end
	local res = st.result
	local n = 0
	for _, row in ipairs(res and res.rows or {}) do
		if row.actionable then n = n + 1; ns:Print(row.name .. ": " .. Logic.Describe(row)) end
	end
	if n == 0 then ns:Print((st.pet.name or "Your pet") .. ": nothing to do, every ability is as good as its level allows.") end
	local lag = res and Logic.LagText(res.lag, ns.db.lagWarn)
	if lag then ns:Print(lag .. ".") end
end, { "todo" })

app:Command("beasts", "beasts [words]", "the Bestiary, with a search (bite 6, cat, stranglethorn, rare)", function(rest)
	ns.Browser.OpenSearch(tostring(rest or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end, { "bestiary", "find" })

app:Command("wishlist", "wishlist", "the beasts you starred, in chat", function()
	local list = {}
	for id in pairs(ns.cdb and ns.cdb.wishlist or {}) do
		local e = ns.Bestiary.Get(ns.Data, id)
		if e then list[#list + 1] = e end
	end
	table.sort(list, function(a, b) return a.lo < b.lo end)
	if #list == 0 then ns:Print("your wishlist is empty: star beasts on the Bestiary page (" .. ns.SLASH .. " beasts).") return end
	for _, e in ipairs(list) do
		ns:Print(("%s, level %s, %s"):format(e.name, ns.Bestiary.Levels(e), ns.Bestiary.ZoneName(ns.Data, e.zones[1] or "where not known", ns.MapName)))
	end
end, { "wish" })

app:StatusLines(function()
	local st = ns.state
	if not st.hunter then return { "Not a hunter: nothing to track." } end
	if not st.pet then return { "No pet out.", ns.MapPins:Status() } end
	return { ("%s, level %s: %d thing%s to do."):format(st.pet.name or "Pet", st.pet.level or "?", st.result and st.result.todo or 0,
		(st.result and st.result.todo or 0) == 1 and "" or "s"), ns.MapPins:Status() }
end)

app:Reset(nil, "every " .. ns.NAME .. " setting", function()
	for k in pairs(ns.db) do ns.db[k] = nil end
	for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
	ns.Alerts:Draw()
	app:Refresh()
end)

------------------------------------------------------------------------
-- Page: one beast (Browser.lua), last: it has no sidebar entry
------------------------------------------------------------------------
ns.Browser.AddBeast(app)

-- Runs once the saved settings are loaded (Core.lua, ADDON_LOADED).
function ns.OnLoaded()
	app:RegisterSlash(ns.SLASH_ID)
	ns.Alerts:SetupBroker()
end
