-- Shared stubs for running LibWowRocks outside World of Warcraft.

package.path = "./?.lua;./?/init.lua;" .. package.path

local COMPANIONS = {
	"LibStdShim.os",
	"LibStdShim.io",
	"LibStdShim.debug",
	"LibStdShim.bit32",
	"LibStdShim.load",
	"LibStdShim.table",
}

local M = {}

function M.make_libstub()
	local libs = {}
	local minors = {}
	local stub = { libs = libs, minors = minors }
	function stub:NewLibrary(major, minor)
		minor = assert(tonumber(tostring(minor):match("%d+")), "minor must contain a number")
		local oldminor = minors[major]
		if oldminor and oldminor >= minor then
			return nil
		end
		minors[major] = minor
		libs[major] = libs[major] or {}
		return libs[major], oldminor
	end
	function stub:GetLibrary(major, silent)
		if not libs[major] and not silent then
			error("Cannot find a library instance of " .. tostring(major), 2)
		end
		return libs[major], minors[major]
	end
	setmetatable(stub, { __call = stub.GetLibrary })
	return stub, libs
end

function M.clear_loaded()
	package.loaded.LibWowRocks = nil
	package.loaded.LibStdShim = nil
	for i = 1, #COMPANIONS do
		package.loaded[COMPANIONS[i]] = nil
	end
	_G.LibWowRocks = nil
	_G.LibStdShim = nil
end

function M.fresh()
	M.clear_loaded()
	local stub, libs = M.make_libstub()
	_G.LibStub = stub
	require("LibStdShim")
	local WowRocks = require("LibWowRocks")
	return WowRocks, stub, libs
end

return M
