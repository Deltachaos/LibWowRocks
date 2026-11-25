# varpackage

Lua 5.1 `require` / `package` for environments that store module sources as strings instead of files.

`varpackage-1.0` is a LibStub factory. Calling it returns an isolated `require` function. Module text comes from a `get` function. Optional globals are written to `_G` only while a chunk runs, then restored.

## Install

Copy this repository into your addon (or a libs folder) and load `varpackage.lua` after LibStub. The included `.toc` does that.

As a LuaRocks module:

```bash
luarocks install varpackage
```

## Usage

```lua
local requirestring = LibStub("varpackage-1.0")({
    get = function(file)
        return _G.__wowrocks[file]
    end,
    globals = {
        os = Std.os,
    },
})
local json = requirestring("dkjson")
```

`get` as the first argument and `globals` as the second:

```lua
local requirestring = LibStub("varpackage-1.0")(function(file)
    return _G.__wowrocks[file]
end, {
    os = Std.os,
})
```

Defaults when an option is omitted:

- `get` is `function(file) return nil end`
- `globals` is `{}`
- `path` is `share/lua/5.1/?.lua;share/lua/5.1/?/init.lua`
- `native` is `true`

`LibStub("varpackage-1.0")()` is valid. With the defaults it uses the host `require` when one exists.

`require` checks `package.loaded`, then a standard-library name, then walks `package.searchers` (aliased as `package.loaders`) the way Lua does. The default searchers are `package.preload`, then `path` templates through `get`, then the host `require` when `native` is on. Replacing or inserting searchers changes what `require` does. When `native` is on (the default), `package.loaded` and `package.preload` are Lua's own tables, so a later native `require` sees modules this instance loaded. Pass `native = false` for a private `package.loaded` / `package.preload` that do not read or write the host cache.

Each factory call gets its own `package` table. The returned function has `require.package` and `require.module`.

Without LibStub, requiring the module returns the same callable factory:

```lua
local varpackage = require("varpackage")
local req = varpackage()
```

## Tests

Tests use [busted](https://lunarmodules.github.io/busted/).

```bash
luarocks test --prepare varpackage-scm-1.rockspec
busted
```

## License

MIT. See [LICENSE](LICENSE).
