# LibWowRocks

Lua 5.1 `require` / `package` for rocks vendored into World of Warcraft.

WoW has no `require` or `package`. LibWowRocks is that layer: a LibStub library (`WowRocks-1.0`) with `require`, `module`, and a `package` table. Standard-library gaps (`os`, `io`, `debug`, `bit32`, `load` / `loadfile` / `dofile`) come from [LibStdShim](https://github.com/Deltachaos/LibStdShim), which this rock depends on.

wowrocks vendors this rock into an addon and rewrites other rocks so their `require` calls go through `WowRocks`. Because `libstdshim` is a dependency, that install brings the shims in too.

## Install

Copy this repository into your addon (or a libs folder). Load LibStdShim first, then `meta/lib.xml`:

```xml
<Include file="LibStdShim\meta\lib.xml"/>
<Include file="LibWowRocks\meta\lib.xml"/>
```

`meta/lib.xml` loads `LibWowRocks.lua`. LibStdShim must already be registered as `LibStdShim-1.0`.

As a LuaRocks module:

```bash
luarocks install libwowrocks
```

That pulls in `libstdshim`.

## Usage

```lua
local WowRocks = LibStub("WowRocks-1.0")
local json = WowRocks.require("dkjson")

local Std = LibStub("LibStdShim-1.0")
local now = Std.os.time()
```

`WowRocks.os`, `WowRocks.io`, `WowRocks.debug`, `WowRocks.bit32`, `WowRocks.load`, `WowRocks.loadfile`, and `WowRocks.dofile` are the LibStdShim implementations. `require` of a standard-library name (`debug`, `os`, `io`, `bit32`, `table`, `string`, `math`, `coroutine`, `package`, `utf8`) returns the LibStdShim module when the shim provides it, and otherwise the host library. `require("package")` is this library's `package` table. A `package.preload` entry still wins.

Without LibStub, requiring the module returns the library table:

```lua
local WowRocks = require("LibWowRocks")
```

Vendored rocks call `WowRocks._accept`, `WowRocks._begin`, and `WowRocks._finish` so a newer rock version replaces an older one and `require` sees the loaded module.

## Tests

Tests use [busted](https://lunarmodules.github.io/busted/).

```bash
luarocks test --prepare libwowrocks-scm-1.rockspec
busted
```

## License

MIT. See [LICENSE](LICENSE).
