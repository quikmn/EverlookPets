-- Everlook Pets: a "Tameable" line on wild beasts' tooltips (hunters only): the family, its level, and what that
-- family can learn. Which ranks a single beast knows is not in our data (see README), so it doesn't guess.
-- Uses the shared EverlookTooltip layout, so its lines sit with the other EverlookDB addons' lines.
local _, ns = ...
local Tip = LibStub and LibStub("EverlookTooltip-1", true)
if not Tip then return end

-- The npc id inside a creature's GUID ("Creature-0-1-0-1-681-0000ABCDEF" -> 681).
function ns.NpcId(guid)
	if type(guid) ~= "string" then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind ~= "Creature" then return nil end
	return tonumber(id)
end

-- The lines for one beast, as { label, value, note, details }; nil when it isn't tameable.
function ns.TameLines(npcId, familyName, playerLevel)
	local info = npcId and ns.Data.tameable[npcId]
	if not info then return nil end
	local fam = ns.Data.families[info[1]]
	if not fam then return nil end
	local lo, hi = info[2], info[3]
	local out = { label = "Tameable", value = familyName or fam.key, note = "level " .. lo .. ((hi > lo) and ("-" .. hi) or "") }
	local learns = {}
	for _, key in ipairs(fam.abilities) do
		local ab = ns.Data.abilities[key]
		if ab and not ab.trainer then learns[#learns + 1] = ns.AbilityName(ab) end
	end
	out.learns = table.concat(learns, ", ")
	if playerLevel and lo > playerLevel then out.tooHigh = lo end
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
		if lines.learns ~= "" then t:Detail("Its family learns", lines.learns) end
	end,
})
