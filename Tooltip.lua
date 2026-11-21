-- Everlook Pets: a "Tameable" line on wild beasts' tooltips (hunters only): the family, its level, what that family
-- can learn, and, from EverlookDB's bestiary, what this beast teaches when tamed ("Teaches: Bite 2 · Claw 3") with
-- how sure that is (confirmed, seen in WoW Forever, or classic data).
-- Uses the shared EverlookTooltip layout, so its lines sit with the other EverlookDB addons' lines.
local _, ns = ...
local Tip = LibStub and LibStub("EverlookTooltip-1", true)
if not Tip then return end

-- The npc id inside a creature's GUID ("Creature-0-1-0-1-681-0000ABCDEF" -> 681).
function ns.NpcId(guid)
	if type(guid) ~= "string" or not ns.Str(guid) then return nil end -- a secret GUID (combat, instances): unknown
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind ~= "Creature" then return nil end
	return tonumber(id)
end

-- The lines for one beast, as { label, value, note, learns, teaches, teachesFrom, tooHigh }; nil when it isn't tameable.
function ns.TameLines(npcId, familyName, playerLevel)
	local info = npcId and ns.Data.tameable[npcId]
	local beast = npcId and ns.Data.beasts and ns.Data.beasts[npcId]
	if not info and beast then
		-- tameable as far as the bestiary knows (players tamed it, or classic data): family from the game's tooltip
		for fid, f in pairs(ns.Data.families) do
			if f.key == familyName then info = { fid, beast[1], beast[2] } end
		end
	end
	if not info then return nil end
	local fam = ns.Data.families[info[1]]
	if not fam then return nil end
	local lo, hi = info[2] or 0, info[3] or 0
	-- WoW Forever's new beasts may have no level in our data yet (0): say nothing rather than "level 0"
	local note = lo > 0 and ("level " .. lo .. ((hi > lo) and ("-" .. hi) or "")) or nil
	local out = { label = "Tameable", value = familyName or fam.key, note = note }
	local learns = {}
	for _, key in ipairs(fam.abilities) do
		local ab = ns.Data.abilities[key]
		if ab and not ab.trainer then learns[#learns + 1] = ns.AbilityName(ab) end
	end
	out.learns = table.concat(learns, ", ")
	out.teaches, out.teachesFrom = ns.Logic.TeachesText(ns.Data, npcId, ns.AbilityName)
	if playerLevel and lo > playerLevel then out.tooHigh = lo end
	out.tamed = ns.cdb and ns.cdb.tamed and ns.cdb.tamed[npcId] or nil
	out.wished = ns.IsWished(npcId)
	return out
end

Tip:Register({
	id = "everlookpets.tameable", kind = "unit", order = Tip.ORDER.source,
	add = function(t, ctx)
		if not (ns.db and ns.db.tooltip and ns.state.hunter) then return end
		local unit = ctx.unit
		local fam = unit and ns.Str((ns.Call(UnitCreatureFamily, unit)))
		local lines = ns.TameLines(ns.NpcId(ctx.guid), fam, ns.state.playerLevel)
		if not lines then return end
		t:Line(lines.label, lines.value, { note = lines.note })
		if lines.tooHigh then t:Detail("Too high for you until level " .. lines.tooHigh, nil, { always = true }) end
		if lines.tamed or lines.wished then
			t:Detail(lines.tamed and "Tamed by you" or "On your wishlist", lines.tamed and lines.wished and "on your wishlist" or nil, { always = true })
		end
		if lines.teaches then
			local mark = ns.Logic.STATE_LABEL[lines.teachesFrom] or lines.teachesFrom
			t:Line("Teaches", lines.teaches, { note = mark })
		else
			t:Detail("Teaches", "not reported yet")
		end
		if lines.learns ~= "" then t:Detail("Its family learns", lines.learns) end
	end,
})
