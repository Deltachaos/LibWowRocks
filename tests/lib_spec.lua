describe("varpackage", function()
	local helper = require("tests.helper")

	local function host_or_missing(req, name)
		if _G[name] ~= nil then
			assert.equals(_G[name], req(name))
		else
			local ok, err = pcall(req, name)
			assert.is_false(ok)
			assert.is_truthy(tostring(err):find("module '" .. name .. "' not found", 1, true))
		end
	end

	it("returns a callable factory from require", function()
		local factory = helper.factory()
		assert.is_table(factory)
		assert.equals("varpackage-1.0", factory.MAJOR)
		assert.equals(4, factory.MINOR)
		assert.is_function(getmetatable(factory).__call)
		assert.equals(factory, require("varpackage"))
	end)

	it("builds a require with the default path and empty get", function()
		local req = helper.fresh()
		assert.is_table(req)
		assert.is_function(getmetatable(req).__call)
		assert.is_table(req.package)
		assert.is_function(req.module)
		assert.equals("share/lua/5.1/?.lua;share/lua/5.1/?/init.lua", req.package.path)
		assert.equals("/", req.package.config:sub(1, 1))
		assert.equals(string, req("string"))
		assert.equals(req.package, req("package"))
	end)

	it("accepts an options table and the (get, globals) form", function()
		local sources = {
			["share/lua/5.1/fromopts.lua"] = "return { via = 'opts', os = os }",
			["share/lua/5.1/fromfn.lua"] = "return { via = 'fn', os = os }",
		}
		local fake_os = { kind = "fake" }
		local from_opts = helper.fresh({
			get = helper.getter(sources),
			globals = { os = fake_os },
			native = false,
		})
		assert.equals("opts", from_opts("fromopts").via)
		assert.equals(fake_os, from_opts("fromopts").os)

		local from_fn = helper.fresh(helper.getter(sources), { os = fake_os })
		assert.equals("fn", from_fn("fromfn").via)
		assert.equals(fake_os, from_fn("fromfn").os)
		package.loaded.fromfn = nil
	end)

	it("uses a private package.loaded when native is false", function()
		local a = helper.fresh({ native = false })
		local b = helper.fresh({ native = false })
		a.package.loaded.x = { n = 1 }
		assert.is_nil(b.package.loaded.x)
		assert.not_equals(a.package.loaded, package.loaded)
		assert.not_equals(a.package, b.package)
	end)

	it("shares the host package.loaded and package.preload when native is enabled", function()
		local req = helper.fresh()
		assert.equals(package.loaded, req.package.loaded)
		assert.equals(package.preload, req.package.preload)
	end)

	it("loads a preload once and returns the cached module", function()
		local req = helper.fresh({ native = false })
		local calls = 0
		req.package.preload.demo = function(name)
			calls = calls + 1
			return { name = name }
		end
		local first = req("demo")
		local second = req("demo")
		assert.equals(1, calls)
		assert.equals(first, second)
		assert.equals("demo", first.name)
		assert.equals(first, req.package.loaded.demo)
	end)

	it("stores true when a preload returns nil", function()
		local req = helper.fresh({ native = false })
		req.package.preload.empty = function() end
		assert.equals(true, req("empty"))
		assert.equals(true, req.package.loaded.empty)
	end)

	it("propagates a preload error and then reports the previous error", function()
		local req = helper.fresh({ native = false })
		req.package.preload.bad = function()
			error("preload failed")
		end
		local ok, err = pcall(req, "bad")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("preload failed", 1, true))
		ok, err = pcall(req, "bad")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("loop or previous error", 1, true))
	end)

	it("returns a host standard library when one exists", function()
		local req = helper.fresh({ native = false })
		assert.equals(string, req("string"))
		assert.equals(table, req("table"))
		assert.equals(math, req("math"))
		assert.equals(coroutine, req("coroutine"))
		assert.equals(os, req("os"))
		assert.equals(io, req("io"))
		assert.equals(debug, req("debug"))
		assert.equals(req.package, req("package"))
		assert.equals(debug, req.package.loaded.debug)
		assert.equals(debug, req("debug"))

		req.package.loaded.debug = nil
		req.package.preload.debug = function()
			return { custom = true }
		end
		assert.is_true(req("debug").custom)

		host_or_missing(req, "bit32")
		host_or_missing(req, "utf8")
	end)

	it("loads a module from get and keeps the source", function()
		local sources = {
			["share/lua/5.1/pkg/sample_mod.lua"] = "return { ok = true, name = ... }",
		}
		local req = helper.fresh({ get = helper.getter(sources), native = false })
		local mod = req("pkg.sample_mod")
		assert.is_true(mod.ok)
		assert.equals("pkg.sample_mod", mod.name)
		assert.equals("return { ok = true, name = ... }", sources["share/lua/5.1/pkg/sample_mod.lua"])
		sources["share/lua/5.1/pkg/sample_mod.lua"] = "return { ok = false }"
		assert.equals(mod, req("pkg.sample_mod"))
	end)

	it("returns the same table so later requires see mutations", function()
		local sources = {
			["share/lua/5.1/module.lua"] = "return { value = 1 }",
			["share/lua/5.1/first.lua"] = "local module = require('module'); module.value = 42; return module",
			["share/lua/5.1/second.lua"] = "local module = require('module'); return module",
		}
		local req = helper.fresh({ get = helper.getter(sources), native = false })
		local first = req("first")
		local second = req("second")
		assert.equals(42, first.value)
		assert.equals(42, second.value)
		assert.equals(first, second)
		assert.equals(first, req("module"))
	end)

	it("loads init files, nested modules, and a nil chunk result", function()
		local sources = {
			["share/lua/5.1/inner.lua"] = "return { n = 1 }",
			["share/lua/5.1/outer.lua"] =
				"local inner = require('inner'); return { inner = inner, pkg = package }",
			["share/lua/5.1/group/init.lua"] = "return { via = 'init' }",
			["share/lua/5.1/blank.lua"] = "return",
			["share/lua/5.1/selfset.lua"] = "package.loaded['selfset'] = { set = true }",
			["share/lua/5.1/writer.lua"] = "answer = 42; return { p = print }",
		}
		_G.answer = nil
		local req = helper.fresh({ get = helper.getter(sources), native = false })
		local outer = req("outer")
		assert.equals(1, outer.inner.n)
		assert.equals(req.package, outer.pkg)
		assert.equals("init", req("group").via)
		assert.equals(true, req("blank"))
		assert.is_true(req("selfset").set)
		local writer = req("writer")
		assert.equals(print, writer.p)
		assert.equals(42, _G.answer)
		_G.answer = nil
	end)

	it("prefers package.loaded and package.preload over get", function()
		local sources = {
			["share/lua/5.1/samplemod.lua"] = "return { from = 'source' }",
		}
		local req = helper.fresh({ get = helper.getter(sources), native = false })
		req.package.loaded.samplemod = { from = "loaded" }
		assert.equals("loaded", req("samplemod").from)
		assert.equals("return { from = 'source' }", sources["share/lua/5.1/samplemod.lua"])

		req.package.loaded.samplemod = nil
		req.package.preload.samplemod = function()
			return { from = "preload" }
		end
		assert.equals("preload", req("samplemod").from)
		assert.equals("return { from = 'source' }", sources["share/lua/5.1/samplemod.lua"])
	end)

	it("reports syntax errors, runtime errors, and a require loop", function()
		local sources = {
			["share/lua/5.1/syntax.lua"] = "return (",
			["share/lua/5.1/boom.lua"] = "error('boom')",
			["share/lua/5.1/loopmod.lua"] = "return require('loopmod')",
		}
		local req = helper.fresh({ get = helper.getter(sources), native = false })
		local ok, err = pcall(req, "syntax")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("syntax", 1, true) or tostring(err):find("expected", 1, true))
		assert.equals("return (", sources["share/lua/5.1/syntax.lua"])

		ok, err = pcall(req, "boom")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("boom", 1, true))
		assert.equals("error('boom')", sources["share/lua/5.1/boom.lua"])
		ok, err = pcall(req, "boom")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("loop or previous error", 1, true))

		ok, err = pcall(req, "loopmod")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("loop or previous error", 1, true))
	end)

	it("skips non-string sources and names the files it tried", function()
		local sources = {
			["share/lua/5.1/skip.lua"] = 5,
			["share/lua/5.1/skip/init.lua"] = "return { via = 'init' }",
		}
		local req = helper.fresh({ get = helper.getter(sources), native = false })
		assert.equals("init", req("skip").via)

		req.package.path = ""
		local ok, err = pcall(req, "nowhere")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("module 'nowhere' not found:", 1, true))

		req.package.path = "share/lua/5.1/?.lua;share/lua/5.1/?/init.lua"
		ok, err = pcall(req, "missing.mod")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("no file 'share/lua/5.1/missing/mod.lua'", 1, true))
		assert.is_truthy(tostring(err):find("no file 'share/lua/5.1/missing/mod/init.lua'", 1, true))
	end)

	it("honors package.path and the directory separator in package.config", function()
		local sources = {
			["custom/thing.lua"] = "return { ok = true }",
			["win\\a\\b.lua"] = "return { win = true }",
		}
		local req = helper.fresh({
			get = helper.getter(sources),
			path = "custom/?.lua",
			native = false,
		})
		assert.is_true(req("thing").ok)

		req.package.config = "\\\n;\n?\n!\n-"
		req.package.path = "win\\?.lua"
		assert.is_true(req("a.b").win)
	end)

	it("errors when the module is missing or the name is not a string", function()
		local req = helper.fresh({ native = false })
		local ok, err = pcall(req, "missing")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("module 'missing' not found", 1, true))
		assert.is_truthy(tostring(err):find("no file 'share/lua/5.1/missing.lua'", 1, true))
		ok, err = pcall(req, 1)
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("string expected", 1, true))
		ok, err = pcall(req, nil)
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("string expected", 1, true))
	end)

	it("applies globals for a load and restores them afterward", function()
		local original = _G.os
		local fake = { kind = "shim" }
		local sources = {
			["share/lua/5.1/inner.lua"] = "return os",
			["share/lua/5.1/outer.lua"] =
				"local inner = require('inner'); return { inner = inner, os = os }",
			["share/lua/5.1/boom.lua"] = "error('boom')",
			["share/lua/5.1/assign.lua"] = "os = 1; return true",
		}
		local req = helper.fresh({
			get = helper.getter(sources),
			globals = { os = fake },
			native = false,
		})
		local outer = req("outer")
		assert.equals(fake, outer.os)
		assert.equals(fake, outer.inner)
		assert.equals(original, _G.os)

		local ok = pcall(req, "boom")
		assert.is_false(ok)
		assert.equals(original, _G.os)

		assert.equals(true, req("assign"))
		assert.equals(original, _G.os)
	end)

	it("restores a missing global to nil", function()
		local saved = _G.shimmed
		_G.shimmed = nil
		local sources = {
			["share/lua/5.1/useshim.lua"] = "return shimmed",
		}
		local value = { ok = true }
		local req = helper.fresh({
			get = helper.getter(sources),
			globals = { shimmed = value },
			native = false,
		})
		assert.equals(value, req("useshim"))
		assert.is_nil(_G.shimmed)
		_G.shimmed = saved
	end)

	it("reuses a module already in the host package.loaded", function()
		local calls = 0
		package.loaded.nativemod = { from = "native", value = 1 }
		local req = helper.fresh({
			get = function(file)
				calls = calls + 1
				return "return { from = 'get' }"
			end,
		})
		local first = req("nativemod")
		first.value = 42
		local second = req("nativemod")
		package.loaded.nativemod = nil
		assert.equals("native", first.from)
		assert.equals(42, second.value)
		assert.equals(first, second)
		assert.equals(0, calls)
	end)

	it("stores the module in the host cache so native require sees it", function()
		local sources = {
			["share/lua/5.1/sharedmod.lua"] = "return { value = 1 }",
		}
		local req = helper.fresh({ get = helper.getter(sources) })
		local first = req("sharedmod")
		first.value = 42
		local via_native = require("sharedmod")
		package.loaded.sharedmod = nil
		assert.equals(first, via_native)
		assert.equals(42, via_native.value)
	end)

	it("does not write the host cache when native is false", function()
		package.loaded.privatemod = nil
		local req = helper.fresh({
			get = helper.getter({
				["share/lua/5.1/privatemod.lua"] = "return { value = 1 }",
			}),
			native = false,
		})
		local first = req("privatemod")
		first.value = 42
		assert.is_nil(package.loaded.privatemod)
		local ok, err = pcall(require, "privatemod")
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("module 'privatemod' not found", 1, true) or tostring(err):find("privatemod", 1, true))
		assert.equals(42, req("privatemod").value)
	end)

	it("loadstrings when native is false even if the host already loaded the name", function()
		package.loaded.nativemod = { from = "native" }
		local req = helper.fresh({
			get = helper.getter({
				["share/lua/5.1/nativemod.lua"] = "return { from = 'get' }",
			}),
			native = false,
		})
		local mod = req("nativemod")
		assert.equals("get", mod.from)
		assert.equals("native", package.loaded.nativemod.from)
		package.loaded.nativemod = nil
	end)

	it("falls back to the host require when native is enabled", function()
		package.preload.hostmod = function()
			return { host = true }
		end
		local req = helper.fresh()
		assert.is_true(req("hostmod").host)
		assert.is_true(req.package.loaded.hostmod.host)
		package.preload.hostmod = nil
		package.loaded.hostmod = nil
	end)

	it("does not call the host require when native is false", function()
		package.preload.hostmod = function()
			return { host = true }
		end
		local req = helper.fresh({ native = false })
		local ok, err = pcall(req, "hostmod")
		package.preload.hostmod = nil
		package.loaded.hostmod = nil
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("module 'hostmod' not found", 1, true))
	end)

	it("module fills _NAME, _M, and _PACKAGE", function()
		local req = helper.fresh({ native = false })
		local function define()
			local M = req.module("pkg.mod")
			assigned = 7
			return M, _NAME, _M, _PACKAGE
		end
		local returned, name, env, pkg = define()
		assert.equals(returned, env)
		assert.equals("pkg.mod", name)
		assert.equals("pkg.", pkg)
		assert.equals(7, returned.assigned)
		assert.equals(returned, req.package.loaded["pkg.mod"])

		local calls = 0
		local function reopen()
			local M = req.module("pkg.mod", function(mod)
				calls = calls + 1
				mod.ready = true
			end, "ignored", function(mod)
				calls = calls + 1
				mod.extra = true
			end)
			return M
		end
		local again = reopen()
		assert.equals(returned, again)
		assert.equals(2, calls)
		assert.is_true(again.ready)
		assert.is_true(again.extra)

		local function open_solo()
			local M = req.module("solo")
			return M
		end
		local solo = open_solo()
		assert.equals("", solo._PACKAGE)
		assert.equals(solo, solo._M)

		local existing = { keep = true }
		req.package.loaded.reused = existing
		local function open_reused()
			local M = req.module("reused")
			return M
		end
		assert.equals(existing, open_reused())
		assert.is_true(existing.keep)

		local ok, err = pcall(req.module, 1)
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("string expected", 1, true))
	end)

	it("uses package.searchers in order and aliases them as package.loaders", function()
		local req = helper.fresh({ native = false })
		assert.equals(req.package.loaders, req.package.searchers)
		assert.is_function(req.package.searchers[1])
		assert.is_function(req.package.searchers[2])
		assert.is_nil(req.package.searchers[3])

		local calls = {}
		table.insert(req.package.searchers, 1, function(name)
			calls[#calls + 1] = name
			if name == "custom" then
				return function(modname)
					return { name = modname, via = "searcher" }
				end
			end
		end)
		assert.equals("searcher", req("custom").via)
		assert.equals("custom", calls[1])
		assert.equals(1, #calls)

		req.package.searchers = {
			function(name)
				return function()
					return { via = "replaced", name = name }
				end
			end,
		}
		assert.equals("replaced", req("other").via)
		assert.equals("other", req("other").name)
	end)

	it("passes a searcher's extra value to the loader", function()
		local req = helper.fresh({ native = false })
		req.package.searchers = {
			function(name)
				return function(modname, extra)
					return { name = modname, extra = extra }
				end, "payload"
			end,
		}
		local mod = req("with-extra")
		assert.equals("with-extra", mod.name)
		assert.equals("payload", mod.extra)
	end)

	it("keeps using package.preload after searchers are rewritten around it", function()
		local req = helper.fresh({ native = false })
		local preload = req.package.searchers[1]
		req.package.preload.fromsearcher = function()
			return { via = "preload" }
		end
		req.package.searchers = {
			function()
				return "\n\tcustom miss"
			end,
			preload,
		}
		assert.equals("preload", req("fromsearcher").via)
	end)

	it("package.loadlib errors and package.seeall indexes _G", function()
		local req = helper.fresh()
		local ok, err = pcall(req.package.loadlib)
		assert.is_false(ok)
		assert.is_truthy(tostring(err):find("package.loadlib is not available", 1, true))
		local env = {}
		req.package.seeall(env)
		assert.equals(print, env.print)
	end)

	it("does not install package onto _G", function()
		local host_package = _G.package
		local req = helper.fresh()
		assert.equals(host_package, _G.package)
		assert.not_equals(req.package, _G.package)
	end)
end)
