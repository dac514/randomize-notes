# Randomize Notes

A [Renoise](https://www.renoise.com) tool that randomizes or shuffles notes in a
scale and key. It works in the Pattern Editor and the Phrase Editor, and a
small piano shows the scale you pick.

The user guide is in
[`com.renoise.NotesRandomizer.xrnx/README.md`](com.renoise.NotesRandomizer.xrnx/README.md).
Renoise also shows it in the Tool Browser.

## Install

Download `com.renoise.NotesRandomizer.xrnx` from the
[latest release](https://github.com/dac514/randomize-notes/releases) and drag it
onto Renoise. It replaces version 1.11 in place. Renoise 3.5 or newer is needed.

## Development

This project is built on the [ReSlop](https://github.com/dac514/reslop) starter
kit. `CLAUDE.md` is the full briefing; this is the short version.

Install [just](https://github.com/casey/just),
[StyLua](https://github.com/JohnnyMorganz/StyLua),
[lua-language-server](https://github.com/LuaLS/lua-language-server) 3.13.6 or newer,
[LuaJIT](https://luajit.org/download.html) and Python 3.8 or newer. Then run
`just doctor` to see what is missing.

In Renoise, open *Edit > Preferences > OSC* and tick *Enable Server* (UDP, port
8000). The kit uses it to install and reload the tool.

```
just check          # formatting + type check against the Renoise API
just test           # unit tests under plain LuaJIT, no Renoise needed
just install        # install into the running Renoise
just reload         # full reload after an edit (about a second)
just eval 'APP.show_dialog()' && just views
just log            # prints and errors from inside the tool
just screenshot     # PNGs of the Renoise window and the dialog, into dist/
just package        # dist/com.renoise.NotesRandomizer.xrnx, ready to share
```

### Layout

```
com.renoise.NotesRandomizer.xrnx/
  manifest.xml        id, version, API version
  main.lua            entry point and saved settings
  src/app.lua         menus, key bindings, running a randomize
  src/ui.lua          the dialog
  src/piano.lua       the piano canvas
  src/targets.lua     which note columns a scope covers
  src/scales.lua      scales and keys (pure Lua, unit-tested)
  src/notes.lua       randomize, nearest neighbour, shuffle (pure Lua, unit-tested)
  src/selection.lua   selection bounds (pure Lua, unit-tested)
  src/scopes.lua      the Where choices (pure Lua, unit-tested)
  src/keyboard.lua    piano geometry and hit test (pure Lua, unit-tested)
  dev/                development bridge, left out of `just package`
tests/                unit tests for the pure modules
definitions/          the Renoise API, annotated, for the type checker
docs/renoise/         the Renoise scripting guide, offline
```

The scale notes match the scale table of Renoise's own
[pattrns](https://github.com/renoise/pattrns) library (`src/note/scale.rs`).
Their names and order match Renoise's instrument Scale menu.

### Releasing

Pushing a tag `vX.YY` that matches `<Version>` in `manifest.xml` publishes a
GitHub release with the `.xrnx` attached.

### Kit updates

Projects made from ReSlop do not receive later kit fixes by themselves. Ask your
coding assistant to apply the entries in
[ReSlop's UPGRADING.md](https://github.com/dac514/reslop/blob/main/UPGRADING.md)
that are newer than this project.

## Credits and license

Written by Dac Chartrand and released under the MIT license. The project bundles the MIT-licensed
[renoise/definitions](https://github.com/renoise/definitions) and guide pages
from [renoise/xrnx](https://github.com/renoise/xrnx); see the `UPSTREAM.md`
files for the exact commits.
