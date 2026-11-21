-- EverlookDB Pets: the Recent page. Everything the addon told you (the level-up card, the chat lines about your pet,
-- beasts near you, a waypoint that couldn't be set) is kept here, newest first, with buttons to act on it again:
-- Show card (the level-up card for that level), Waypoint, Open beast, Your pet. A message closed mid-fight is never
-- lost. Command echo and help (/epets check, wishlist, status...) are not kept.
--   ns.Tell(kind, text, data)  says it in chat and keeps it (the alerts use this instead of ns:Print)
--   ns.Recent.Add(kind, text, data)  only keeps it (the level-up card)
-- Kept per character (EverlookPetsCharDB.recent), the newest R.MAX: { t = time(), k = kind, x = plain text,
-- lv = level (a level-up), npc = beast id, pet = pet name, more = { lines } }. Never a GUID, a spawn's id or where it
-- was: only the NPC id. The page never opens by itself; the sidebar's "Recent" shows a count until it is seen.
local _, ns = ...
local UI = ns.UI
local U = UI.Util
local R = {}
ns.Recent = R

R.MAX = 100
local MUTED, GOLD, GREEN = "|cff8d94a3", "|cffffd200", "|cff62cf88"
local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

-- The kinds: their filter chip, the word under a row, the icon.
R.KINDS = {
	levelup = { label = "Level-up", word = "Level-up card", icon = "Interface\\Icons\\Spell_ChargePositive" },
	beast = { label = "Beasts nearby", word = "Beast nearby", icon = "Interface\\Icons\\Ability_Tracking" },
	pet = { label = "Pet", word = "Your pet", icon = "Interface\\Icons\\Ability_Hunter_BeastTraining" },
	other = { label = "Other", word = ns.NAME, icon = "Interface\\Icons\\INV_Misc_Note_01" },
}
R.FILTERS = { "all", "levelup", "beast", "pet" }
R.filter = "all"

------------------------------------------------------------------------
-- Keeping messages
------------------------------------------------------------------------
-- Chat text as plain text: links become their label, colours go.
function R.Plain(s)
	s = tostring(s or "")
	s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
	return (s:gsub("%s+$", ""))
end

local function now() return ns.Num((ns.Call(_G.time))) or 0 end

function R.List()
	if not ns.cdb then return {} end
	if type(ns.cdb.recent) ~= "table" then ns.cdb.recent = {} end
	return ns.cdb.recent
end

-- Is the Recent page in front of you now (then nothing is unread)?
function R.Looking()
	local app = ns.app
	return app and app:IsShown() and app.current == "recent" and not app.searching and true or false
end

-- Keep a message. kind: "levelup", "beast", "pet" or "other"; data: { level, npc, pet, more } (only these are kept).
function R.Add(kind, text, data)
	if not ns.cdb then return nil end
	kind = R.KINDS[kind] and kind or "other"
	data = type(data) == "table" and data or {}
	local e = { t = now(), k = kind, x = R.Plain(text) }
	e.lv = ns.Num(data.level)
	e.npc = ns.Num(data.npc)
	e.pet = ns.Str(data.pet)
	if type(data.more) == "table" then
		local more = {}
		for i, l in ipairs(data.more) do
			if i > 20 then break end
			if type(l) == "string" then more[#more + 1] = R.Plain(l) end
		end
		if #more > 0 then e.more = more end
	end
	local list = R.List()
	list[#list + 1] = e
	while #list > R.MAX do table.remove(list, 1) end
	if R.Looking() then
		ns.cdb.recentUnread = 0
		ns.app:Refresh()
	else
		ns.cdb.recentUnread = math.min(R.MAX, (tonumber(ns.cdb.recentUnread) or 0) + 1)
	end
	R.Paint()
	return e
end

-- Say it in chat and keep it.
function ns.Tell(kind, text, data)
	R.Add(kind, text, data)
	ns:Print(text)
end

function R.Unread() return ns.cdb and tonumber(ns.cdb.recentUnread) or 0 end

function R.MarkSeen()
	if ns.cdb and R.Unread() > 0 then ns.cdb.recentUnread = 0 end
	R.Paint()
end

function R.Clear()
	if not ns.cdb then return end
	ns.cdb.recent = {}
	ns.cdb.recentUnread = 0
	R.note = nil
	R.Paint()
end

-- The messages the page lists: newest first, of the chosen kind.
function R.Items(filter)
	filter = filter or R.filter
	local list, out = R.List(), {}
	for i = #list, 1, -1 do
		local e = list[i]
		if filter == "all" or e.k == filter then out[#out + 1] = e end
	end
	return out
end

function R.Count(kind)
	local n = 0
	for _, e in ipairs(R.List()) do if kind == "all" or e.k == kind then n = n + 1 end end
	return n
end

------------------------------------------------------------------------
-- How a message reads
------------------------------------------------------------------------
-- "just now", "12m ago", "3h ago", "today 09:05", "yesterday 21:14", "Mon 21:14", "12 Nov 21:14".
function R.Ago(t, at)
	at = at or now()
	t = tonumber(t) or 0
	local d = at - t
	if d < 60 then return "just now" end
	if d < 3600 then return math.floor(d / 60) .. "m ago" end
	local date = _G.date
	if type(date) ~= "function" then return math.floor(d / 3600) .. "h ago" end
	local a, b = date("*t", t), date("*t", at)
	local clock = date("%H:%M", t)
	local sameDay = a.year == b.year and a.yday == b.yday
	if sameDay then
		if d < 6 * 3600 then return math.floor(d / 3600) .. "h ago" end
		return "today " .. clock
	end
	local y = date("*t", at - 86400)
	if a.year == y.year and a.yday == y.yday then return "yesterday " .. clock end
	if d < 6 * 86400 then return date("%a", t) .. " " .. clock end
	return date("%d %b", t):gsub("^0", "") .. " " .. clock
end

function R.Beast(e) return e and e.npc and ns.Bestiary.Get(ns.Data, e.npc) or nil end

function R.Icon(e)
	if e.k == "beast" then
		local b = R.Beast(e)
		local fam = b and ns.Data.families[b.family]
		if fam and fam.icon then return fam.icon end
	end
	return (R.KINDS[e.k] or R.KINDS.other).icon
end

function R.Title(e) return e.x or "" end

function R.Sub(e)
	return MUTED .. R.Ago(e.t) .. " · " .. (R.KINDS[e.k] or R.KINDS.other).word .. "|r"
end

function R.Tooltip(e)
	local lines = { (R.KINDS[e.k] or R.KINDS.other).word, e.x }
	for _, l in ipairs(e.more or {}) do lines[#lines + 1] = "  " .. l end
	local date = _G.date
	if type(date) == "function" and (e.t or 0) > 0 then lines[#lines + 1] = MUTED .. date("%d %b %H:%M", e.t) .. "|r" end
	local hint = R.Hint(e)
	if hint then lines[#lines + 1] = MUTED .. hint .. "|r" end
	return lines
end

function R.Hint(e)
	if e.k == "levelup" and e.lv then return "Click to show the card for level " .. e.lv .. " again." end
	if e.k == "beast" and R.Beast(e) then return "Click for the beast's page." end
	if e.k == "pet" then return "Click for your pet's page." end
	return nil
end

------------------------------------------------------------------------
-- Acting again
------------------------------------------------------------------------
function R.ShowCard(e)
	if not (e and e.lv and ns.LevelUp) then return nil end
	return ns.LevelUp.Show(e.lv, true)
end

-- A waypoint to the beast again; what it did shows under the chips (not in chat).
function R.Waypoint(e)
	local b = R.Beast(e)
	if not b then return nil end
	local how, _, text = ns.Browser.Waypoint(b)
	R.note = text and { text = text, ok = how ~= nil } or nil
	if ns.app and ns.app:IsShown() then ns.app:Refresh() end
	return how, text
end

function R.OpenBeast(e)
	local b = R.Beast(e)
	if b then return ns.Browser.OpenBeast(b) end
	return false
end

function R.OpenPet() if ns.app then ns.app:ShowSection("pet") end end

-- A click on the card itself: its first action.
function R.Act(e)
	if e.k == "levelup" then return R.ShowCard(e) end
	if e.k == "beast" then return R.OpenBeast(e) end
	if e.k == "pet" then return R.OpenPet() end
end

------------------------------------------------------------------------
-- The sidebar's count
------------------------------------------------------------------------
local app, T

function R.Paint()
	if not app then return end
	local nav = app.window and app.window.navButtons
	local b = nav and nav.recent
	if not b then return end
	local n = R.Unread()
	if R.Looking() then n = 0 end
	if not b.count then
		local c = CreateFrame("Frame", nil, b)
		c:SetHeight(16)
		c:SetPoint("RIGHT", -8, 0)
		c.bg = U.Round(c, 8, "ARTWORK")
		c.bg:SetAllPoints(c)
		c.bg:SetVertexColor(rgba(T.accent))
		c.text = UI.Text(c, T.fontSmall, { 0.06, 0.07, 0.09, 1 })
		c.text:SetPoint("CENTER", 0, 0)
		b.count = c
	end
	b.count.text:SetText(n > 99 and "99+" or tostring(n))
	b.count:SetWidth(math.max(16, math.floor((b.count.text:GetStringWidth() or 8) + 10)))
	b.count:SetShown(n > 0)
end

------------------------------------------------------------------------
-- Page: Recent
------------------------------------------------------------------------
-- The filter chips (one at a time) and Clear on the right.
local function chipRow(stack)
	local f = CreateFrame("Frame")
	f:SetParent(stack.parent)
	f.chips = {}
	for i, kind in ipairs(R.FILTERS) do
		local b = CreateFrame("Button", nil, f)
		b:SetHeight(24)
		b.bg = U.Solid(b, "BACKGROUND", rgba(T.surface))
		b.bg:SetAllPoints()
		b.border = U.Border(b, 1, rgba(T.border))
		b.text = UI.Text(b, T.font, T.text)
		b.text:SetPoint("CENTER")
		b.text:SetWordWrap(false)
		b.kind = kind
		b:SetScript("OnClick", function(self)
			R.filter = self.kind
			if R.list then R.list:ResetPage() end
			stack:RefreshAll()
		end)
		f.chips[i] = b
	end
	-- plain, and it asks first: the page has no primary button
	f.clear = UI.ConfirmButton(f, "Clear", function()
		R.Clear()
		stack:RefreshAll()
	end, 110, "plain")
	f.clear:SetHeight(24)
	f.clear:SetPoint("TOPRIGHT", 0, 0)
	UI.Tooltip(f.clear, "Clear", "Forget every message on this page (this character).")
	function f:Refresh()
		local x = 0
		for _, b in ipairs(f.chips) do
			local label = b.kind == "all" and "All" or R.KINDS[b.kind].label
			local n = R.Count(b.kind)
			b.text:SetText(label .. (n > 0 and ("  " .. MUTED .. n .. "|r") or ""))
			local on = R.filter == b.kind
			b.bg:SetVertexColor(rgba(on and T.accentDim or T.surface))
			b.border:SetColor(rgba(on and T.accent or T.border))
			b.text:SetTextColor(rgba(on and T.text or T.muted))
			local w = math.floor(((b.text.GetUnboundedStringWidth and b.text:GetUnboundedStringWidth()) or b.text:GetStringWidth() or 60) + 22)
			b:SetWidth(w)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", x, 0)
			x = x + w + 6
		end
		f.clear:SetUsable(#R.List() > 0)
	end
	stack:Add(f, 24, 10)
	f:Refresh()
	return f
end

local function page(stack)
	UI.Header(stack, "Recent", "Everything " .. ns.NAME .. " told you, newest first: the level-up card, your pet, beasts near you. "
		.. "Missed one mid-fight? It's here, with a button to show the card or set the waypoint again.")
	R.chips = chipRow(stack)
	UI.Note(stack, function()
		local w = R.note
		if w then return (w.ok and GREEN or MUTED) .. w.text .. "|r" end
		local n = #R.List()
		if n == 0 then return "" end
		return ("%d message%s kept (the newest %d). %s recent opens this page."):format(n, n == 1 and "" or "s", R.MAX, ns.SLASH)
	end)
	R.list = ns.Cards(stack, {
		rowHeight = 54,
		titleLines = 2,
		page = 25,
		items = function() return R.Items() end,
		icon = R.Icon,
		title = R.Title,
		sub = R.Sub,
		tooltip = R.Tooltip,
		onClick = R.Act,
		buttons = {
			{ label = "Show card", width = 88, shown = function(e) return e.k == "levelup" and e.lv ~= nil end, onClick = R.ShowCard },
			{ label = "Waypoint", width = 84, onClick = R.Waypoint,
				shown = function(e) local b = R.Beast(e); return b ~= nil and #(b.spots or {}) > 0 end },
			{ label = "Open beast", width = 92, shown = function(e) return R.Beast(e) ~= nil end, onClick = R.OpenBeast },
			{ label = "Your pet", width = 80, shown = function(e) return e.k == "pet" end, onClick = R.OpenPet },
		},
		empty = function()
			if #R.List() == 0 then
				return "Nothing yet. When " .. ns.NAME .. " tells you something (a level-up card, a rare beast near you, a new rank "
					.. "for your pet), it shows up here too."
			end
			return "Nothing of this kind. Pick All to see every message."
		end,
	})
end

-- Options.lua adds the page right after "Your pet": high in the sidebar.
function R.AddPage(a)
	app, T = a, a.T
	app:Section("recent", "Recent", page)
	-- seeing the page reads its messages; the count is drawn on the sidebar once the window exists
	local show = app.ShowSection
	app.ShowSection = function(self, id, ...)
		show(self, id, ...)
		if id == "recent" then R.MarkSeen() end
		R.Paint()
	end
end

-- "/epets recent" (and the plugin's and minimap button's right-click): the window on this page.
function R.Open()
	if ns.app then ns.app:Open("recent") end
end
