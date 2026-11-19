-- Everlook Pets: the Bestiary page (search, filter chips, a card per beast with a wishlist star) and the beast page
-- (model, levels, what it teaches, attack speed, diet, where it spawns, "Set waypoint"). Options.lua registers
-- both pages on the window: ns.Browser.AddBestiary(app) after "Your pet", ns.Browser.AddBeast(app) last (the beast
-- page has no sidebar entry: it opens from a card, and "Bestiary" stays lit in the sidebar).
local _, ns = ...
local UI = ns.UI
local U = UI.Util
local B = ns.Bestiary
local Logic = ns.Logic
local Br = {}
ns.Browser = Br

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end
local function hexOf(c) return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5)) end
local MUTED, GOLD, GREEN, RED = "|cff8d94a3", "|cffffd200", "|cff62cf88", "|cffef5d5d"

-- the filter chips' state (this session)
Br.filter = { query = "" }
-- the beast the beast page shows (an entry of B.Entries)
Br.current = nil

------------------------------------------------------------------------
-- The context every bestiary function takes: you, your pet, your lists, the game's names
------------------------------------------------------------------------
function Br.Ctx()
	local st = ns.state
	local w = ns.Where()
	local ctx = {
		level = st.playerLevel or w.level, zone = w.zone, continent = w.continent,
		tamed = ns.cdb and ns.cdb.tamed or {}, wish = ns.cdb and ns.cdb.wishlist or {},
		mapName = ns.MapName, familyName = ns.FamilyName, abilityName = ns.AbilityName,
	}
	local res, p = st.result, st.pet
	if res and res.family and p then
		local have = {}
		for _, row in ipairs(res.rows) do have[row.key] = row.haveRank or 0 end
		ctx.pet = { familyId = p.familyId, level = p.level, have = function(key) return have[key] or 0 end }
	end
	return ctx
end

-- The beasts the Bestiary page lists now. The context is kept for the cards drawn right after (Br.CardCtx).
function Br.Items()
	Br.ctx = Br.Ctx()
	return (B.Filter(ns.Data, (B.Entries(ns.Data)), Br.filter, Br.ctx))
end
function Br.CardCtx() return Br.ctx or Br.Ctx() end

------------------------------------------------------------------------
-- How a beast reads
------------------------------------------------------------------------
local T -- the window theme, set when the pages are added

-- Chip colours: the text says what it means for your pet, the edge how sure the rank is.
function Br.ChipColors(c)
	local color = (c.rel == "gain" and { 1, 0.82, 0 }) or (c.rel == "later" and T.text) or T.muted
	local edge = (c.state == "confirmed" and T.ok) or (c.state == "seen" and T.text) or T.border
	return color, edge
end

local REL_TEXT = {
	gain = "your pet would gain it",
	later = "a higher rank than your pet's, once its level allows",
	have = "your pet has it (or better)",
	other = "your pet's family can't learn it",
}

function Br.ChipList(e, ctx)
	local out = {}
	for _, c in ipairs(B.Chips(ns.Data, e, ctx)) do
		local color, edge = Br.ChipColors(c)
		out[#out + 1] = { text = c.text, color = color, edge = edge,
			tip = { c.text, Logic.STATE_LABEL[c.state] or c.state, ctx.pet and REL_TEXT[c.rel] or nil } }
	end
	if #out == 0 then out[1] = { text = "teaches: not reported yet", color = T.muted, edge = T.border } end
	return out
end

local function zoneNames(e, max)
	local t = {}
	for i, z in ipairs(e.zones) do
		if max and i > max then t[#t + 1] = ("+%d"):format(#e.zones - max) break end
		t[#t + 1] = B.ZoneName(ns.Data, z, ns.MapName)
	end
	return #t > 0 and table.concat(t, ", ") or "where: not known yet"
end

function Br.SpeedText(e)
	if not e.speed or e.speed <= 0 then return nil end
	local s = ("%.1f s attack"):format(e.speed)
	if B.Fast(e) then return GREEN .. s .. " (fast)|r" end
	if e.speed > B.FAST then return s .. " (slow)" end
	return s
end

function Br.Title(e)
	local s = e.name .. "  " .. MUTED .. "level " .. B.Levels(e)
	local tag = B.RANK_WORD[e.rank]
	if tag then s = s .. " · |r" .. GOLD .. tag .. "|r" else s = s .. "|r" end
	local st = ns.state
	if st.playerLevel and e.lo > st.playerLevel then s = s .. "  " .. RED .. "(level " .. e.lo .. "+)|r" end
	if ns.cdb and ns.cdb.tamed[e.id] then s = s .. "  " .. GREEN .. "tamed by you|r" end
	return s
end

function Br.Sub(e)
	local parts = { ns.FamilyName(e.family) or e.famKey, zoneNames(e, 2) }
	local sp = Br.SpeedText(e)
	if sp then parts[#parts + 1] = sp end
	return table.concat(parts, " · ")
end

function Br.Tooltip(e, ctx)
	local lines = { e.name, (ns.FamilyName(e.family) or e.famKey) .. ", level " .. B.Levels(e) .. (B.RANK_WORD[e.rank] and (", " .. B.RANK_WORD[e.rank]) or ""),
		"Where: " .. zoneNames(e) }
	local sp = Br.SpeedText(e)
	if sp then lines[#lines + 1] = "Attack speed: " .. sp end
	local chips = B.Chips(ns.Data, e, ctx)
	if #chips > 0 then
		lines[#lines + 1] = "Teaches when tamed:"
		for _, c in ipairs(chips) do
			local color = Br.ChipColors(c)
			lines[#lines + 1] = "  " .. hexOf(color) .. c.text .. "|r  " .. MUTED .. (Logic.STATE_LABEL[c.state] or c.state) .. "|r"
		end
	else
		lines[#lines + 1] = "What it teaches isn't reported yet."
	end
	lines[#lines + 1] = MUTED .. "Click for its page; the star adds it to your wishlist.|r"
	return lines
end

------------------------------------------------------------------------
-- Opening things
------------------------------------------------------------------------
local app

-- "Bestiary" stays lit in the sidebar while a beast's page shows.
local function lightBestiary()
	local nav = app and app.window and app.window.navButtons
	if not nav then return end
	if nav.beast then nav.beast:Hide() end
	local b = nav.bestiary
	if b and app.current == "beast" then
		b.bg:Show(); b.bar:Show(); b.text:SetTextColor(rgba(T.text))
	end
end
Br.LightBestiary = lightBestiary

function Br.OpenBeast(id)
	local e = type(id) == "table" and id or B.Get(ns.Data, id)
	if not e then return false end
	Br.current = e
	app:Open("beast")
	lightBestiary()
	-- a new beast starts at the top of its page
	local s = app.sections.beast
	if s and s.scroll and s.scroll.SetScroll then s.scroll.SetScroll(0) end
	return true
end

-- The Bestiary page, with the search filled in (nil keeps the search as it is).
function Br.OpenSearch(text)
	if text then
		Br.filter.query = text
		if Br.searchBox then Br.searchBox:SetText(text) end
		if Br.list then Br.list:ResetPage() end
	end
	app:Open("bestiary")
end

-- A waypoint to the beast's best spot (nearest on your map, else on your continent). Returns what was set.
function Br.Waypoint(e, spot)
	spot = spot or B.BestSpot(ns.Data, e, ns.Here())
	if not spot then ns:Print("no spawn point known for " .. e.name .. ".") return nil end
	local how = ns.SetWaypoint(spot.map, spot.x, spot.y, e.name)
	local where = ("%s %.1f, %.1f"):format(B.ZoneName(ns.Data, spot.map, ns.MapName), spot.x * 100, spot.y * 100)
	if how == "tomtom" then ns:Print("TomTom waypoint: " .. e.name .. ", " .. where .. ".")
	elseif how == "game" then ns:Print("Waypoint: " .. e.name .. ", " .. where .. " (on your map and screen).")
	else ns:Print("this map takes no waypoint. " .. e.name .. ": " .. where .. ".") end
	return how, spot
end

------------------------------------------------------------------------
-- Page: Bestiary
------------------------------------------------------------------------
-- A row of chips that wraps: { { label = text | fn, active = fn, onClick = fn(button), tip } }.
local function ChipRow(stack, defs)
	local f = CreateFrame("Frame")
	f:SetParent(stack.parent)
	f.buttons = {}
	for i, d in ipairs(defs) do
		local b = CreateFrame("Button", nil, f)
		b:SetHeight(24)
		b.bg = U.Solid(b, "BACKGROUND", rgba(T.surface))
		b.bg:SetAllPoints()
		b.border = U.Border(b, 1, rgba(T.border))
		b.text = UI.Text(b, T.font, T.text)
		b.text:SetPoint("CENTER")
		b.text:SetWordWrap(false)
		b:SetScript("OnClick", function(self) d.onClick(self); stack:RefreshAll() end)
		if d.tip then UI.Tooltip(b, nil, d.tip) end
		b.def = d
		f.buttons[i] = b
	end
	function f:Refresh()
		local x, y, w = 0, 0, stack.width
		for _, b in ipairs(f.buttons) do
			local d = b.def
			b.text:SetText(type(d.label) == "function" and d.label() or d.label)
			local on = d.active and d.active() or false
			b.bg:SetVertexColor(rgba(on and T.accentDim or T.surface))
			b.border:SetColor(rgba(on and T.accent or T.border))
			b.text:SetTextColor(rgba(on and T.text or T.muted))
			local bw = math.floor(((b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth()) or b.text:GetStringWidth() or 60) + 22)
			if x > 0 and x + bw > w then x, y = 0, y + 30 end
			b:SetWidth(bw)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", x, -y)
			x = x + bw + 6
		end
		stack:SetHeightOf(f, y + 24)
	end
	stack:Add(f, 24, 10)
	f:Refresh()
	return f
end

local function familyItems()
	local items = { { value = 0, text = "Any family" } }
	local ids = {}
	for id in pairs(ns.Data.families) do ids[#ids + 1] = id end
	table.sort(ids, function(a, b) return (ns.FamilyName(a) or "") < (ns.FamilyName(b) or "") end)
	for _, id in ipairs(ids) do items[#items + 1] = { value = id, text = ns.FamilyName(id), icon = ns.Data.families[id].icon } end
	return items
end

local function zoneItems()
	local w = ns.Where()
	local items = { { value = 0, text = "Any zone" } }
	if w.zone then items[#items + 1] = { value = "here", text = "This zone (" .. B.ZoneName(ns.Data, w.zone, ns.MapName) .. ")" } end
	if w.continent then items[#items + 1] = { value = "continent", text = "This continent" } end
	-- the zones beasts live in, on your continent (or all when we don't know where you are)
	local seen, zs = {}, {}
	for _, e in ipairs((B.Entries(ns.Data))) do
		for _, z in ipairs(e.zones) do
			if type(z) == "number" and not seen[z] and (not w.continent or B.Continent(ns.Data, z) == w.continent) then
				seen[z] = true
				zs[#zs + 1] = { value = z, text = B.ZoneName(ns.Data, z, ns.MapName) }
			end
		end
	end
	table.sort(zs, function(a, b) return a.text < b.text end)
	for _, z in ipairs(zs) do items[#items + 1] = z end
	return items
end

local function itemText(items, v)
	for _, it in ipairs(items) do if it.value == v then return it.text end end
end

local function bestiaryPage(stack)
	-- the search box, top centre of the page
	local top = CreateFrame("Frame")
	top:SetParent(stack.parent)
	local box = UI.EditBox(top, math.min(360, stack.width - 40), 26)
	box:SetPoint("TOP", top, "TOP", 0, 0)
	local hint = UI.Text(box, T.font, T.muted)
	hint:SetPoint("LEFT", 8, 0)
	hint:SetText("Find a beast: bite 6, cat, stranglethorn, rare")
	local function updateHint() hint:SetShown(not box:HasFocus() and (box:GetText() or "") == "") end
	box:HookScript("OnEditFocusGained", updateHint)
	box:HookScript("OnEditFocusLost", updateHint)
	box:SetScript("OnTextChanged", function(self, user)
		updateHint()
		if user then
			Br.filter.query = self:GetText() or ""
			if Br.list then Br.list:ResetPage() end
			stack:RefreshAll()
		end
	end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEscapePressed", function(self)
		if (self:GetText() or "") ~= "" then
			self:SetText("")
			Br.filter.query = ""
			stack:RefreshAll()
		end
		self:ClearFocus()
	end)
	UI.Tooltip(box, "Find a beast", "An ability rank (bite 6), an ability (dash), a family (cat), a zone (stranglethorn), "
		.. "rare, elite, fast, a level (32) or part of a name. Every word must match.")
	box:SetText(Br.filter.query or "")
	updateHint()
	Br.searchBox = box
	stack:Add(top, 26, 10)

	local F = Br.filter
	local function toggle(key) return function() F[key] = not F[key] or nil; if Br.list then Br.list:ResetPage() end end end
	local function active(key) return function() return F[key] and true or false end end
	ChipRow(stack, {
		{ label = function() return "Family: " .. (F.family and ns.FamilyName(F.family) or "any") .. " v" end,
			active = function() return F.family ~= nil end,
			onClick = function(b)
				UI.OpenPopup(b, familyItems(), F.family or 0, function(v)
					F.family = v ~= 0 and v or nil
					if Br.list then Br.list:ResetPage() end
					stack:RefreshAll()
				end, { width = 180 })
			end },
		{ label = function()
				if not F.zone then return "Zone: any v" end
				return "Zone: " .. (itemText(zoneItems(), F.zone) or B.ZoneName(ns.Data, F.zone, ns.MapName)) .. " v"
			end,
			active = function() return F.zone ~= nil end,
			onClick = function(b)
				UI.OpenPopup(b, zoneItems(), F.zone or 0, function(v)
					F.zone = v ~= 0 and v or nil
					if Br.list then Br.list:ResetPage() end
					stack:RefreshAll()
				end, { width = 220 })
			end },
		{ label = "Near my level", active = active("near"), onClick = toggle("near"),
			tip = ("Beasts whose levels reach from %d below to %d above yours."):format(B.NEAR_BELOW, B.NEAR_ABOVE) },
		{ label = "Rare", active = active("rare"), onClick = toggle("rare") },
		{ label = "Fast attack", active = active("fast"), onClick = toggle("fast"),
			tip = "Beasts whose tames showed a faster attack than 2.0 s." },
		{ label = "Untamed by you", active = active("untamed"), onClick = toggle("untamed"),
			tip = "Leaves out the beasts you have tamed (this character)." },
		{ label = "Wishlist", active = active("wish"), onClick = toggle("wish"),
			tip = "Only the beasts you starred. You hear about them when one is near." },
	})

	UI.Note(stack, function()
		local items = Br.Items()
		local n = 0
		for _ in pairs(ns.cdb and ns.cdb.wishlist or {}) do n = n + 1 end
		return ("%d beast%s. %d on your wishlist. Chips: %sgold|r your pet would gain it, %sgrey|r it has it; the edge is "
			.. "%sgreen|r when confirmed, white when seen in WoW Forever, grey for classic data."):format(#items,
			#items == 1 and "" or "s", n, GOLD, MUTED, GREEN)
	end)

	Br.list = ns.Cards(stack, {
		items = Br.Items,
		icon = function(e) return ns.Data.families[e.family] and ns.Data.families[e.family].icon end,
		title = Br.Title,
		sub = Br.Sub,
		chips = function(e) return Br.ChipList(e, Br.CardCtx()) end,
		star = { get = function(e) return ns.IsWished(e.id) end, set = function(e, on) ns.SetWished(e.id, on) end,
			tip = "You get a chat line when one is near (Settings)." },
		onClick = function(e) Br.OpenBeast(e) end,
		tooltip = function(e) return Br.Tooltip(e, Br.CardCtx()) end,
		empty = function()
			if (Br.filter.query or "") ~= "" then return "No beast matches \"" .. Br.filter.query .. "\". Try fewer words." end
			return "No beast matches these chips."
		end,
	})
end

function Br.AddBestiary(a)
	app, T = a, a.T
	app:Section("bestiary", "Bestiary", bestiaryPage)
end

------------------------------------------------------------------------
-- Page: one beast
------------------------------------------------------------------------
local function headerBlock(stack)
	local f = CreateFrame("Frame")
	f:SetParent(stack.parent)
	local back = UI.Button(f, "< Bestiary", function() app:ShowSection("bestiary") end, 100)
	back:SetPoint("TOPLEFT")
	local icon = f:CreateTexture(nil, "ARTWORK")
	icon:SetSize(32, 32)
	icon:SetPoint("TOPLEFT", 112, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local name = UI.Text(f, T.fontHuge, T.text)
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, 0)
	name:SetPoint("RIGHT")
	name:SetWordWrap(false)
	local sub = UI.Text(f, T.fontSmall + 1, T.muted)
	sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	sub:SetPoint("RIGHT")
	sub:SetWordWrap(false)
	function f:Refresh()
		local e = Br.current
		if not e then name:SetText("No beast picked"); sub:SetText("Pick one on the Bestiary page."); icon:Hide() return end
		local fam = ns.Data.families[e.family]
		icon:SetTexture(fam and fam.icon)
		icon:Show()
		name:SetText(e.name)
		local parts = { (ns.FamilyName(e.family) or e.famKey), "level " .. B.Levels(e) }
		if B.RANK_WORD[e.rank] then parts[#parts + 1] = GOLD .. B.RANK_WORD[e.rank] .. "|r" end
		if ns.cdb and ns.cdb.tamed[e.id] then parts[#parts + 1] = GREEN .. "tamed by you|r" end
		if ns.IsWished(e.id) then parts[#parts + 1] = "on your wishlist" end
		sub:SetText(table.concat(parts, " · "))
	end
	stack:Add(f, 40, 12)
	f:Refresh()
	return f
end

-- The model on the left (drag to turn it), the facts on the right.
local function modelBlock(stack)
	local f = CreateFrame("Frame")
	f:SetParent(stack.parent)
	local H = 190
	local box = CreateFrame("Frame", nil, f)
	box:SetSize(180, H)
	box:SetPoint("TOPLEFT")
	U.Solid(box, "BACKGROUND", rgba(T.surface)):SetAllPoints()
	U.Border(box, 1, rgba(T.border))
	local none = UI.Text(box, T.fontSmall + 1, T.muted)
	none:SetPoint("CENTER")
	none:SetWidth(160)
	none:SetJustifyH("CENTER")
	local model
	local facts = UI.Text(f, T.font, T.text)
	facts:SetPoint("TOPLEFT", box, "TOPRIGHT", 14, -2)
	facts:SetPoint("RIGHT")
	facts:SetSpacing(4)
	local function makeModel()
		if model then return model end
		model = CreateFrame("PlayerModel", nil, box)
		model:SetPoint("TOPLEFT", 1, -1)
		model:SetPoint("BOTTOMRIGHT", -1, 1)
		model.rot = 0
		model:EnableMouse(true)
		model:SetScript("OnMouseDown", function(self) self.dragX = GetCursorPosition() end)
		model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
		model:SetScript("OnHide", function(self) self.dragX = nil end)
		model:SetScript("OnUpdate", function(self)
			if not self.dragX then return end
			local x = GetCursorPosition()
			self.rot = self.rot + (x - self.dragX) / 80
			self.dragX = x
			ns.Call(self.SetRotation, self, self.rot)
		end)
		return model
	end
	function f:Refresh()
		local e = Br.current
		local show = e and ns.db.models and e.display and e.display > 0
		if show then
			local m = makeModel()
			m:Show()
			if m.shown ~= e.display then
				ns.Call(m.ClearModel, m)
				ns.Call(m.SetDisplayInfo, m, e.display)
				m.rot = 0.6
				ns.Call(m.SetRotation, m, m.rot)
				m.shown = e.display
			end
			none:SetText("")
		else
			if model then model:Hide() end
			none:SetText(not e and "" or (not ns.db.models and "Models are off (Settings)." or "No model known."))
		end
		facts:SetText(e and Br.Facts(e) or "")
	end
	stack:Add(f, H, 14)
	f:Refresh()
	return f
end

-- The facts next to the model.
function Br.Facts(e)
	local L = {}
	local function add(label, value) L[#L + 1] = MUTED .. label .. "|r  " .. value end
	add("Level", B.Levels(e) .. (ns.state.playerLevel and e.lo > ns.state.playerLevel and (RED .. "  too high for you until " .. e.lo .. "|r") or ""))
	add("Attack speed", Br.SpeedText(e) or "not reported yet (it shows when someone tames one)")
	local fam = ns.Data.families[e.family]
	if fam then add("Eats", table.concat(Logic.Foods(ns.Data, fam.diet), ", ")) end
	add("Where", zoneNames(e))
	local n = ns.cdb and ns.cdb.tamed[e.id]
	add("Tamed by you", n and (n > 1 and (n .. " times") or "yes") or "not yet")
	add("Wishlist", ns.IsWished(e.id) and "yes: you hear when one is near" or "no")
	return table.concat(L, "\n")
end

-- The teach list rows for a beast: { chip, ab, cost, net, rel text }.
function Br.TeachRows(e, ctx)
	local out = {}
	for _, c in ipairs(B.Chips(ns.Data, e, ctx)) do
		local ab = ns.Data.abilities[c.key]
		local have = ctx.pet and ctx.pet.have(c.key) or 0
		local cost, net
		if ab then cost, net = B.Cost(ns.Data, ab, c.rank, have) end
		out[#out + 1] = { chip = c, ab = ab, cost = cost, net = net, have = have }
	end
	return out
end

local function teachDetail(r, ctx)
	local c = r.chip
	local parts = { Logic.STATE_LABEL[c.state] or c.state }
	if ctx.pet then
		if c.rel == "gain" then parts[#parts + 1] = GOLD .. (r.have > 0 and ("your pet has rank " .. r.have) or "your pet doesn't have it") .. "|r"
		elseif c.rel == "later" then parts[#parts + 1] = "your pet's level doesn't allow it yet"
		elseif c.rel == "have" then parts[#parts + 1] = "your pet has it"
		else parts[#parts + 1] = "your pet's family can't learn it" end
	end
	if r.cost then parts[#parts + 1] = r.cost .. " training points" .. ((r.net and r.net ~= r.cost) and (" (" .. r.net .. " for your pet)") or "") end
	return table.concat(parts, " · ")
end

local function beastPage(stack)
	headerBlock(stack)
	local row = UI.ButtonRow(stack, {
		{ label = "Set waypoint", width = 130, style = "accent",
			desc = "A waypoint to where it spawns: the nearest spot on your map, else one on your continent. TomTom's when TomTom is loaded.",
			onClick = function() if Br.current then Br.Waypoint(Br.current) end end },
		{ label = "Add to wishlist", width = 150,
			onClick = function()
				local e = Br.current
				if e then ns.SetWished(e.id, not ns.IsWished(e.id)); stack:RefreshAll() end
			end },
		{ label = "EverlookDB page", width = 140,
			onClick = function()
				local e = Br.current
				if e then ns.Options:ShowLink("EverlookDB: " .. e.name .. " (map, spawns, what it teaches).", Logic.NPC_URL .. e.id) end
			end },
		search = false,
		refresh = function(r)
			local e = Br.current
			r.buttons[1]:SetUsable(e ~= nil and #e.spots > 0)
			r.buttons[2]:SetText(e and ns.IsWished(e.id) and "Remove from wishlist" or "Add to wishlist")
			r.buttons[2]:SetUsable(e ~= nil)
			r.buttons[3]:SetUsable(e ~= nil)
		end,
	})
	Br.beastButtons = row
	modelBlock(stack)

	UI.Header(stack, "What it teaches", "Each rank, how sure we are of it, and what it means for your pet.")
	Br.teachList = ns.Cards(stack, {
		rowHeight = 44,
		items = function() return Br.current and Br.TeachRows(Br.current, Br.Ctx()) or {} end,
		icon = function(r) return r.ab and ns.AbilityIcon(r.ab) end,
		title = function(r)
			local color = Br.ChipColors(r.chip)
			return hexOf(color) .. r.chip.text .. "|r"
		end,
		sub = function(r) return teachDetail(r, Br.Ctx()) end,
		tooltip = function(r) return { r.chip.text, Logic.STATE_LABEL[r.chip.state] or r.chip.state,
			"Fight with the tamed beast until you learn it, then teach your pet with Beast Training." } end,
		empty = "Nobody has reported what it teaches yet. Beast Lore it and upload with EverlookDB.",
	})

	UI.Header(stack, "Where it spawns")
	UI.Note(stack, function()
		local e = Br.current
		if not e then return "" end
		if #e.spots == 0 then return #e.zones > 0 and ("In " .. zoneNames(e) .. ". No spawn points known yet.") or "Where it lives isn't known yet." end
		return e.spotsFrom == 1 and "Where WoW Forever players found it (Forever Hunter Pets, MIT)."
			or "Spawn points from classic-db (Classic 1.12, GPL-3.0); WoW Forever may differ."
	end)
	Br.spotList = ns.Cards(stack, {
		rowHeight = 36,
		items = function() return Br.current and Br.current.spots or {} end,
		title = function(s) return ("%s  %s%.1f, %.1f|r"):format(B.ZoneName(ns.Data, s.map, ns.MapName), MUTED, s.x * 100, s.y * 100) end,
		buttons = { { label = "Waypoint", width = 90, onClick = function(s) if Br.current then Br.Waypoint(Br.current, s) end end } },
		empty = "",
	})
end

function Br.AddBeast(a)
	app, T = a, a.T
	app:Section("beast", "Beast", beastPage)
end
