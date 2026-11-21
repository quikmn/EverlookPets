-- EverlookDB Pets: a list of row cards for the bestiary and the pet page (EverlookUI's look: a card a shade lighter
-- than the window, an icon on the left, a white title, muted lines under it, small rank chips, plain buttons on the
-- right). Long lists show a page at a time with a "Show more" button.
--   ns.Cards(stack, opt) with opt:
--     items() -> array; icon(item); title(item); sub(item) (second line); chips(item) -> { { text, edge = {r,g,b},
--     color = {r,g,b}, tip = { lines }, onClick(chip) } } (third line, as many as fit); star = { get(item), set(item, on), tip }; buttons = { { label | fn(item),
--     width, onClick(item), shown(item) } }; onClick(item); tooltip(item) -> lines; empty; rowHeight; page (rows
--     per page, default 40); titleLines (the title may wrap to this many lines, default 1).
--   The returned frame has :Refresh() and :ResetPage() (back to the first page, after the search changed).
local _, ns = ...
local UI = ns.UI
local U = UI.Util

local STAR = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" -- the raid marker star

local function rgba(c) return c[1], c[2], c[3], c[4] or 1 end

local function textWidth(fs)
	return (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
end

function ns.Cards(stack, opt)
	local T = stack.T
	local f = CreateFrame("Frame")
	f:SetParent(stack.parent)
	f.rows = {}
	local rowH = opt.rowHeight or (opt.chips and 58 or 44)
	local pageSize = opt.page or 40
	local limit = pageSize
	local empty = UI.Text(f, T.font, T.muted)
	empty:SetPoint("TOPLEFT", 4, -4)
	empty:SetWidth(stack.width - 8)
	local more = UI.Button(f, "Show more", function()
		limit = limit + pageSize
		f:Refresh()
	end, 160)
	more:Hide()

	local function chip(r, i)
		local c = r.chips[i]
		if c then return c end
		c = CreateFrame("Frame", nil, r)
		c:SetHeight(16)
		c.bg = U.Solid(c, "BACKGROUND", rgba(T.surfaceHi))
		c.bg:SetAllPoints()
		c.border = U.Border(c, 1, rgba(T.border))
		c.text = UI.Text(c, T.fontSmall, T.text)
		c.text:SetPoint("CENTER", 0, 0)
		c.text:SetWordWrap(false)
		c:SetScript("OnMouseUp", function(self) if self.data and self.data.onClick then self.data.onClick(self.data) end end)
		c:SetScript("OnEnter", function(self)
			self.bg:SetVertexColor(rgba(T.border))
			local d = self.data
			if d and d.tip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				for li, line in ipairs(d.tip) do
					if li == 1 then GameTooltip:AddLine(line, 1, 1, 1) else GameTooltip:AddLine(line, nil, nil, nil, true) end
				end
				GameTooltip:Show()
			end
		end)
		c:SetScript("OnLeave", function(self) self.bg:SetVertexColor(rgba(T.surfaceHi)); GameTooltip:Hide() end)
		r.chips[i] = c
		return c
	end

	local function newRow(i)
		local r = CreateFrame("Button", nil, f)
		r:SetHeight(rowH)
		r:SetPoint("TOPLEFT", 0, -(i - 1) * (rowH + 4))
		r:SetPoint("RIGHT")
		r.bg = U.Solid(r, "BACKGROUND", rgba(T.surface))
		r.bg:SetAllPoints()
		r.chips = {}
		local x = 10
		if opt.icon then
			r.icon = r:CreateTexture(nil, "ARTWORK")
			r.icon:SetSize(28, 28)
			r.icon:SetPoint("TOPLEFT", x, -8)
			r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
			x = x + 38
		end
		local right = -8
		if opt.star then
			local s = CreateFrame("Button", nil, r)
			s:SetSize(20, 20)
			s:SetPoint("TOPRIGHT", right, -8)
			s.tex = s:CreateTexture(nil, "ARTWORK")
			s.tex:SetAllPoints()
			s.tex:SetTexture(STAR)
			s:SetScript("OnClick", function()
				if r.item == nil then return end
				opt.star.set(r.item, not opt.star.get(r.item))
				stack:RefreshAll()
			end)
			s:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				local on = r.item ~= nil and opt.star.get(r.item)
				GameTooltip:AddLine(on and "On your wishlist" or "Add to your wishlist", 1, 1, 1)
				if opt.star.tip then GameTooltip:AddLine(opt.star.tip, nil, nil, nil, true) end
				GameTooltip:Show()
			end)
			s:SetScript("OnLeave", function() GameTooltip:Hide() end)
			r.star = s
			right = right - 28
		end
		r.buttons = {}
		r.btnRight = right
		for bi = #(opt.buttons or {}), 1, -1 do
			local d = opt.buttons[bi]
			local b = UI.Button(r, type(d.label) == "string" and d.label or "", function(btn) if r.item ~= nil then d.onClick(r.item, btn) end end, d.width or 80)
			b:SetHeight(22)
			b:SetPoint("TOPRIGHT", right, -8)
			right = right - (d.width or 80) - 6
			r.buttons[bi] = b
		end
		r.title = UI.Text(r, T.font, T.text)
		r.title:SetWordWrap((opt.titleLines or 1) > 1)
		if (opt.titleLines or 1) > 1 and r.title.SetMaxLines then r.title:SetMaxLines(opt.titleLines) end
		r.title:SetJustifyH("LEFT")
		r.title:SetPoint("TOPLEFT", x, -8)
		r.title:SetPoint("RIGHT", right - 4, 0)
		r.sub = UI.Text(r, T.fontSmall + 1, T.muted)
		r.sub:SetWordWrap(false)
		r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -4)
		r.sub:SetPoint("RIGHT", right - 4, 0) -- clear of the star and the buttons, like the title
		r.chipX = x
		r:SetScript("OnEnter", function(self)
			self.bg:SetVertexColor(rgba(T.surfaceHi))
			if self.item == nil or not opt.tooltip then return end
			local tip = opt.tooltip(self.item)
			if type(tip) == "table" and #tip > 0 then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				for li, line in ipairs(tip) do
					if li == 1 then GameTooltip:AddLine(line, 1, 1, 1) else GameTooltip:AddLine(line, nil, nil, nil, true) end
				end
				GameTooltip:Show()
			end
		end)
		r:SetScript("OnLeave", function(self)
			self.bg:SetVertexColor(rgba(T.surface))
			GameTooltip:Hide()
		end)
		r:SetScript("OnClick", function(self) if self.item ~= nil and opt.onClick then opt.onClick(self.item) end end)
		f.rows[i] = r
		return r
	end

	local function fillChips(r, list)
		local x, room = r.chipX, (stack.width or 500) - r.chipX - 12
		local shown = 0
		for i, d in ipairs(list or {}) do
			local c = chip(r, i)
			c.data = d
			c:EnableMouse((d.onClick or d.tip) and true or false)
			c.text:SetText(d.text or "")
			c.text:SetTextColor(rgba(d.color or T.text))
			c.border:SetColor(rgba(d.edge or T.border))
			local w = math.floor(textWidth(c.text) + 12)
			if x - r.chipX + w > room then
				c:Hide()
			else
				c:SetWidth(w)
				c:ClearAllPoints()
				c:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 8)
				c:Show()
				x = x + w + 4
				shown = shown + 1
			end
		end
		for i = #(list or {}) + 1, #r.chips do r.chips[i]:Hide() end
		return shown
	end

	function f:ResetPage() limit = pageSize end

	function f:Refresh()
		local items = opt.items() or {}
		local n = math.min(#items, limit)
		for i = 1, n do
			local item = items[i]
			local r = f.rows[i] or newRow(i)
			r.item = item
			r.title:SetText(opt.title(item) or "")
			r.sub:SetText(opt.sub and opt.sub(item) or "")
			if r.icon then
				local icon = opt.icon(item)
				r.icon:SetShown(icon ~= nil)
				if icon then r.icon:SetTexture(icon) end
			end
			if r.star then
				local on = opt.star.get(item) and true or false
				if r.star.tex.SetDesaturated then r.star.tex:SetDesaturated(not on) end
				r.star.tex:SetAlpha(on and 1 or 0.3)
			end
			-- the shown buttons sit together on the right (a hidden one leaves no gap), the text runs up to them
			local right = r.btnRight
			for bi = #(opt.buttons or {}), 1, -1 do
				local d, b = opt.buttons[bi], r.buttons[bi]
				if type(d.label) == "function" then b:SetText(d.label(item)) end
				local show = not d.shown or d.shown(item) and true or false
				b:SetShown(show)
				if show then
					b:ClearAllPoints()
					b:SetPoint("TOPRIGHT", right, -8)
					right = right - (d.width or 80) - 6
				end
			end
			if opt.buttons then
				r.title:SetPoint("RIGHT", right - 4, 0)
				r.sub:SetPoint("RIGHT", right - 4, 0)
			end
			if opt.chips then fillChips(r, opt.chips(item)) end
			r:Show()
		end
		for i = n + 1, #f.rows do f.rows[i].item = nil; f.rows[i]:Hide() end
		empty:SetText(type(opt.empty) == "function" and opt.empty() or opt.empty or "Nothing here.")
		empty:SetShown(n == 0)
		-- an empty text may wrap to two lines: give it its room
		local h = n == 0 and math.max(24, math.ceil((empty:GetStringHeight() or 0) + 8)) or n * (rowH + 4)
		if #items > n then
			more:SetText(("Show more (%d left)"):format(#items - n))
			more:ClearAllPoints()
			more:SetPoint("TOPLEFT", 0, -h - 4)
			more:Show()
			h = h + 34
		else
			more:Hide()
		end
		f.shownCount, f.total = n, #items
		stack:SetHeightOf(f, h)
	end
	stack:Add(f, 24)
	f:Refresh()
	return f
end
