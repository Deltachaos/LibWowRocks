rockspec_format = "3.0"
package = "libwowrocks"
version = "scm-1"

source = {
  url = "git+https://github.com/Deltachaos/LibWowRocks.git",
}

description = {
  summary = "Lua 5.1 require/package for rocks vendored into World of Warcraft",
  detailed = [[
    LibWowRocks provides require, package, and module for pure-Lua rocks
    loaded inside WoW. Standard-library shims (os, io, debug, bit32, load)
    come from LibStdShim.
  ]],
  homepage = "https://github.com/Deltachaos/LibWowRocks",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1",
  "libstdshim",
}

test_dependencies = {
  "busted",
}

build = {
  type = "builtin",
  modules = {
    LibWowRocks = "LibWowRocks.lua",
  },
  copy_directories = {
    "tests",
    "meta",
  },
}

test = {
  type = "busted",
}
