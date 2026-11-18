-- LibDataBroker-1.1, an independent implementation written for Everlook Bar (GPL-3.0, like the rest of the addon).
--
-- Why not the usual file: the widely shared LibDataBroker-1.1.lua has no licence file in its repository and its
-- project pages say "All Rights Reserved", so Everlook Bar does not ship it. This file implements the same public
-- interface (the LDB 1.1 data specification: NewDataObject, DataObjectIterator, GetDataObjectByName,
-- GetNameByDataObject, pairs, ipairs and the four LibDataBroker_* callbacks) under the same LibStub name and minor
-- version, so every LDB plugin and display works with it, and whichever copy loads first is the one all addons share.
-- The storage tables keep the names other copies use (attributestorage, namestorage, proxystorage, domt), so an
-- older copy that loaded first upgrades into this one without losing data objects.
assert(LibStub, "LibDataBroker-1.1 needs LibStub")
local CBH = LibStub:GetLibrary("CallbackHandler-1.0", true)
assert(CBH, "LibDataBroker-1.1 needs CallbackHandler-1.0")

local lib, oldminor = LibStub:NewLibrary("LibDataBroker-1.1", 4)
if not lib then return end -- the same or a newer copy is already loaded: everyone uses that one

lib.callbacks = lib.callbacks or CBH:New(lib)
lib.attributestorage = lib.attributestorage or {} -- [dataobj] = { attribute = value }
lib.namestorage = lib.namestorage or {}           -- [dataobj] = name
lib.proxystorage = lib.proxystorage or {}         -- [name] = dataobj

local values, names, objects, callbacks = lib.attributestorage, lib.namestorage, lib.proxystorage, lib.callbacks

-- A data object is an empty proxy table: reads come from its stored attributes and every write that changes a value
-- fires the change callbacks (general, per object, per object and attribute, per attribute).
local function readAttribute(dataobj, key)
	local stored = values[dataobj]
	if stored then return stored[key] end
end

local function writeAttribute(dataobj, key, value)
	local stored = values[dataobj]
	if not stored then
		stored = {}
		values[dataobj] = stored
	end
	if stored[key] == value then return end
	stored[key] = value
	local name = names[dataobj]
	if name == nil then return end
	callbacks:Fire("LibDataBroker_AttributeChanged", name, key, value, dataobj)
	callbacks:Fire("LibDataBroker_AttributeChanged_" .. name, name, key, value, dataobj)
	callbacks:Fire("LibDataBroker_AttributeChanged_" .. name .. "_" .. key, name, key, value, dataobj)
	callbacks:Fire("LibDataBroker_AttributeChanged__" .. key, name, key, value, dataobj)
end

lib.domt = lib.domt or {}
lib.domt.__metatable = "access denied"
lib.domt.__index = readAttribute
lib.domt.__newindex = writeAttribute

-- name: a unique string. dataobj: optional table of starting attributes (it becomes the proxy, emptied).
-- Returns nil when the name is taken.
function lib:NewDataObject(name, dataobj)
	if objects[name] then return nil end
	if dataobj ~= nil and type(dataobj) ~= "table" then error("Invalid dataobj, must be nil or a table", 2) end
	local stored = {}
	if dataobj then
		for k, v in pairs(dataobj) do stored[k] = v end
		for k in pairs(stored) do dataobj[k] = nil end
	else
		dataobj = {}
	end
	values[dataobj] = stored
	setmetatable(dataobj, lib.domt)
	objects[name] = dataobj
	names[dataobj] = name
	callbacks:Fire("LibDataBroker_DataObjectCreated", name, dataobj)
	return dataobj
end

function lib:DataObjectIterator()
	return pairs(objects)
end

function lib:GetDataObjectByName(name)
	return objects[name]
end

function lib:GetNameByDataObject(dataobj)
	return names[dataobj]
end

local function storedOf(self, which, usage)
	local t = type(which)
	if t ~= "string" and t ~= "table" then error(usage, 3) end
	local dataobj = objects[which] or which
	local stored = values[dataobj]
	if not stored then error("Data object not found", 3) end
	return stored
end

-- Iterate a data object's attributes (the proxy itself is always empty).
function lib:pairs(which)
	return next, storedOf(self, which, "Usage: ldb:pairs('dataobjectname') or ldb:pairs(dataobject)"), nil
end

function lib:ipairs(which)
	return ipairs(storedOf(self, which, "Usage: ldb:ipairs('dataobjectname') or ldb:ipairs(dataobject)"))
end

-- An older copy may have created objects with its own metatable; give them this one.
if oldminor then
	for _, dataobj in pairs(objects) do
		if values[dataobj] == nil then values[dataobj] = {} end
	end
end
