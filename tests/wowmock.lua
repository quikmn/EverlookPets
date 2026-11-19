-- A small fake of the WoW client for offline tests (from Everlook Bar's; a hunter and a pet at the end) (Lua 5.1 via lupa).
-- Secret values are tables with a locked metatable: arithmetic, comparison, length, indexing and calls throw, the
-- way the real client stops addons from reading them. Widget setters that the client lets take secrets accept
-- them; every other widget method throws when handed one.

MOCK = { log = {}, combat = false, time = 1000, timers = {}, tickers = {}, widgets = {}, setText = 0, loaded = {} }

local SecretMT = {}
local function misuse(what) error("SECRET VALUE MISUSE: " .. what .. " on a secret value", 2) end
SecretMT.__add = function() misuse("arithmetic (+)") end
SecretMT.__sub = function() misuse("arithmetic (-)") end
SecretMT.__mul = function() misuse("arithmetic (*)") end
SecretMT.__div = function() misuse("arithmetic (/)") end
SecretMT.__mod = function() misuse("arithmetic (%)") end
SecretMT.__unm = function() misuse("negation") end
SecretMT.__lt = function() misuse("comparison (<)") end
SecretMT.__le = function() misuse("comparison (<=)") end
SecretMT.__len = function() misuse("length (#)") end
SecretMT.__index = function() misuse("indexing") end
SecretMT.__newindex = function() misuse("index assignment") end
SecretMT.__call = function() misuse("call") end
SecretMT.__concat = function() return "<secret>" end
SecretMT.__tostring = function() return "<secret>" end
SecretMT.__metatable = "secret"
function MOCK.Secret(v) local s = setmetatable({}, SecretMT); rawset(s, "__real", v); return s end
local function isSecret(v) return type(v) == "table" and getmetatable(v) == "secret" end
MOCK.isSecret = isSecret
function issecretvalue(v) return isSecret(v) end

local SECRET_OK = { SetText = true, SetFormattedText = true, SetValue = true, SetAlpha = true, SetVertexColor = true,
	SetTexture = true, SetTextColor = true, SetShown = true }

local Widget = {}
local impl = {}

local function newWidget(kind, name, parent)
	local w = setmetatable({ __kind = kind, __name = name, __parent = parent, __shown = true, __scripts = {},
		__events = {}, __children = {}, __text = "", __w = 0, __h = 0, __alpha = 1, __level = 1, __points = {} }, Widget)
	MOCK.widgets[#MOCK.widgets + 1] = w
	if name then _G[name] = w end
	if parent and parent.__children then table.insert(parent.__children, w) end
	return w
end
MOCK.newWidget = newWidget

function impl:GetName() return self.__name end
function impl:GetParent() return self.__parent end
function impl:SetParent(p)
	local old = self.__parent
	if old and old.__children then
		for i, c in ipairs(old.__children) do if c == self then table.remove(old.__children, i) break end end
	end
	self.__parent = p
	if p and p.__children then table.insert(p.__children, self) end
end
function impl:Show() local was = self.__shown; self.__shown = true; if not was and self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function impl:Hide() local was = self.__shown; self.__shown = false; if was and self.__scripts.OnHide then self.__scripts.OnHide(self) end end
function impl:SetShown(v) if v then self:Show() else self:Hide() end end
function impl:IsShown() return self.__shown end
function impl:IsVisible()
	local f = self
	while f do if not f.__shown then return false end f = f.__parent end
	return true
end
function impl:SetSize(w, h) self.__w, self.__h = w, h end
function impl:SetWidth(w) self.__w = w end
function impl:SetHeight(h) self.__h = h end
function impl:GetWidth() return self.__w end
function impl:GetHeight() return self.__h end
function impl:GetSize() return self.__w, self.__h end
function impl:SetPoint(...) table.insert(self.__points, { ... }) end
function impl:ClearAllPoints() self.__points = {} end
function impl:GetNumPoints() return #self.__points end
function impl:GetPoint(i) local p = self.__points[i or 1]; if p then return unpack(p) end end
function impl:GetLeft() return self.__left or 100 end
function impl:GetBottom() return self.__bottom or 400 end
function impl:GetTop() return (self.__bottom or 400) + self.__h end
function impl:GetRight() return (self.__left or 100) + self.__w end
function impl:GetCenter() return (self.__left or 100) + self.__w / 2, (self.__bottom or 400) + self.__h / 2 end
function impl:SetScript(k, fn) self.__scripts[k] = fn end
function impl:SetAttribute(k, v) self.__attrs = self.__attrs or {}; self.__attrs[k] = v end
function impl:GetAttribute(k) return self.__attrs and self.__attrs[k] end
function impl:GetScript(k) return self.__scripts[k] end
function impl:HookScript(k, fn)
	local old = self.__scripts[k]
	self.__scripts[k] = function(...) if old then old(...) end fn(...) end
end
function impl:RegisterEvent(e)
	if MOCK.unknownEvents and MOCK.unknownEvents[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
	self.__events[e] = true
end
function impl:UnregisterEvent(e) self.__events[e] = nil end
function impl:CreateTexture() return newWidget("Texture", nil, self) end
function impl:CreateFontString() return newWidget("FontString", nil, self) end
function impl:SetFont() return true end
function impl:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function impl:SetText(t) MOCK.setText = MOCK.setText + 1; self.__text = t end
function impl:GetText() return self.__text end
local function textWidth(self)
	if isSecret(self.__text) then return MOCK.Secret(60) end
	local s = tostring(self.__text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
	return #s * 6
end
function impl:GetStringWidth() return textWidth(self) end
function impl:GetUnboundedStringWidth() return textWidth(self) end
function impl:GetStringHeight() return 12 end
function impl:SetAlpha(a) self.__alpha = a end
function impl:GetAlpha() return self.__alpha end
function impl:GetFrameLevel() return self.__level end
function impl:SetFrameLevel(l) if not self.__fixedLevel then self.__level = l end end
function impl:GetEffectiveScale() return (self.__scale or 1) * (self.__parent and self.__parent.GetEffectiveScale and self.__parent:GetEffectiveScale() or 1) end
function impl:StartMoving() self.__moving = true end
function impl:StopMovingOrSizing() self.__moving = false end
function impl:GetObjectType() return self.__kind end
function impl:IsObjectType(t) return self.__kind == t end
local REGION = { Texture = true, FontString = true, MaskTexture = true }
function impl:GetChildren()
	local t = {}
	for _, c in ipairs(self.__children) do if not REGION[c.__kind] then t[#t + 1] = c end end
	return unpack(t)
end
function impl:GetRegions()
	local t = {}
	for _, c in ipairs(self.__children) do if REGION[c.__kind] then t[#t + 1] = c end end
	return unpack(t)
end
function impl:GetNormalTexture() return self.__normal end
function impl:SetNormalTexture(t) self.__normal = t end
function impl:IsProtected() return self.__protected or false end
function impl:IsMouseOver() return false end
function impl:GetZoom() return self.__zoom or 0 end
function impl:SetZoom(z) self.__zoom = z end
function impl:GetZoomLevels() return 5 end
function impl:EnableMouse(on) self.__mouse = on end
function impl:IsMouseEnabled() return self.__mouse end
function impl:HasFocus() return false end
function impl:GetVerticalScroll() return 0 end
function impl:GetValue() return self.__value or 0 end
function impl:SetValue(v) self.__value = v end
function impl:GetMinMaxValues() return 0, 1 end
function impl:GetID() return 0 end
function impl:SetMaskTexture(t) self.__mask = t end
function impl:RegisterForDrag(...) self.__drag = select("#", ...) > 0 end
function impl:SetClampedToScreen(on) self.__clamped = on end
function impl:IsClampedToScreen() return self.__clamped or false end
function impl:GetFrameStrata() return self.__strata or (self.__parent and self.__parent.GetFrameStrata and self.__parent:GetFrameStrata()) or "MEDIUM" end
function impl:SetFrameStrata(s) if not self.__fixedStrata then self.__strata = s end end
function impl:SetFixedFrameStrata(on) self.__fixedStrata = on end
function impl:HasFixedFrameStrata() return self.__fixedStrata or false end
function impl:SetFixedFrameLevel(on) self.__fixedLevel = on end
function impl:HasFixedFrameLevel() return self.__fixedLevel or false end
function impl:CreateMaskTexture() local m = newWidget("MaskTexture", nil, self); return m end
function impl:AddMaskTexture(m) self.__masks = self.__masks or {}; table.insert(self.__masks, m) end
function impl:SetTexture(t) self.__texture = t end
function impl:GetTexture() return self.__texture end
function impl:SetVertexColor(r, g, b, a) self.__color = { r, g, b, a } end
function impl:SetScale(s) self.__scale = s end
function impl:GetScale() return self.__scale or 1 end
function impl:SetMovable(on) self.__movable = on end
function impl:IsMovable() return self.__movable or false end

Widget.__index = function(self, key)
	local f = impl[key]
	if f then
		return function(s, ...)
			if not SECRET_OK[key] then
				for i = 1, select("#", ...) do
					if isSecret((select(i, ...))) then error("SECRET VALUE MISUSE: passed a secret to " .. key, 2) end
				end
			end
			return f(s, ...)
		end
	end
	if type(key) == "string" and key:match("^[A-Z]") then
		return function(s, ...)
			if not SECRET_OK[key] then
				for i = 1, select("#", ...) do
					if isSecret((select(i, ...))) then error("SECRET VALUE MISUSE: passed a secret to " .. key, 2) end
				end
			end
			return nil
		end
	end
	return nil
end

function CreateFrame(kind, name, parent) return newWidget(kind, name, parent) end
function EnumerateFrames(after)
	local seen = after == nil
	for _, w in ipairs(MOCK.widgets) do
		if seen and not REGION[w.__kind] then return w end
		if w == after then seen = true end
	end
end
UIParent = newWidget("Frame", "UIParent", nil)
UIParent.__w, UIParent.__h = 1920, 1080
DEFAULT_CHAT_FRAME = newWidget("Frame", "DEFAULT_CHAT_FRAME")
function DEFAULT_CHAT_FRAME:AddMessage(m) table.insert(MOCK.log, m) end
GameTooltip = newWidget("GameTooltip", "GameTooltip", UIParent)
MOCK.tip = {}
function GameTooltip:AddLine(t) table.insert(MOCK.tip, tostring(t)) end
function GameTooltip:AddDoubleLine(a, b) table.insert(MOCK.tip, tostring(a) .. " | " .. tostring(b)) end
function GameTooltip:SetOwner() MOCK.tip = {} end
ColorPickerFrame = newWidget("Frame", "ColorPickerFrame")
GameFontHighlightSmall = newWidget("Font", "GameFontHighlightSmall")
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-- Minimap and friends
MinimapCluster = newWidget("Frame", "MinimapCluster", UIParent)
Minimap = newWidget("Frame", "Minimap", MinimapCluster)
Minimap.__w, Minimap.__h = 140, 140
Minimap.__left, Minimap.__bottom = 1760, 900
MinimapZoneTextButton = newWidget("Button", "MinimapZoneTextButton", MinimapCluster)
GameTimeFrame = newWidget("Button", "GameTimeFrame", MinimapCluster)
MiniMapTracking = newWidget("Frame", "MiniMapTracking", Minimap)
MinimapCluster.Diel = newWidget("Frame", nil, MinimapCluster)
MinimapCluster.MinimapContainer = newWidget("Frame", nil, MinimapCluster)
-- Blizzard's player coordinates: a frame with a FontString, centred under the minimap
MinimapCluster.MinimapContainer.PlayerCoords = newWidget("Frame", nil, MinimapCluster.MinimapContainer)
MinimapCluster.MinimapContainer.PlayerCoords.CoordText = MinimapCluster.MinimapContainer.PlayerCoords:CreateFontString()
MinimapCluster.MinimapContainer.PlayerCoords.CoordText:SetText("49.5, 55.7")
MinimapCluster.MinimapContainer.PlayerCoords:SetPoint("TOP", Minimap, "BOTTOM", 0, -2)
-- The indicator frame is a layout frame: its children call their parent's Layout() from their own event handler
-- (Blizzard_Minimap/Mainline/Minimap.lua: MiniMapIndicatorFrameMixin, UPDATE_PENDING_MAIL). A child moved under a
-- plain frame makes that call fail ("attempt to call a nil value").
MinimapCluster.IndicatorFrame = newWidget("Frame", nil, MinimapCluster)
MinimapCluster.IndicatorFrame.Layout = function(self) self.__layouts = (self.__layouts or 0) + 1 end
do
	local mail = newWidget("Frame", "MiniMapMailFrame", MinimapCluster.IndicatorFrame)
	MinimapCluster.IndicatorFrame.MailFrame = mail
	mail.layoutIndex = 1
	mail.MailIcon = newWidget("Texture", "MiniMapMailIcon", mail)
	mail.__events.UPDATE_PENDING_MAIL = true
	mail.__scripts.OnEvent = function(self, event)
		if event == "UPDATE_PENDING_MAIL" then
			self:SetShown(HasNewMail())
			self:GetParent():Layout()
		end
	end
	local craft = newWidget("Frame", nil, MinimapCluster.IndicatorFrame)
	MinimapCluster.IndicatorFrame.CraftingOrderFrame = craft
	craft.__events.CRAFTINGORDERS_UPDATE_PERSONAL_ORDER_COUNTS = true
	craft.__scripts.OnEvent = function(self) self:Hide(); self:GetParent():Layout() end
end
-- Blizzard's own code showing its pieces again (zoom buttons on mouse-over, the clock after a CVar change...)
function MOCK.BlizzardShowsAgain()
	for _, o in ipairs({ MinimapZoneTextButton, GameTimeFrame, MinimapCluster.MinimapContainer.PlayerCoords, MinimapCluster.IndicatorFrame.MailFrame }) do
		o:Show()
	end
end

-- Globals
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert, tremove = table.insert, table.remove
format = string.format
date = os.date
time = os.time
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
hooksecurefunc = function(t, k, fn)
	if type(t) == "string" then t, k, fn = _G, t, k end
	local old = t[k]
	rawset(t, k, function(...) local r = { old(...) }; fn(...); return unpack(r) end)
end
geterrorhandler = function() return function(e) table.insert(MOCK.log, "ERRORHANDLER " .. tostring(e)) end end
securecallfunction = function(f, ...) return f(...) end
debugprofilestop = function() return os.clock() * 1000 end
GetTime = function() return MOCK.time end
InCombatLockdown = function() return MOCK.combat end
IsLoggedIn = function() return MOCK.loggedIn end
IsShiftKeyDown = function() return false end
GetCursorPosition = function() return MOCK.cursorX or 0, MOCK.cursorY or 0 end
ReloadUI = function() MOCK.reloaded = true end
GetLocale = function() return "enUS" end
SlashCmdList = {}
Enum = setmetatable({}, { __index = function(t, k) local e = setmetatable({}, { __index = function(_, kk) return kk end }); rawset(t, k, e); return e end })
Enum.CalendarStatus = { Invited = 0, Available = 1, Declined = 2, Confirmed = 3, NotSignedup = 7, Tentative = 8 }
Enum.CalendarInviteType = { Normal = 0, Signup = 1 }
Enum.AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, PeakTime = 4, CountTimeOver1Ms = 5 }

C_Timer = {
	After = function(_, fn) table.insert(MOCK.timers, fn) end,
	NewTicker = function(_, fn) table.insert(MOCK.tickers, fn); return { Cancel = function() end } end,
}
function MOCK.RunTimers()
	for _ = 1, 5 do
		local t = MOCK.timers
		if #t == 0 then return end
		MOCK.timers = {}
		for _, fn in ipairs(t) do fn() end
	end
end

MOCK.addons = { "EverlookBar", "OtherAddon" }
C_AddOns = {
	GetAddOnMetadata = function(_, k) if k == "Version" then return "0.1.0-test" end end,
	IsAddOnLoaded = function(n) return MOCK.loaded[n] or false end,
	GetNumAddOns = function() return #MOCK.addons end,
	GetAddOnInfo = function(i) return MOCK.addons[i] end,
	LoadAddOn = function(n) MOCK.loaded[n] = true end,
}
UpdateAddOnMemoryUsage = function() MOCK.memUpdates = (MOCK.memUpdates or 0) + 1 end
GetAddOnMemoryUsage = function() return 321.5 end
C_AddOnProfiler = {
	IsEnabled = function() return true end,
	GetAddOnMetric = function(_, metric) return metric == 1 and 0.012 or 0.01 end,
	GetOverallMetric = function() return 0.5 end,
	GetTopKAddOnsForMetric = function() return { { addOnName = "OtherAddon", metricValue = 0.3 } } end,
}

-- Player data the modules read
MOCK.xp = { cur = 1500, max = 4000, rested = 800, level = 20, maxLevel = 60 }
UnitXP = function() return MOCK.xp.cur end
UnitXPMax = function() return MOCK.xp.max end
GetXPExhaustion = function() return MOCK.xp.rested end
UnitLevel = function() return MOCK.xp.level end
GetMaxPlayerLevel = function() return MOCK.xp.maxLevel end
IsXPUserDisabled = function() return false end
MOCK.fps, MOCK.net = 60, { 1.5, 0.4, 48, 52 }
GetFramerate = function() return MOCK.fps end
GetNetStats = function() return unpack(MOCK.net) end
GetCVarBool = function() return false end
MOCK.zone = { "Hillsbrad Foothills", "Tarren Mill", "contested" }
GetZoneText = function() return MOCK.zone[1] end
GetSubZoneText = function() return MOCK.zone[2] end
GetMinimapZoneText = function() return MOCK.zone[2] end
GetZonePVPInfo = function() return MOCK.zone[3] end
MOCK.pos = { 0.4523, 0.6311 }
C_Map = {
	GetBestMapForUnit = function() return 1424 end,
	GetPlayerMapPosition = function()
		if MOCK.pos == "secret" then return MOCK.Secret({}) end
		if not MOCK.pos then return nil end
		local x, y = MOCK.pos[1], MOCK.pos[2]
		return { GetXY = function() return x, y end }
	end,
}
UnitOnTaxi = function() return false end
MOCK.dur = { [1] = { 50, 60 }, [5] = { 10, 100 }, [16] = { 70, 70 } }
GetInventoryItemDurability = function(slot) local d = MOCK.dur[slot]; if d then return d[1], d[2] end end
HEADSLOT, CHESTSLOT, MAINHANDSLOT = "Head", "Chest", "Main Hand"
MOCK.mail = false
HasNewMail = function() return MOCK.mail end
GetLatestThreeSenders = function() return "Thrall", "Jaina" end
NUM_BAG_SLOTS = 4
MOCK.quests = 38
C_QuestLog = C_QuestLog or {}
C_QuestLog.GetNumQuestLogEntries = function() return MOCK.quests + 6, MOCK.quests end -- with 6 zone headers
C_QuestLog.GetMaxNumQuestsCanAccept = function() return 45 end
C_QuestLog.GetNumQuestWatches = function() return 2 end
MOCK.bags = { [0] = { 16, 3, 0 }, [1] = { 10, 0, 0 }, [2] = { 12, 5, 32 } } -- slots, free, family
C_Container = {
	GetContainerNumSlots = function(b) local d = MOCK.bags[b]; return d and d[1] or 0 end,
	GetContainerNumFreeSlots = function(b) local d = MOCK.bags[b]; if d then return d[2], d[3] end return 0, 0 end,
	GetBagName = function(b) return b == 2 and "Herb Pouch" or "Bag" end,
}
MOCK.money = 1234567
GetMoney = function() return MOCK.money end
GetGameTime = function() return 20, 15 end

-- Calendar
MOCK.now = { year = 2026, month = 11, monthDay = 30, weekday = 2, hour = 18, minute = 5 }
MOCK.calMonth = { year = 2026, month = 11 }
MOCK.dayEvents = {} -- ["y-m-d"] = { events }
MOCK.calls = {}
C_DateAndTime = { GetCurrentCalendarTime = function() return MOCK.now end }
local function evKey(off, d)
	local m = MOCK.calMonth.month + off
	local y = MOCK.calMonth.year
	while m > 12 do m = m - 12; y = y + 1 end
	return y .. "-" .. m .. "-" .. d
end
C_Calendar = {
	OpenCalendar = function() MOCK.calendarOpened = (MOCK.calendarOpened or 0) + 1 end,
	GetMonthInfo = function() return { year = MOCK.calMonth.year, month = MOCK.calMonth.month, numDays = 30 } end,
	GetNumDayEvents = function(off, d) local l = MOCK.dayEvents[evKey(off, d)]; return l and #l or 0 end,
	GetDayEvent = function(off, d, i) return MOCK.dayEvents[evKey(off, d)][i] end,
	GetNumPendingInvites = function() return MOCK.pending or 0 end,
	ContextMenuSelectEvent = function(off, d, i) table.insert(MOCK.calls, "select " .. evKey(off, d) .. " " .. i) end,
	ContextMenuInviteAvailable = function() table.insert(MOCK.calls, "accept") end,
	ContextMenuInviteTentative = function() table.insert(MOCK.calls, "tentative") end,
	ContextMenuInviteDecline = function() table.insert(MOCK.calls, "decline") end,
	ContextMenuEventSignUp = function() table.insert(MOCK.calls, "signup") end,
	OpenEvent = function() table.insert(MOCK.calls, "openevent") end,
}

function MOCK.Fire(event, ...)
	for _, w in ipairs(MOCK.widgets) do
		if w.__events[event] and w.__scripts.OnEvent then w.__scripts.OnEvent(w, event, ...) end
	end
end

------------------------------------------------------------------------
-- Everlook Pets: a hunter with a pet. Tests change MOCK.pet, MOCK.playerLevel and MOCK.hunterKnows.
------------------------------------------------------------------------
MOCK.class = "HUNTER"
MOCK.playerLevel = 20
MOCK.hunterKnows = {}
MOCK.pet = nil
UnitClass = function(u) if u == "player" then return "Hunter", MOCK.class, 3 end end
UnitExists = function(u) if u == "pet" then return MOCK.pet ~= nil end return true end
UnitName = function(u)
	if u == "pet" then return MOCK.pet and MOCK.pet.name end
	if MOCK.units and MOCK.units[u] then return MOCK.units[u].name end
	return "Tester"
end
UnitCreatureFamily = function(u) if u == "pet" and MOCK.pet then return MOCK.pet.family, MOCK.pet.familyId end end
UnitLevel = function(u) if u == "pet" then return MOCK.pet and MOCK.pet.level end return MOCK.playerLevel end
Enum.SpellBookSpellBank = { Player = 0, Pet = 1 }
local function petSpells()
	local ids = {}
	for id in pairs(MOCK.pet and MOCK.pet.knows or {}) do ids[#ids + 1] = id end
	table.sort(ids)
	return ids
end
C_SpellBook = {
	HasPetSpells = function() if not MOCK.pet then return nil end return #petSpells(), "PET" end,
	GetSpellBookItemInfo = function(i, bank)
		if bank ~= 1 then return nil end
		local id = petSpells()[i]
		if id then return { spellID = id, actionID = id, name = "spell " .. id, itemType = 1 } end
	end,
	IsSpellKnown = function(id, bank)
		if bank == 1 then return MOCK.pet and MOCK.pet.knows[id] or false end
		return MOCK.hunterKnows[id] or false
	end,
}
C_PetInfo = {
	GetPetHappiness = function() if MOCK.pet then return 3, 125, 1 end end,
	GetPetLoyalty = function() if MOCK.pet then return "Loyalty Level 3 (Dependable)" end end,
	GetPetTrainingPoints = function() return 120, 45 end,
	GetPetFoodTypes = function() return MOCK.pet and { "Meat", "Fish" } or {} end,
}
C_Spell = { GetSpellName = function() return nil end, GetSpellTexture = function() return 136000 end }
C_StableInfo = {
	GetActivePetList = function() return MOCK.stableActive end,
	GetStabledPetList = function() return MOCK.stabled end,
}

-- Everlook Pets 0.3: units around you, the map, waypoints, sounds and the world map canvas.
MOCK.units = {} -- [unit] = { guid, class (classification), dead }
MOCK.petGUID = nil
UnitGUID = function(u)
	if u == "pet" then return MOCK.pet and MOCK.petGUID or nil end
	local d = MOCK.units[u]
	return d and d.guid
end
UnitClassification = function(u) local d = MOCK.units[u]; return d and d.class or "normal" end
UnitIsDead = function(u) local d = MOCK.units[u]; return d and d.dead or false end
MOCK.mapInfo = { [1424] = { name = "Hillsbrad Foothills", mapType = 3, parentMapID = 1415 }, [1415] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 947 } }
C_Map.GetMapInfo = function(id) return MOCK.mapInfo[id] end
C_Map.CanSetUserWaypointOnMap = function(id) return type(id) == "number" and id > 0 end
C_Map.SetUserWaypoint = function(p) MOCK.waypoint = p; return true end
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) MOCK.superTracked = on end }
C_Sound = { PlaySound = function(id) MOCK.sounds = (MOCK.sounds or 0) + 1; MOCK.lastSound = id; return true end }

-- The map canvas, as far as an addon's data provider and pins use it.
function CreateFromMixins(...)
	local t = {}
	for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do t[k] = v end end
	return t
end
MapCanvasDataProviderMixin = {
	GetMap = function(self) return self.owningMap end,
	OnAdded = function(self, map) self.owningMap = map end,
	RefreshAllData = function() end,
	RemoveAllData = function() end,
}
MapCanvasPinMixin = {
	SetPosition = function(self, x, y) self.normalizedX, self.normalizedY = x, y end,
	OnLoad = function() end,
}
WorldMapFrame = newWidget("Frame", "WorldMapFrame", UIParent)
WorldMapFrame.ScrollContainer = newWidget("Frame", nil, WorldMapFrame)
WorldMapFrame.__shown = false
WorldMapFrame.mapID = 1429
WorldMapFrame.providers = {}
WorldMapFrame.pins = {}
function WorldMapFrame:AddDataProvider(p) table.insert(self.providers, p); p:OnAdded(self) end
function WorldMapFrame:GetMapID() return self.mapID end
function WorldMapFrame:RemoveAllPinsByTemplate(t) for _, pin in ipairs(self.pins) do pin:Hide() end; self.pins = {} end
function WorldMapFrame:AcquirePin(template, ...)
	local pin = newWidget("Frame", nil, self.ScrollContainer)
	local mixin = _G[template:gsub("Template$", "Mixin")]
	for k, v in pairs(mixin) do pin[k] = v end
	pin:OnLoad()
	pin:OnAcquired(...)
	table.insert(self.pins, pin)
	return pin
end
