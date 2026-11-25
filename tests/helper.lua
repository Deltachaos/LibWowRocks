-- Shared stubs for running varpackage as a Lua module.

package.path = "./?.lua;./?/init.lua;" .. package.path

local M = {}

function M.clear_loaded()
	package.loaded.varpackage = nil
end

function M.factory()
	M.clear_loaded()
	return require("varpackage")
end

function M.fresh(first, second)
	return M.factory()(first, second)
end

function M.getter(sources)
	return function(file)
		return sources[file]
	end
end

return M
