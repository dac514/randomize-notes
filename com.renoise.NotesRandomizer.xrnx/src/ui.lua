--[[
  ViewBuilder UI for the main dialog. Returns the builder (so the dev bridge
  can map ids to views), the root view, a refresh function and the dialog's
  key handler.

  Options that do not apply to the current mode are greyed out, not hidden,
  so the dialog keeps its size.
]]

local piano = require "src.piano"
local scales = require "src.scales"
local scopes = require "src.scopes"

local M = {}

local MARGIN = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN
local SECTION = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING
local ROW = 4

local WIDTH = 224 -- 14 white keys of 16
local LABEL_WIDTH = 44
local FIELD_WIDTH = WIDTH - LABEL_WIDTH
local PIANO_HEIGHT = 60
local INDENT = 22
local OCTAVE_WIDTH = 44
-- Longest note list, in characters, that fits WIDTH in the mono font. Renoise
-- 3.5 draws mono text at about 6.1 pixels per character.
local CAPTION_CHARS = 34
local BUTTON_HEIGHT = renoise.ViewBuilder.DEFAULT_DIALOG_BUTTON_HEIGHT + 4

local OCTAVES = { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" }

---@param app table The application module (`src/app.lua`).
---@return renoise.ViewBuilder vb
---@return renoise.Views.View root
---@return fun() refresh
---@return fun(dialog: renoise.Dialog, key: KeyEvent): KeyEvent? key_handler
function M.build(app)
  local vb = renoise.ViewBuilder()
  local prefs = app.prefs() --[[@as NotesRandomizerPreferences]]
  local modes = scales.modes()
  local editor = app.editor() --[[@as ScopeEditor]]
  -- Set while the code changes views, so their notifiers do not write back.
  local updating = false

  local function mode_index(how)
    for i, name in ipairs(modes) do
      if name == how then
        return i
      end
    end
    return 1
  end

  local function current_how()
    return app.settings().how
  end

  ---@type fun()
  local refresh

  local function label(text)
    return vb:text { text = text, width = LABEL_WIDTH }
  end

  ---A checkbox with a text label. The label is greyed out with the checkbox.
  ---@type table<string, { box: renoise.Views.CheckBox, text: renoise.Views.Text }>
  local checkboxes = {}

  ---@param id string
  ---@param text string
  ---@param observable renoise.Document.ObservableBoolean
  ---@param tooltip string|nil Shown on the checkbox and on its label.
  local function option(id, text, observable, tooltip)
    local box = vb:checkbox {
      id = id,
      bind = observable,
      tooltip = tooltip,
      notifier = function()
        if refresh then
          refresh()
        end
      end,
    }
    local caption_text = vb:text { id = id .. "_text", text = text, tooltip = tooltip }
    checkboxes[id] = { box = box, text = caption_text }
    return vb:row { box, caption_text }
  end

  -- Where -----------------------------------------------------------------

  local where = vb:popup {
    id = "where",
    width = FIELD_WIDTH,
    items = scopes.labels(editor),
    value = scopes.index(editor, app.scope(editor)),
    tooltip = "What to change. The list follows the editor you are in: pattern or phrase.",
    notifier = function(index)
      if updating then
        return
      end
      local id = scopes.at(editor, index)
      if editor == "phrase" then
        prefs.where_phrase.value = id
      else
        prefs.where_pattern.value = id
      end
    end,
  }

  -- How and Key -------------------------------------------------------------

  local how = vb:popup {
    id = "how",
    width = FIELD_WIDTH,
    items = modes,
    value = mode_index(current_how()),
    tooltip = "Shuffle reorders the notes. Chaos uses all 12 notes. Custom uses the notes you click on the piano.",
    notifier = function(index)
      local previous = current_how()
      local next_how = modes[index]
      prefs.how.value = next_how
      -- A new Custom scale starts from the scale that was shown before.
      if next_how == scales.CUSTOM and not prefs.custom.value:find "1" then
        local settings = app.settings()
        local pcs = scales.pitch_classes(previous, settings.key, settings.custom)
        if pcs and #pcs < 12 then
          prefs.custom.value = scales.to_mask(pcs)
        end
      end
      refresh()
    end,
  }

  local key = vb:popup {
    id = "key",
    width = FIELD_WIDTH,
    items = scales.NOTE_NAMES,
    bind = prefs.key,
    tooltip = "The root note of the scale. You can also click a piano key.",
    notifier = function()
      if refresh then
        refresh()
      end
    end,
  }

  -- Piano -------------------------------------------------------------------

  ---@return PianoState
  local function piano_state()
    local s = app.settings()
    return {
      pitch_classes = scales.pitch_classes(s.how, s.key, s.custom),
      root = scales.root(s.how, s.key),
    }
  end

  local keys = vb:canvas {
    id = "piano",
    width = WIDTH,
    height = PIANO_HEIGHT,
    mode = "transparent",
    render = function(ctx)
      piano.render(ctx, piano_state())
    end,
    mouse_events = { "down" },
    mouse_handler = app.guard(function(event)
      if event.type ~= "down" or event.button ~= "left" then
        return
      end
      local pc = piano.hit(WIDTH, PIANO_HEIGHT, event.position.x, event.position.y)
      if pc == nil then
        return
      end
      local h = current_how()
      if h == scales.CUSTOM then
        prefs.custom.value = scales.toggle(app.settings().custom, pc)
        refresh()
      elseif scales.uses_key(h) then
        prefs.key.value = pc + 1 -- the Key popup's notifier refreshes
      end
    end),
  }

  local caption = vb:text {
    id = "scale_notes",
    width = WIDTH,
    align = "center",
    text = "",
  }

  -- Options -----------------------------------------------------------------

  -- Rand / Up / Down, built from buttons and not from a switch. Renoise dims
  -- the label of an inactive switch on top of its accent colour, which makes
  -- it hard to read. These buttons stay active and draw their own muted look
  -- while the option is off; clicks are ignored then.
  local shift_on = false
  local shift_width = WIDTH - INDENT - 2 * ROW - MARGIN
  local segment = math.floor(shift_width / 3)
  local shift_styles = { "rounded_left", "normal", "rounded_right" }
  ---@type renoise.Views.Button[]
  local shift_buttons = {}
  for i, text in ipairs { "Rand", "Up", "Down" } do
    shift_buttons[i] = vb:button {
      id = "shift_" .. text:lower(),
      text = text,
      style = shift_styles[i],
      width = i < 3 and segment or shift_width - 2 * segment,
      tooltip = "Move each note to the next scale note up, down, or a random one of the two.",
      notifier = function()
        if shift_on then
          prefs.neighbour_shift.value = i
          refresh()
        end
      end,
    }
  end
  local shift =
    vb:row { id = "neighbour_shift", shift_buttons[1], shift_buttons[2], shift_buttons[3] }

  ---@param a RGBColor
  ---@param b RGBColor
  ---@param t number 0 gives `a`, 1 gives `b`.
  ---@return RGBColor
  local function mix(a, b, t)
    return {
      math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
      math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
      math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
    }
  end

  local THEME_DEFAULT = { 0, 0, 0 } -- tells a button to use the theme colours again

  ---Colour the direction buttons. On: like a Renoise switch. Off: a muted
  ---accent behind the chosen direction, dimmed text that stays readable.
  local function paint_shift()
    local selected = prefs.neighbour_shift.value
    local c = renoise.app().theme.colors
    for i, b in ipairs(shift_buttons) do
      if shift_on and i == selected then
        b.color = "selected_button_back"
        b.secondary_color = "selected_button_font"
      elseif shift_on then
        b.color = THEME_DEFAULT
        b.secondary_color = THEME_DEFAULT
      elseif i == selected then
        b.color = mix(c.body_back, c.selected_button_back, 0.45)
        b.secondary_color = c.main_font
      else
        b.color = mix(c.button_back, c.body_back, 0.5)
        b.secondary_color = mix(c.button_font, c.body_back, 0.5)
      end
    end
  end

  ---@type renoise.Views.Popup, renoise.Views.Popup
  local octave_min, octave_max

  local function clamp_octaves(changed)
    if updating then
      return
    end
    local lo, hi = prefs.octave_min.value, prefs.octave_max.value
    if lo > hi then
      updating = true
      if changed == "min" then
        prefs.octave_max.value = lo
        octave_max.value = lo + 1
      else
        prefs.octave_min.value = hi
        octave_min.value = hi + 1
      end
      updating = false
    end
  end

  octave_min = vb:popup {
    id = "octave_min",
    width = OCTAVE_WIDTH,
    items = OCTAVES,
    value = prefs.octave_min.value + 1,
    notifier = function(index)
      if not updating then
        prefs.octave_min.value = index - 1
        clamp_octaves "min"
      end
    end,
  }

  octave_max = vb:popup {
    id = "octave_max",
    width = OCTAVE_WIDTH,
    items = OCTAVES,
    value = prefs.octave_max.value + 1,
    notifier = function(index)
      if not updating then
        prefs.octave_max.value = index - 1
        clamp_octaves "max"
      end
    end,
  }

  local octaves_text = vb:text { id = "octaves_text", text = "Octaves" }
  local octaves_to_text = vb:text { id = "octaves_to_text", text = "to" }

  local options = vb:column {
    style = "group",
    margin = MARGIN,
    spacing = ROW,
    width = WIDTH,
    option("neighbour", "Nearest neighbour", prefs.neighbour),
    vb:row {
      vb:space { width = INDENT },
      shift,
    },
    option(
      "preserve_notes",
      "Preserve notes in scale",
      prefs.preserve_notes,
      "Keep the notes that are already in the scale and change only the others. "
        .. "With Preserve octaves off, a kept note can still move to another octave."
    ),
    option(
      "preserve_octaves",
      "Preserve octaves",
      prefs.preserve_octaves,
      "Keep each note in its own octave. "
        .. "Turn it off to pick a random octave in the range below."
    ),
    vb:row {
      spacing = ROW,
      vb:space { width = INDENT - ROW },
      octaves_text,
      octave_min,
      octaves_to_text,
      octave_max,
    },
    option("ignore_muted", "Ignore muted tracks and columns", prefs.ignore_muted),
  }

  local button = vb:button {
    id = "randomize",
    text = "Randomize",
    width = WIDTH,
    height = BUTTON_HEIGHT,
    notifier = app.guard(function()
      app.run()
    end),
  }

  local root = vb:column {
    id = "root",
    margin = MARGIN,
    spacing = SECTION,
    vb:column {
      spacing = ROW,
      vb:row { label "Where", where },
      vb:row { label "How", how },
      vb:row { label "Key", key },
    },
    vb:column {
      spacing = ROW,
      keys,
      caption,
    },
    options,
    button,
  }

  ---Grey out an option and its label.
  local function set_active(id, active)
    checkboxes[id].box.active = active
    checkboxes[id].text.style = active and "normal" or "disabled"
  end

  function refresh()
    local s = app.settings()
    local is_shuffle = s.how == scales.SHUFFLE
    local uses_scale = not is_shuffle and s.how ~= scales.CHAOS

    -- Where follows the active editor.
    local now = app.editor() --[[@as ScopeEditor]]
    if now ~= editor then
      editor = now
      updating = true
      where.items = scopes.labels(editor)
      where.value = scopes.index(editor, app.scope(editor))
      updating = false
    end

    key.active = scales.uses_key(s.how)
    set_active("neighbour", uses_scale)
    shift_on = uses_scale and s.neighbour
    paint_shift()
    set_active("preserve_notes", uses_scale)
    set_active("preserve_octaves", not is_shuffle)
    local octaves_active = not is_shuffle and not s.preserve_octaves
    octave_min.active = octaves_active
    octave_max.active = octaves_active
    octaves_text.style = octaves_active and "normal" or "disabled"
    octaves_to_text.style = octaves_active and "normal" or "disabled"

    local pcs = scales.pitch_classes(s.how, s.key, s.custom)
    local text, font, style = "", "normal", "disabled"
    if is_shuffle then
      text = "Shuffle mixes up the notes that are there"
      keys.tooltip = ""
    elseif s.how == scales.CHAOS then
      text = "All 12 notes"
      keys.tooltip = ""
    elseif pcs and #pcs == 0 then
      text = "Click the keys to pick notes"
      keys.tooltip = "Click a key to add or remove that note."
    else
      text = scales.caption(scales.from_root(pcs or {}, scales.root(s.how, s.key)), CAPTION_CHARS)
      font, style = "mono", "normal"
      keys.tooltip = s.how == scales.CUSTOM and "Click a key to add or remove that note."
        or "Click a key to make it the root."
    end
    -- Renoise widens a text view to fit new text and never shrinks it, and the
    -- dialog grows with it. Set the font before the text, then restore the
    -- fixed width.
    caption.font = font
    caption.style = style
    caption.text = text
    caption.width = WIDTH
    button.text = is_shuffle and "Shuffle" or "Randomize"
    keys:update()
  end

  ---Esc closes, Return runs, Up and Down change How, Left and Right change Key.
  ---@param dialog renoise.Dialog
  ---@param k KeyEvent
  ---@return KeyEvent?
  local function key_handler(dialog, k)
    local mods = k.modifier_flags
    if mods and (mods.shift or mods.control or mods.alt or mods.meta) then
      return k
    end
    if k.name == "esc" then
      dialog:close()
    elseif k.name == "return" then
      app.guard(app.run)()
    elseif k.name == "up" then
      how.value = math.max(1, how.value - 1)
    elseif k.name == "down" then
      how.value = math.min(#modes, how.value + 1)
    elseif k.name == "left" then
      if key.active then
        key.value = math.max(1, key.value - 1)
      end
    elseif k.name == "right" then
      if key.active then
        key.value = math.min(12, key.value + 1)
      end
    else
      return k
    end
    return nil
  end

  refresh()
  return vb, root, refresh, key_handler
end

return M
