--[[
  WowRocks-1.0
  Lua 5.1 require/package for rocks vendored into World of Warcraft.
  Standard-library shims live in LibStdShim-1.0 (libstdshim rock).
]]

local MAJOR, MINOR = "WowRocks-1.0", 1

-- WoW loads this file from meta/lib.xml after LibStub and LibStdShim.
-- luarocks/busted require() it, and then LibStdShim comes in as a module.
local libstub = _G.LibStub
local loaded_as_module = select("#", ...) >= 1 and type((...)) == "string"

local WowRocks
if not libstub then
	if not loaded_as_module then
		error("LibWowRocks requires LibStub", 2)
	end
	WowRocks = {}
else
	WowRocks = libstub:NewLibrary(MAJOR, MINOR)
	if not WowRocks then return end
end

local Std = (libstub and libstub("LibStdShim-1.0", true))
	or (loaded_as_module and require("LibStdShim"))
if not Std then
	error("LibWowRocks requires LibStdShim-1.0", 2)
end
local _type = type
local _error = error
local _tostring = tostring
local _select = select
local _setmetatable = setmetatable
local _pcall = pcall
local _tonumber = tonumber
local _string_match = string.match
local _string_find = string.find
local _string_sub = string.sub
local _table_insert = table.insert
local _setfenv = setfenv

local SENTINEL = WowRocks._SENTINEL or {}
WowRocks._SENTINEL = SENTINEL
WowRocks._module_versions = WowRocks._module_versions or {}

local function parse_version_part(s)
	local parts = {}
	local revision = 0
	local ver, rev = _string_match(s, "^(.*)%-(%d+)$")
	if ver then
		s = ver
		revision = _tonumber(rev) or 0
	end
	for piece in (s .. "."):gmatch("([^.]*)%.") do
		local n = _tonumber(piece)
		if n then
			_table_insert(parts, n)
		else
			local num, rest = _string_match(piece, "^(%d*)(.*)$")
			if num and num ~= "" then
				_table_insert(parts, _tonumber(num))
			end
			if rest and rest ~= "" then
				_table_insert(parts, rest)
			elseif not n then
				_table_insert(parts, piece)
			end
		end
	end
	return parts, revision
end

local function cmp_parts(a, b)
	local n = #a
	if #b > n then n = #b end
	for i = 1, n do
		local x, y = a[i] or 0, b[i] or 0
		local tx, ty = _type(x), _type(y)
		if tx == "number" and ty == "number" then
			if x < y then return -1 end
			if x > y then return 1 end
		else
			x, y = _tostring(x), _tostring(y)
			if x < y then return -1 end
			if x > y then return 1 end
		end
	end
	return 0
end

local function compare_versions(a, b)
	local ap, ar = parse_version_part(a)
	local bp, br = parse_version_part(b)
	local c = cmp_parts(ap, bp)
	if c ~= 0 then return c end
	if ar < br then return -1 end
	if ar > br then return 1 end
	return 0
end

function WowRocks._accept(name, version)
	local current = WowRocks._module_versions[name]
	if current == nil then
		WowRocks._module_versions[name] = version
		return true
	end
	if compare_versions(version, current) > 0 then
		WowRocks._module_versions[name] = version
		return true
	end
	return false
end

local package = WowRocks.package or {
	loaded = {},
	preload = {},
	path = "",
	cpath = "",
	config = "/\n;\n?\n!\n-",
	loaders = {},
	searchers = {},
}
WowRocks.package = package
package.loaded = package.loaded or {}
package.preload = package.preload or {}
package.loaders = package.loaders or {}
package.searchers = package.searchers or package.loaders

function package.loadlib()
	_error("WowRocks: package.loadlib is not available in WoW", 2)
end

function package.seeall(env)
	_setmetatable(env, { __index = _G })
end

local function require_name(name)
	if _type(name) ~= "string" then
		_error("bad argument #1 to 'require' (string expected, got " .. _type(name) .. ")", 3)
	end
	local loaded = package.loaded[name]
	if loaded == SENTINEL then
		_error("loop or previous error loading module '" .. name .. "'", 3)
	end
	if loaded ~= nil then
		return loaded
	end
	local preload = package.preload[name]
	if preload then
		package.loaded[name] = SENTINEL
		local ok, result = _pcall(preload, name)
		if not ok then
			package.loaded[name] = SENTINEL
			_error(result, 0)
		end
		if result ~= nil then
			package.loaded[name] = result
		elseif package.loaded[name] == SENTINEL then
			package.loaded[name] = true
		end
		return package.loaded[name]
	end
	_error("module '" .. name .. "' not found", 3)
end

function WowRocks.require(name)
	return require_name(name)
end

function WowRocks._begin(name)
	package.loaded[name] = SENTINEL
end

function WowRocks._finish(name, value, explicit)
	if explicit then
		if value == nil then
			if package.loaded[name] == SENTINEL then
				package.loaded[name] = true
			end
		else
			package.loaded[name] = value
		end
		return
	end
	if package.loaded[name] == SENTINEL then
		package.loaded[name] = true
	end
end

function WowRocks.module(name, ...)
	if _type(name) ~= "string" then
		_error("bad argument #1 to 'module' (string expected)", 2)
	end
	local M = package.loaded[name]
	if _type(M) ~= "table" then
		M = {}
		package.loaded[name] = M
	end
	M._NAME = name
	M._M = M
	local dot = _string_find(name, "%.[^%.]*$")
	M._PACKAGE = dot and _string_sub(name, 1, dot) or ""
	if _setfenv then
		_setfenv(2, M)
	end
	for i = 1, _select("#", ...) do
		local modifier = _select(i, ...)
		if _type(modifier) == "function" then
			modifier(M)
		end
	end
	return M
end

WowRocks.os = Std.os
WowRocks.io = Std.io
WowRocks.debug = Std.debug
WowRocks.bit32 = Std.bit32
WowRocks.load = Std.load
WowRocks.dofile = Std.dofile
WowRocks.loadfile = Std.loadfile
package.preload.bit32 = function()
	return Std.bit32
end

WowRocks.MAJOR = MAJOR
WowRocks.MINOR = MINOR

return WowRocks
