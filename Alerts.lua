-- Everlook Pets: telling you when something becomes actionable. A chat line once per change (a new rank opened, you
-- learned a rank your pet lacks), a count on the minimap button and on the LibDataBroker plugin (Everlook Bar,
-- Titan Panel, ChocolateBar...) until you open the window, and a note when your pet falls behind your level.
local _, ns = ...
local Logic = ns.Logic
local A = {}
ns.Alerts = A

local GOLD, GREEN, MUTED, ORANGE = "|cffffd200", "|cff62cf88", "|cff8d94a3", "|cffff9f40"

-- How many rows of the current pet you haven't seen in the window yet.
function A:Unseen()
	local st = ns.state
	local p = st.pet
	local list = p and ns.cdb and ns.cdb.unseen[p.key]
	local n = 0
	for _ in pairs(list or {}) do n = n + 1 end
	return n
end

-- Opening the window counts as seeing them.
function A:MarkSeen()
	local p = ns.state.pet
	if p and ns.cdb then ns.cdb.unseen[p.key] = nil end
	self:Draw()
end

function A:Check(st)
	local p, res = st.pet, st.result
	if not (p and res and res.family and ns.cdb) then self:Draw() return end
	-- the pet's spellbook isn't filled yet (just summoned, just logged in): wait for the next update
	if (p.spellCount or 0) == 0 and next(p.knows) == nil then self:Draw() return end
	local key = p.key
	local prev = ns.cdb.alerted[key]
	local news, now = Logic.Diff(prev, res.rows)
	ns.cdb.alerted[key] = now
	local unseen = ns.cdb.unseen[key] or {}
	for k in pairs(unseen) do if not now[k] then unseen[k] = nil end end
	for _, row in ipairs(news) do unseen[row.key] = true end
	ns.cdb.unseen[key] = next(unseen) and unseen or nil

	if ns.db.chat and #news > 0 then
		local who = p.name or "Your pet"
		if prev == nil or #news > 3 then
			-- a pet seen for the first time (or a big change): one line, not a wall
			ns:Print(("%s: %d thing%s to do for its abilities. %s shows them."):format(who, #news, #news == 1 and "" or "s", ns.SLASH))
		else
			for _, row in ipairs(news) do ns:Print(who .. ": " .. Logic.ChatLine(row)) end
		end
	end

	-- the pet lagging behind: once when it starts, again only after it caught up
	local lagText = Logic.LagText(res.lag, ns.db.lagWarn)
	if lagText and not ns.cdb.lagNoted[key] and ns.db.chat then
		ns:Print(lagText .. ". Pets learn faster from kills near their own level.")
	end
	ns.cdb.lagNoted[key] = lagText and true or nil
	self:Draw()
end

------------------------------------------------------------------------
-- A rare tameable beast, or one on your wishlist, is near: one chat line (and a sound), at most once in
-- A.NEAR_AGAIN seconds per beast. Seen through nameplates (enemy nameplates on), your target and your mouse-over.
------------------------------------------------------------------------
A.NEAR_AGAIN = 300
A.nearSaid = {}

-- What to say about this beast near you, or nil. npc id, classification (the game's word), your level, wished.
function A.NearLine(npc, classification, playerLevel, wished)
	local e = ns.Bestiary.Get(ns.Data, npc)
	if not e then return nil end
	local rare = classification == "rare" or classification == "rareelite" or (classification == nil and e.rare)
	if not ((rare and ns.db.rareAlert) or (wished and ns.db.wishAlert)) then return nil end
	local what = (rare and "rare " or "") .. (ns.FamilyName(e.family) or e.famKey)
	local s = ("%s (%s, level %s) is near"):format(e.name, what, ns.Bestiary.Levels(e))
	if wished then s = s .. ", and it's on your wishlist" end
	if playerLevel and e.lo > playerLevel then s = s .. (". Too high for you until level %d"):format(e.lo) end
	return s .. ". /tar " .. e.name
end

function A:SeeUnit(unit)
	if not (ns.db and ns.state.hunter) then return end
	-- in combat and instances the game may hide these (secret values): then we skip the unit
	local npc = ns.NpcId and ns.NpcId(ns.Str((ns.Call(UnitGUID, unit))))
	if not npc or ns.Bool((ns.Call(UnitIsDead, unit))) ~= false then return end
	local now = ns.Num((ns.Call(GetTime))) or 0
	local last = self.nearSaid[npc]
	if last and now - last < self.NEAR_AGAIN then return end
	local line = self.NearLine(npc, ns.Str((ns.Call(UnitClassification, unit))), ns.state.playerLevel, ns.IsWished(npc))
	if not line then return end
	self.nearSaid[npc] = now
	ns:Print(GOLD .. line .. "|r")
	if ns.db.alertSound then
		local play = ns.api("C_Sound", "PlaySound")
		if not ns.Call(play, 8959, "SFX") then ns.Call(_G.PlaySound, 8959, "Master") end -- the raid warning sound
	end
end

ns.On("NAME_PLATE_UNIT_ADDED", function(_, unit) A:SeeUnit(unit) end)
ns.On("PLAYER_TARGET_CHANGED", function() A:SeeUnit("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() A:SeeUnit("mouseover") end)

------------------------------------------------------------------------
-- Summary text, shared by the plugin, the minimap button and its tooltip
------------------------------------------------------------------------
function A:Summary()
	local st = ns.state
	if not st.hunter then return "Hunters only" end
	local p = st.pet
	if not p then return MUTED .. "No pet|r" end
	local s = (p.name or "Pet") .. " " .. (p.level or "?")
	local res = st.result
	if res and res.lag and ns.db and ns.db.lagWarn > 0 and res.lag >= ns.db.lagWarn then s = s .. " " .. ORANGE .. "(-" .. res.lag .. ")|r" end
	local todo, unseen = res and res.todo or 0, self:Unseen()
	if unseen > 0 then
		s = s .. " " .. GOLD .. unseen .. " new|r"
	elseif todo > 0 then
		s = s .. " " .. MUTED .. todo .. " to do|r"
	end
	return s
end

function A:Tooltip(tip)
	local st = ns.state
	tip:AddLine(ns.NAME, 1, 1, 1)
	if not st.hunter then tip:AddLine("For hunters: your pet's abilities and ranks.", nil, nil, nil, true) return end
	local p, res = st.pet, st.result
	if not p then
		tip:AddLine("Summon your pet to see its abilities.", nil, nil, nil, true)
	else
		tip:AddDoubleLine((p.name or "Pet") .. (p.familyName and (" (" .. p.familyName .. ")") or ""),
			"Level " .. (p.level or "?") .. (st.playerLevel and (" / you " .. st.playerLevel) or ""), 1, 1, 1, 1, 1, 1)
		local lag = res and Logic.LagText(res.lag, ns.db.lagWarn)
		if lag then tip:AddLine(lag .. ".", 1, 0.62, 0.25) end
		local shown = 0
		for _, row in ipairs(res and res.rows or {}) do
			if row.actionable and shown < 8 then
				tip:AddLine(GOLD .. row.name .. "|r  " .. (Logic.Describe(row)), 0.85, 0.85, 0.85, true)
				shown = shown + 1
			end
		end
		if res and res.family and shown == 0 then tip:AddLine(GREEN .. "Nothing to do: every ability is as good as its level allows.|r", nil, nil, nil, true) end
	end
	tip:AddLine(" ")
	tip:AddLine(MUTED .. "Click: open " .. ns.NAME .. "|r")
end

------------------------------------------------------------------------
-- LibDataBroker plugin (shown by any data-broker display, Everlook Bar included)
------------------------------------------------------------------------
local ldb
function A:SetupBroker()
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	if not LDB or ldb then return end
	ldb = LDB:NewDataObject(ns.PREFIX, {
		type = "data source", label = "Pet", text = "", icon = ns.ICON,
		OnClick = function() if ns.app then ns.app:Toggle() end end,
		OnTooltipShow = function(tip) A:Tooltip(tip) end,
	})
end

------------------------------------------------------------------------
-- Minimap button: drag it around the minimap; the count shows what's new
------------------------------------------------------------------------
local button
local function place()
	if not button or not Minimap then return end
	local a = math.rad(ns.db.angle or 200)
	local r = (Minimap:GetWidth() or 140) / 2 + 10
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

function A:SetupMinimap()
	if button or not Minimap then return end
	local b = CreateFrame("Button", ns.PREFIX .. "MinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("AnyUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(17, 17)
	b.icon:SetPoint("TOPLEFT", 7, -6)
	b.icon:SetTexture(ns.ICON)
	b.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")
	-- the count: a small gold circle with a number
	b.badge = CreateFrame("Frame", nil, b)
	b.badge:SetSize(14, 14)
	b.badge:SetPoint("TOPRIGHT", 2, 2)
	b.badge:SetFrameLevel(b:GetFrameLevel() + 2)
	local dot = b.badge:CreateTexture(nil, "ARTWORK")
	dot:SetAllPoints()
	dot:SetTexture("Interface\\COMMON\\Indicator-Yellow")
	b.badge.text = b.badge:CreateFontString(nil, "OVERLAY")
	b.badge.text:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
	b.badge.text:SetPoint("CENTER", 0, 0)
	b.badge:Hide()
	b:SetScript("OnClick", function() if ns.app then ns.app:Toggle() end end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		A:Tooltip(GameTooltip)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	b:SetScript("OnDragStart", function(self)
		-- collected by a button drawer (Everlook Bar, MinimapButtonBag...): it is not ours to move around the minimap
		if self:GetParent() ~= Minimap then return end
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			if not (mx and cx) then return end
			ns.db.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx)) % 360
			place()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	button = b
	place()
end

-- Show the current summary everywhere.
function A:Draw()
	if ldb then
		ldb.text = self:Summary()
		local fam = ns.state.result and ns.state.result.family
		ldb.icon = fam and fam.icon or ns.ICON
	end
	local want = ns.db and ns.ShowMinimapButton() and ns.state.hunter and true or false
	if not button and want then self:SetupMinimap() end
	if button then
		button:SetShown(want)
		local n = self:Unseen()
		button.badge:SetShown(n > 0)
		button.badge.text:SetText(n > 9 and "9+" or tostring(n))
		local fam = ns.state.result and ns.state.result.family
		button.icon:SetTexture(fam and fam.icon or ns.ICON)
	end
end
