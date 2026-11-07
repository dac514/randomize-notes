--[[
  Application module. Owns everything the tool registers with Renoise (menu
  entries, key bindings, notifiers, timers, dialogs) so that it can be started
  and stopped cleanly. That is what makes the dev bridge's soft reload safe:
  `APP.stop()` on the old module, re-require `src/`, `APP.start()` on the new one.

  Rules:
  * Register only through `App.reg.*` and `App.register_dialog`.
  * No side effects at module level; do them in `App.start()`.
  * Wrap callbacks that Renoise invokes with `App.guard` so errors reach the
    dev log.
  * Inside song list notifiers, read dependents through `App.defer`.
]]

local notes = require "src.notes"
local scales = require "src.scales"
local scopes = require "src.scopes"
local targets = require "src.targets"

local App = {}

---@class NotesRandomizerPreferences : renoise.Document.DocumentNode
---@field how renoise.Document.ObservableString
---@field key renoise.Document.ObservableNumber
---@field custom renoise.Document.ObservableString
---@field where_pattern renoise.Document.ObservableString
---@field where_phrase renoise.Document.ObservableString
---@field neighbour renoise.Document.ObservableBoolean
---@field neighbour_shift renoise.Document.ObservableNumber
---@field preserve_notes renoise.Document.ObservableBoolean
---@field preserve_octaves renoise.Document.ObservableBoolean
---@field octave_min renoise.Document.ObservableNumber
---@field octave_max renoise.Document.ObservableNumber
---@field ignore_muted renoise.Document.ObservableBoolean

App.name = "Randomize Notes"
App.dialog_title = "Notes Randomizer"

---Menu entries that open the dialog. The names are the ones version 1.11
---used, plus the phrase editor.
App.menu_entries = {
  "Main Menu:Tools:Randomize Notes...",
  "Pattern Editor:Randomize Notes...",
  "Phrase Editor:Randomize Notes...",
}

---Key bindings that open the dialog.
App.dialog_keybindings = {
  "Pattern Editor:Tools:Randomize Notes...",
  "Phrase Editor:Phrase Operations:Randomize Notes...",
}

---Key bindings that run directly on one scope. Users' mappings are stored by
---these names, so the 1.11 ones must not change.
---@type { name: string, scope: ScopeId }[]
App.scope_keybindings = {
  { name = "Pattern Editor:Block Operations:Randomize Notes", scope = "pattern_selection" },
  {
    name = "Pattern Editor:Track Operations:Randomize Notes in Pattern",
    scope = "track_in_pattern",
  },
  { name = "Pattern Editor:Track Operations:Randomize Notes in Song", scope = "track_in_song" },
  { name = "Pattern Editor:Pattern Operations:Randomize Notes", scope = "whole_pattern" },
  { name = "Phrase Editor:Block Operations:Randomize Notes", scope = "phrase_selection" },
  { name = "Phrase Editor:Phrase Operations:Randomize Notes", scope = "whole_phrase" },
}

---@class AppDialogEntry
---@field dialog renoise.Dialog
---@field vb renoise.ViewBuilder
---@field root renoise.Views.View
---@field refresh fun()|nil Update the dialog after a change outside of it.

---Registered dialogs by name. Read by the dev bridge's `views` command.
---@type table<string, AppDialogEntry>
App.dialogs = {}

---Log sink. The dev bridge replaces it to capture messages into its ring buffer.
---@type fun(kind: string, text: string)
App.log_sink = function(kind, text)
  print(("[%s] %s"):format(kind, text))
end

---Replace the log sink (used by the dev bridge).
---@param sink fun(kind: string, text: string)
function App.set_log_sink(sink)
  App.log_sink = sink
end

---@param text string
function App.log(text)
  App.log_sink("app", text)
end

---@return NotesRandomizerPreferences
function App.prefs()
  return renoise.tool().preferences --[[@as NotesRandomizerPreferences]]
end

---Wrap a callback so that errors are logged before being re-raised.
---@generic F : function
---@param fn F
---@return F
function App.guard(fn)
  return function(...)
    local n = select("#", ...)
    local args = { ... }
    local results = {
      xpcall(function()
        return fn(unpack(args, 1, n))
      end, function(err)
        return debug.traceback(tostring(err), 2)
      end),
    }
    if not results[1] then
      local message = results[2] and tostring(results[2]) or "unknown error"
      App.log_sink("error", message)
      error(message, 0)
    end
    return unpack(results, 2)
  end
end

-- Registration ---------------------------------------------------------------

---Registration helpers. Everything registered here is undone by `App.stop()`.
local reg = {
  ---@type string[]
  menus = {},
  ---@type string[]
  keys = {},
  ---@type { observable: renoise.Document.Observable, fn: function }[]
  notifiers = {},
  ---@type function[]
  timers = {},
}
App.reg = reg

---@param entry ToolMenuEntry
function reg.menu(entry)
  local tool = renoise.tool()
  if tool:has_menu_entry(entry.name) then
    tool:remove_menu_entry(entry.name)
  end
  tool:add_menu_entry(entry)
  table.insert(reg.menus, entry.name)
end

---@param binding ToolKeybindingEntry
function reg.key(binding)
  local tool = renoise.tool()
  if tool:has_keybinding(binding.name) then
    tool:remove_keybinding(binding.name)
  end
  tool:add_keybinding(binding)
  table.insert(reg.keys, binding.name)
end

---@param observable renoise.Document.Observable
---@param fn function
function reg.notifier(observable, fn)
  if observable:has_notifier(fn) then
    return -- already registered and tracked; safe to call again on refresh
  end
  observable:add_notifier(fn)
  table.insert(reg.notifiers, { observable = observable, fn = fn })
end

---@param fn function
---@param interval_ms integer
function reg.timer(fn, interval_ms)
  local tool = renoise.tool()
  if tool:has_timer(fn) then
    tool:remove_timer(fn)
  end
  tool:add_timer(fn, interval_ms)
  table.insert(reg.timers, fn)
end

-- Deferral -------------------------------------------------------------------

---@type fun()[]
local deferred = {}

local function run_deferred()
  renoise.tool().app_idle_observable:remove_notifier(run_deferred)
  local queue = deferred
  deferred = {}
  for _, fn in ipairs(queue) do
    pcall(App.guard(fn)) -- guard logs the error, pcall keeps the queue going
  end
end

---Queue `fn` (once) for the next idle tick, after Renoise has finished the
---current operation. Song list notifiers (`tracks_observable`,
---`instruments_observable`, `sequencer.pattern_sequence_observable`,
---`phrase_mappings_observable`) fire *during* the edit: inside them the list is
---updated but patterns, sequence and selection are not, and the song must not
---be modified. Observe the dependent object when it has an observable;
---otherwise defer the work with this.
---https://forum.renoise.com/t/79511  https://forum.renoise.com/t/33796/11
---@param fn fun()
function App.defer(fn)
  if table.find(deferred, fn) then
    return
  end
  table.insert(deferred, fn)
  local idle = renoise.tool().app_idle_observable
  if not idle:has_notifier(run_deferred) then
    idle:add_notifier(run_deferred)
  end
end

-- Settings -------------------------------------------------------------------

---The editor the Where popup follows: the phrase editor when it is the
---active middle frame, the pattern editor otherwise.
---@return ScopeEditor
function App.editor()
  local frame = renoise.app().window.active_middle_frame
  if frame == renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_PHRASE_EDITOR then
    return "phrase"
  end
  return "pattern"
end

---The stored Where choice of an editor.
---@param editor ScopeEditor
---@return ScopeId
function App.scope(editor)
  local prefs = App.prefs()
  local stored = editor == "phrase" and prefs.where_phrase.value or prefs.where_pattern.value
  return scopes.at(editor, scopes.index(editor, stored))
end

---The stored settings as plain values, repaired where they are invalid.
---@return NotesSettings
function App.settings()
  local prefs = App.prefs()
  local how = prefs.how.value
  if not scales.is_mode(how) then
    how = "Natural Major"
  end
  local custom = prefs.custom.value
  if #custom ~= 12 or custom:find "[^01]" then
    custom = scales.EMPTY_CUSTOM
  end
  return {
    how = how,
    key = (math.floor(prefs.key.value) - 1) % 12,
    custom = custom,
    neighbour = prefs.neighbour.value,
    shift = notes.SHIFTS[prefs.neighbour_shift.value] or "rand",
    preserve_notes = prefs.preserve_notes.value,
    preserve_octaves = prefs.preserve_octaves.value,
    octave_min = prefs.octave_min.value,
    octave_max = prefs.octave_max.value,
  }
end

-- Running --------------------------------------------------------------------

---@param m integer
---@param n integer
---@return integer
local function rng(m, n)
  return math.random(m, n)
end

---@param text string
local function status(text)
  renoise.app():show_status(App.name .. ": " .. text)
  App.log(text)
end

---@param n integer
---@return string
local function count(n)
  return n == 1 and "1 note" or (n .. " notes")
end

---Randomize or shuffle the notes of a scope with the stored settings.
---@param scope ScopeId|nil Default: the dialog's Where for the active editor.
---@return integer changed Number of notes processed (0 when nothing ran).
function App.run(scope)
  local song = renoise.song()
  if not song then
    return 0
  end
  scope = scope or App.scope(App.editor())
  local settings = App.settings()
  local label = scopes.LABELS[scope]

  local options, problem = nil, nil
  if settings.how ~= scales.SHUFFLE then
    options, problem = notes.options(settings)
    if not options then
      status(problem or "Nothing to do.")
      return 0
    end
  end

  local columns, message = targets.collect(song, scope, App.prefs().ignore_muted.value)
  if not columns then
    status(message or "Nothing to do.")
    return 0
  end
  if #columns == 0 then
    status(("No notes found in %s."):format(label))
    return 0
  end

  if options == nil then
    local values = {}
    for i, column in ipairs(columns) do
      values[i] = column.note_value
    end
    local shuffled = notes.shuffle(values, rng)
    song:describe_undo "Shuffle Notes"
    for i, column in ipairs(columns) do
      column.note_value = shuffled[i]
    end
    status(("Shuffled %s in %s."):format(count(#columns), label))
  else
    song:describe_undo "Randomize Notes"
    for _, column in ipairs(columns) do
      column.note_value = notes.randomize(column.note_value, options, rng)
    end
    local what = settings.how
    if scales.uses_key(what) then
      what = scales.NOTE_NAMES[settings.key + 1] .. " " .. what
    end
    status(("Randomized %s in %s (%s)."):format(count(#columns), label, what))
  end
  return #columns
end

-- Dialogs --------------------------------------------------------------------

---@param name string
---@param dialog renoise.Dialog
---@param vb renoise.ViewBuilder
---@param root renoise.Views.View
---@param refresh fun()|nil
function App.register_dialog(name, dialog, vb, root, refresh)
  App.dialogs[name] = { dialog = dialog, vb = vb, root = root, refresh = refresh }
end

function App.close_dialogs()
  for name, entry in pairs(App.dialogs) do
    if entry.dialog.visible then
      entry.dialog:close()
    end
    App.dialogs[name] = nil
  end
end

---Bring the open dialog up to date, for example when the active editor changes.
local function refresh_dialog()
  local entry = App.dialogs.main
  if entry and entry.dialog.visible and entry.refresh then
    entry.refresh()
  end
end

---Guarded `refresh_dialog`, created once per `App.start` so `reg.notifier`
---sees the same function every time and registers it only once.
---@type fun()|nil
local guarded_refresh = nil

---Show the main dialog, creating it if needed.
function App.show_dialog()
  local existing = App.dialogs.main
  if existing and existing.dialog.visible then
    existing.dialog:show()
    return
  end
  -- Registered here and not in App.start: Renoise loads tools before it has
  -- finished starting, and refuses access to the application theme then
  -- ("can not access the application theme while the application
  -- initializes"). The dialog only opens after startup.
  if guarded_refresh then
    -- The Where popup follows the active editor.
    reg.notifier(renoise.app().window.active_middle_frame_observable, guarded_refresh)
    -- The direction buttons mix their colours from the theme.
    reg.notifier(renoise.app().theme_observable, guarded_refresh)
  end
  local ui = require "src.ui"
  local vb, root, refresh, key_handler = ui.build(App)
  local dialog = renoise.app():show_custom_dialog(App.dialog_title, root, key_handler)
  App.register_dialog("main", dialog, vb, root, refresh)
end

-- Lifecycle ------------------------------------------------------------------

function App.start()
  -- Seed once. Version 1.11 re-seeded with os.time() on every run, so two runs
  -- in the same second gave the same result.
  math.randomseed(os.time() + math.floor(os.clock() * 1000))
  math.random()

  for _, name in ipairs(App.menu_entries) do
    reg.menu { name = name, invoke = App.guard(App.show_dialog) }
  end
  for _, name in ipairs(App.dialog_keybindings) do
    reg.key {
      name = name,
      invoke = App.guard(function(repeated)
        if not repeated then
          App.show_dialog()
        end
      end),
    }
  end
  for _, binding in ipairs(App.scope_keybindings) do
    local scope = binding.scope
    reg.key {
      name = binding.name,
      invoke = App.guard(function(repeated)
        if not repeated then
          App.run(scope)
        end
      end),
    }
  end
  -- The dialog's app notifiers are registered by App.show_dialog. Do not touch
  -- renoise.app().theme here: it errors while Renoise is starting up.
  guarded_refresh = App.guard(refresh_dialog)
  -- Close dialogs when the song changes so no view keeps stale song references.
  reg.notifier(renoise.tool().app_new_document_observable, App.close_dialogs)
  App.log "started"
end

function App.stop()
  App.close_dialogs()
  local tool = renoise.tool()
  for _, name in ipairs(reg.menus) do
    if tool:has_menu_entry(name) then
      tool:remove_menu_entry(name)
    end
  end
  for _, name in ipairs(reg.keys) do
    if tool:has_keybinding(name) then
      tool:remove_keybinding(name)
    end
  end
  for _, n in ipairs(reg.notifiers) do
    -- The observable may belong to a song that no longer exists.
    pcall(function()
      if n.observable:has_notifier(n.fn) then
        n.observable:remove_notifier(n.fn)
      end
    end)
  end
  for _, fn in ipairs(reg.timers) do
    if tool:has_timer(fn) then
      tool:remove_timer(fn)
    end
  end
  deferred = {}
  if tool.app_idle_observable:has_notifier(run_deferred) then
    tool.app_idle_observable:remove_notifier(run_deferred)
  end
  reg.menus, reg.keys, reg.notifiers, reg.timers = {}, {}, {}, {}
  guarded_refresh = nil
  App.log "stopped"
end

return App
