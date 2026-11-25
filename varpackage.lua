--[[
  varpackage-1.0
  Lua 5.1 require/package that loads source text through a caller-supplied getter.
]]

local MAJOR, MINOR = "varpackage-1.0", 4
local DEFAULT_PATH = "share/lua/5.1/?.lua;share/lua/5.1/?/init.lua"

local libstub = _G.LibStub
local loaded_as_module = require ~= nil and select("#", ...) >= 1 and type((...)) == "string"

local VarPackage
if not libstub then
	if not loaded_as_module then
		error("varpackage requires LibStub", 2)
	end
	VarPackage = {}
else
	VarPackage = libstub:NewLibrary(MAJOR, MINOR)
	if not VarPackage then return end
end

local _type = type
local _error = error
local _tostring = tostring
local _select = select
local _setmetatable = setmetatable
local _pcall = pcall
local _pairs = pairs
local _string_match = string.match
local _string_find = string.find
local _string_sub = string.sub
local _setfenv = setfenv
local _loadstring = loadstring
local _load = load
local _VERSION = _VERSION

local STDLIB = {
	coroutine = true,
	package = true,
	string = true,
	utf8 = true,
	table = true,
	math = true,
	io = true,
	os = true,
	debug = true,
	bit32 = true,
}

local function default_get()
	return nil
end

local lua51 = _string_match(_tostring(_VERSION), "5%.1") ~= nil

local function compile_chunk(src, filename, env)
	if not lua51 and _load then
		return _load(src, "@" .. filename, "t", env)
	end
	if not _loadstring then
		_error("varpackage: loadstring is not available", 3)
	end
	local fn, err = _loadstring(src, "@" .. filename)
	if fn and _setfenv then
		_setfenv(fn, env)
	end
	return fn, err
end

local function parse_opts(first, second)
	if first == nil then
		return default_get, {}, DEFAULT_PATH, true
	end
	if _type(first) == "function" then
		local globals = second
		if globals == nil then
			globals = {}
		elseif _type(globals) ~= "table" then
			_error("varpackage: globals must be a table", 3)
		end
		return first, globals, DEFAULT_PATH, true
	end
	if _type(first) ~= "table" then
		_error("varpackage: options table or get function expected", 3)
	end
	local get = first.get
	if get == nil then
		get = default_get
	elseif _type(get) ~= "function" then
		_error("varpackage: get must be a function", 3)
	end
	local globals = first.globals
	if globals == nil then
		globals = {}
	elseif _type(globals) ~= "table" then
		_error("varpackage: globals must be a table", 3)
	end
	local path = first.path
	if path == nil then
		path = DEFAULT_PATH
	end
	local native = first.native
	if native == nil then
		native = true
	end
	return get, globals, path, native ~= false
end

local function new_require(first, second)
	local getter, globals, path, native = parse_opts(first, second)
	local native_require
	local loaded = {}
	local preload = {}
	if native then
		local host = _G.require
		if _type(host) == "function" then
			native_require = host
		end
		local host_package = _G.package
		if _type(host_package) == "table" then
			if _type(host_package.loaded) == "table" then
				loaded = host_package.loaded
			end
			if _type(host_package.preload) == "table" then
				preload = host_package.preload
			end
		end
	end

	local loading = {}
	local package = {
		loaded = loaded,
		preload = preload,
		path = path,
		cpath = "",
		config = "/\n;\n?\n!\n-",
		loaders = {},
		searchers = {},
	}
	package.searchers = package.loaders

	function package.loadlib()
		_error("varpackage: package.loadlib is not available", 2)
	end

	-- Injected globals live on a per-load frame. Assigning them on _G taints those
	-- slots in WoW, and restoring the old value does not clear the taint.
	local depth = 0
	local frames = {}

	local function push_globals()
		local keys = {}
		local values = {}
		for key, value in _pairs(globals) do
			keys[key] = true
			values[key] = value
		end
		depth = depth + 1
		frames[depth] = { keys = keys, values = values }
	end

	local function pop_globals()
		frames[depth] = nil
		depth = depth - 1
	end

	local function global_index(key)
		local frame = frames[depth]
		if frame and frame.keys[key] then
			return frame.values[key]
		end
		return _G[key]
	end

	local function global_newindex(key, value)
		local frame = frames[depth]
		if frame and frame.keys[key] then
			frame.values[key] = value
			return
		end
		_G[key] = value
	end

	local function with_globals(fn)
		push_globals()
		local ok, result = _pcall(fn)
		pop_globals()
		return ok, result
	end

	function package.seeall(env)
		_setmetatable(env, {
			__index = function(_, key)
				return global_index(key)
			end,
		})
	end

	local function stdlib_module(name)
		if not STDLIB[name] then
			return nil
		end
		if name == "package" then
			return package
		end
		return global_index(name)
	end

	local function dirsep()
		return _string_sub(package.config or "/", 1, 1)
	end

	local function pathsep()
		local cfg = package.config or "/\n;"
		local nl = _string_find(cfg, "\n", 1, true)
		if not nl then
			return ";"
		end
		local rest = _string_sub(cfg, nl + 1)
		nl = _string_find(rest, "\n", 1, true)
		if nl then
			rest = _string_sub(rest, 1, nl - 1)
		end
		if rest == "" then
			return ";"
		end
		return rest
	end

	local function search(name)
		local subst = name:gsub("%.", dirsep())
		local errmsg = ""
		local search_path = package.path or ""
		local psep = pathsep()
		for template in (search_path .. psep):gmatch("(.-)" .. psep) do
			if template ~= "" then
				local filename = template:gsub("%?", subst)
				local src = getter(filename)
				if _type(src) == "string" then
					return filename, src
				end
				errmsg = errmsg .. "\n\tno file '" .. filename .. "'"
			end
		end
		return nil, errmsg
	end

	local function finish_loaded(name, result)
		if result ~= nil then
			package.loaded[name] = result
		elseif package.loaded[name] == nil then
			package.loaded[name] = true
		end
		loading[name] = nil
		return package.loaded[name]
	end

	local require_fn = {}
	local module_fn
	local chunk_env
	local function module_env()
		if not chunk_env then
			chunk_env = {
				require = require_fn,
				package = package,
				module = module_fn,
			}
			_setmetatable(chunk_env, {
				__index = function(_, key)
					return global_index(key)
				end,
				__newindex = function(_, key, value)
					global_newindex(key, value)
				end,
			})
		end
		return chunk_env
	end

	local function run_loader(name, loader, extra)
		loading[name] = true
		local ok, result = with_globals(function()
			return loader(name, extra)
		end)
		if not ok then
			_error(result, 0)
		end
		return finish_loaded(name, result)
	end

	local function searcher_preload(name)
		local fn = package.preload[name]
		if fn == nil then
			return "\n\tno field package.preload['" .. name .. "']"
		end
		return fn
	end

	local function searcher_lua(name)
		local filename, src = search(name)
		if not filename then
			return src
		end
		return function(modname)
			local fn, err = compile_chunk(src, filename, module_env())
			if not fn then
				_error(err or ("error loading module '" .. modname .. "' from '" .. filename .. "'"), 0)
			end
			return fn(modname)
		end
	end

	package.loaders[1] = searcher_preload
	package.loaders[2] = searcher_lua
	if native_require then
		package.loaders[3] = function(name)
			return function(modname)
				return native_require(modname)
			end
		end
	end

	function module_fn(name, ...)
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

	local function require_name(name)
		if _type(name) ~= "string" then
			_error("bad argument #1 to 'require' (string expected, got " .. _type(name) .. ")", 3)
		end
		if loading[name] then
			_error("loop or previous error loading module '" .. name .. "'", 3)
		end
		if name == "package" then
			return package
		end
		local cached = package.loaded[name]
		if cached and not STDLIB[name] then
			return cached
		end
		local searchers = package.searchers
		if _type(searchers) ~= "table" then
			searchers = package.loaders
		end
		if _type(searchers) ~= "table" then
			_error("package.searchers must be a table", 3)
		end
		local errmsg = ""
		local i = 1
		while true do
			local searcher = searchers[i]
			if searcher == nil then
				break
			end
			i = i + 1
			if _type(searcher) == "function" then
				local loader, extra = searcher(name)
				if _type(loader) == "function" then
					return run_loader(name, loader, extra)
				elseif _type(loader) == "string" then
					errmsg = errmsg .. loader
				end
			end
		end
		local std = stdlib_module(name)
		if std ~= nil then
			return finish_loaded(name, std)
		end
		if cached then
			return cached
		end
		_error("module '" .. name .. "' not found:" .. errmsg, 3)
	end

	require_fn.package = package
	require_fn.module = module_fn
	return _setmetatable(require_fn, {
		__call = function(_, name)
			return require_name(name)
		end,
	})
end

VarPackage.MAJOR = MAJOR
VarPackage.MINOR = MINOR

setmetatable(VarPackage, {
	__call = function(_, first, second)
		return new_require(first, second)
	end,
})

return VarPackage
