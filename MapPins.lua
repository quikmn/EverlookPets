-- EverlookDB Pets: "Tameable beasts" on the world map. A pin where a beast spawns that teaches a rank your pet lacks
-- (one its level allows, not sold by pet trainers) and that you can tame at your level. The pin is the beast's family
-- icon; its edge says how sure the rank is (green confirmed, white seen in WoW Forever, grey classic data). Hover for
-- what it teaches, click for its page in /epets. A switch on the map and the "map" setting turn the pins off.
--
-- The world map is Blizzard's map canvas (Blizzard_MapCanvas, Blizzard_WorldMap in the WoW Forever client): a data
-- provider (WorldMapFrame:AddDataProvider) acquires pins from MapPins.xml's template. When the client lacks any of it,
-- nothing is added and /epets status says so.
local _, ns = ...
local B = ns.Bestiary
local MP = {}
ns.MapPins = MP

MP.TEMPLATE = "EverlookPetsBeastPinTemplate"

local function canvasReady()
	local w = _G.WorldMapFrame
	return type(w) == "table" and type(w.AddDataProvider) == "function" and type(_G.CreateFromMixins) == "function"
		and type(_G.MapCanvasDataProviderMixin) == "table" and type(_G.MapCanvasPinMixin) == "table"
end

function MP:Enabled() return ns.db and ns.db.mapPins and ns.state.hunter and true or false end

-- The pins for one map: { { entry, spot, ranks } } (B.PinsOn), or none without a pet.
function MP.Pins(map)
	local st = ns.state
	if not (st.hunter and st.result and st.result.family and map) then return {} end
	local missing = B.Missing(ns.Data, st.result, ns.HunterKnows)
	return B.PinsOn(ns.Data, map, missing, st.playerLevel)
end

-- The note beside the map's switch: pins live on zone maps, so a continent or the world map says where to look.
-- mapType: the game's (0 cosmic, 1 world, 2 continent, 3 zone...). Returns the text or nil.
function MP.Hint(mapType, enabled)
	if not enabled or type(mapType) ~= "number" then return nil end
	if mapType <= 2 then return "Open a zone's map to see tameable beasts." end
	return nil
end

-- The surest state among a pin's ranks decides its edge colour (one confirmed rank makes the trip worth it; the
-- tooltip lists each rank with its own state).
local EDGE = { confirmed = { 0.384, 0.812, 0.533 }, seen = { 0.902, 0.910, 0.933 }, classic = { 0.553, 0.580, 0.639 } }
local SURE = { confirmed = 3, seen = 2, classic = 1 }
function MP.Edge(ranks)
	local best
	for _, t in ipairs(ranks or {}) do
		if not best or (SURE[t.state] or 0) > (SURE[best] or 0) then best = t.state end
	end
	return EDGE[best or "classic"] or EDGE.classic, best
end

function MP.TooltipLines(info)
	local e = info.entry
	local lines = { e.name, (ns.FamilyName(e.family) or e.famKey) .. ", level " .. B.Levels(e)
		.. (B.RANK_WORD[e.rank] and (", " .. B.RANK_WORD[e.rank]) or "") }
	for _, t in ipairs(info.ranks) do
		local ab = ns.Data.abilities[t.key]
		lines[#lines + 1] = "|cffffd200" .. ((ab and ns.AbilityName(ab)) or t.key) .. " " .. t.rank .. "|r  |cff8d94a3"
			.. (ns.Logic.STATE_LABEL[t.state] or t.state) .. "|r"
	end
	if B.OldSpot(info.spot) then
		lines[#lines + 1] = "|cff8d94a3Older data (classic spawn points): WoW Forever players haven't seen it here yet, so it may be wrong.|r"
	end
	lines[#lines + 1] = "|cff8d94a3Your pet lacks these ranks. Click for its page in " .. ns.SLASH .. ".|r"
	return lines
end

------------------------------------------------------------------------
-- The pin (MapPins.xml makes the template; this is its mixin)
------------------------------------------------------------------------
-- A plain table now: the map canvas may load after us. Setup gives it MapCanvasPinMixin's functions (the template
-- applies the mixin by name when a pin is made, which is after that).
local PinMixin = {}
_G.EverlookPetsBeastPinMixin = PinMixin

function PinMixin:OnLoad()
	self:SetSize(18, 18)
	self.ring = self:CreateTexture(nil, "BACKGROUND")
	self.ring:SetPoint("TOPLEFT", -1, 1)
	self.ring:SetPoint("BOTTOMRIGHT", 1, -1)
	self.ring:SetTexture("Interface\\Buttons\\WHITE8X8")
	self.icon = self:CreateTexture(nil, "ARTWORK")
	self.icon:SetAllPoints()
	self.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	self:EnableMouse(true)
	if self.UseFrameLevelType then pcall(self.UseFrameLevelType, self, "PIN_FRAME_LEVEL_AREA_POI") end
	if self.SetScalingLimits then pcall(self.SetScalingLimits, self, 1, 1.0, 1.25) end
	self:SetScript("OnMouseUp", function(pin, button)
		if button == "LeftButton" and pin.info then ns.Browser.OpenBeast(pin.info.entry) end
	end)
end

function PinMixin:OnAcquired(info)
	self.info = info
	local fam = ns.Data.families[info.entry.family]
	self.icon:SetTexture(fam and fam.icon or ns.ICON)
	local c = MP.Edge(info.ranks)
	self.ring:SetVertexColor(c[1], c[2], c[3], 1)
	self:SetPosition(info.spot.x, info.spot.y)
end

function PinMixin:OnMouseEnter()
	if not self.info then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	for i, line in ipairs(MP.TooltipLines(self.info)) do
		if i == 1 then GameTooltip:AddLine(line, 1, 1, 1) else GameTooltip:AddLine(line, nil, nil, nil, true) end
	end
	GameTooltip:Show()
end

function PinMixin:OnMouseLeave() GameTooltip:Hide() end

------------------------------------------------------------------------
-- The data provider and the switch on the map
------------------------------------------------------------------------
function MP:Setup()
	if self.provider or not canvasReady() then return self.provider ~= nil end
	local map = _G.WorldMapFrame
	for k, v in pairs(_G.MapCanvasPinMixin) do if PinMixin[k] == nil then PinMixin[k] = v end end
	local P = _G.CreateFromMixins(_G.MapCanvasDataProviderMixin)
	function P:RemoveAllData()
		self:GetMap():RemoveAllPinsByTemplate(MP.TEMPLATE)
	end
	function P:RefreshAllData()
		self:RemoveAllData()
		local id = self:GetMap():GetMapID()
		MP:ShowHint(id)
		if not MP:Enabled() then return end
		for _, info in ipairs(MP.Pins(id)) do self:GetMap():AcquirePin(MP.TEMPLATE, info) end
	end
	local ok = pcall(map.AddDataProvider, map, P)
	if not ok then return false end
	self.provider = P
	-- the switch: bottom left of the map, plain (the map's own buttons stay the main ones)
	local parent = map.ScrollContainer or map
	local b = ns.UI.Button(parent, "", function()
		ns.db.mapPins = not ns.db.mapPins
		MP:Refresh()
	end, 150)
	b:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 8, 8)
	b:SetFrameLevel((parent:GetFrameLevel() or 1) + 20)
	ns.UI.Tooltip(b, "Tameable beasts (" .. ns.NAME .. ")", "Pins where beasts spawn that teach a rank your pet lacks and that you "
		.. "can tame at your level. Edge: green confirmed, white seen in WoW Forever, grey classic data.")
	self.switch = b
	-- the small note beside it (continent and world maps have no pins)
	local hint = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", b, "RIGHT", 8, 0)
	hint:SetTextColor(0.85, 0.87, 0.9, 1)
	hint:Hide()
	self.hint = hint
	self:Refresh()
	return true
end

function MP:ShowHint(mapId)
	if not self.hint then return end
	local mi = mapId and ns.Call(ns.api("C_Map", "GetMapInfo"), mapId)
	local text = MP.Hint(type(mi) == "table" and ns.Num(mi.mapType) or nil, MP:Enabled())
	self.hint:SetText(text or "")
	self.hint:SetShown(text ~= nil)
end

function MP:Refresh()
	if self.switch then
		self.switch:SetText("Tameable beasts: " .. (ns.db and ns.db.mapPins and "on" or "off"))
		self.switch:SetShown(ns.state.hunter and true or false)
	end
	local map = _G.WorldMapFrame
	if self.provider and type(map) == "table" and map:IsShown() then pcall(self.provider.RefreshAllData, self.provider) end
end

function MP:Status()
	if self.provider then return "World map pins: ready (" .. (ns.db.mapPins and "on" or "off") .. ")." end
	return "World map pins: this client's world map takes no pins from addons."
end

ns.On("PLAYER_LOGIN", function() if ns.IsHunter() then MP:Setup() end end)
ns.On("ADDON_LOADED", function(_, name) if name == "Blizzard_WorldMap" and ns.IsHunter() then MP:Setup() end end)
