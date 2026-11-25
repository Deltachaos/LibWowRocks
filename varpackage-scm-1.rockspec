rockspec_format = "3.0"
package = "varpackage"
version = "scm-1"

source = {
  url = "git+https://github.com/Deltachaos/varpackage.git",
}

description = {
  summary = "Lua 5.1 require/package that loads source text through a getter",
  detailed = [[
    varpackage provides require, package, and module for environments
    without a filesystem. Module sources are returned by a caller-supplied
    get function. Optional globals are applied only while a chunk runs.
  ]],
  homepage = "https://github.com/Deltachaos/varpackage",
  license = "MIT",
}

dependencies = {
  "lua >= 5.1"
}

test_dependencies = {
  "busted",
}

build = {
  type = "builtin",
  modules = {
    varpackage = "varpackage.lua",
  },
  copy_directories = {
    "tests"
  },
}

test = {
  type = "busted",
}
