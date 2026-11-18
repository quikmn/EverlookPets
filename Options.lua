-- Everlook Pets: the window (/epets), its settings (also from chat) and the chat commands.
-- Pages: "Your pet" (status and every ability with what to do next), "Settings", "Data and links".
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
	onShow = function() ns:Update(); ns.Alerts:MarkSeen() end,
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
	if row.state == "tame" then
		lines[#lines + 1] = "Petopia: " .. Logic.PetopiaRank(row.ability, row.target.rank)
		lines[#lines + 1] = "EverlookDB: " .. Logic.SiteLink(fam, row.target.level)
	elseif row.state == "forever" then
		lines[#lines + 1] = "EverlookDB: " .. Logic.SiteLink(fam, row.target.level)
	end
	return lines
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

	UI.Header(stack, "Abilities", "What your pet has, the best rank its level allows, and how to get it. Things to do come first; hover a row for more.")
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
				onClick = function(row)
					if row.state == "tame" then
						O:ShowLink(("Petopia: beasts that know %s rank %d."):format(row.name, row.target.rank), Logic.PetopiaRank(row.ability, row.target.rank))
					else
						O:ShowLink(("EverlookDB: %s."):format(row.name), Logic.SiteLink(ns.state.result.family, row.target.level))
					end
				end },
		},
	})
end)

------------------------------------------------------------------------
-- Page: settings
------------------------------------------------------------------------
app:Section("settings", "Settings", function(stack)
	UI.Header(stack, "Alerts")
	app:Widget(stack, "chat")
	app:Widget(stack, "lag")
	app:Widget(stack, "minimap")
	UI.Header(stack, "Window and tooltips")
	app:Widget(stack, "locked")
	app:Widget(stack, "tooltip")
	UI.Header(stack, "Chat commands")
	UI.Note(stack, ns.SLASH .. "  this window\n" .. ns.SLASH .. " check  what to do now, in chat\n" .. ns.SLASH
		.. " chat off, lag 5, minimap off, tooltip off  change a setting\n" .. ns.SLASH .. " get  every setting\n"
		.. ns.SLASH .. " search <words>  find a setting\n" .. ns.SLASH .. " status, version, help")
end)

------------------------------------------------------------------------
-- Page: data and links
------------------------------------------------------------------------
app:Section("data", "Data and links", function(stack)
	UI.Header(stack, "Where the data comes from")
	UI.Note(stack, "Families, diets, abilities and the pet level each rank needs: EverlookDB's pet data, from the WoW Forever "
		.. "game files (build " .. (ns.Data.build or "?") .. "). Tameable beasts: EverlookDB (the game's tameable flag, classic-db levels).")
	UI.Note(stack, "Which beast knows which rank is not in the game files WoW Forever ships, so Everlook Pets doesn't guess. "
		.. "Petopia, the long-running hunter pet site, lists the beasts for every rank; EverlookDB's pet page lists beasts "
		.. "to tame near a level.")
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

app:StatusLines(function()
	local st = ns.state
	if not st.hunter then return { "Not a hunter: nothing to track." } end
	if not st.pet then return { "No pet out." } end
	return { ("%s, level %s: %d thing%s to do."):format(st.pet.name or "Pet", st.pet.level or "?", st.result and st.result.todo or 0,
		(st.result and st.result.todo or 0) == 1 and "" or "s") }
end)

app:Reset(nil, "every " .. ns.NAME .. " setting", function()
	for k in pairs(ns.db) do ns.db[k] = nil end
	for k, v in pairs(ns.DEFAULTS) do ns.db[k] = v end
	ns.Alerts:Draw()
	app:Refresh()
end)

-- Runs once the saved settings are loaded (Core.lua, ADDON_LOADED).
function ns.OnLoaded()
	app:RegisterSlash(ns.SLASH_ID)
	ns.Alerts:SetupBroker()
end
