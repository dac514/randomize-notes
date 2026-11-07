--[[
  Selection bounds, scopes and piano geometry.
  Run with `just test tests/selection_test.lua`.
]]

local t = require "tests.helper"
local selection = require "src.selection"
local scopes = require "src.scopes"
local keyboard = require "src.keyboard"

---@param r SelectionRange|nil
---@return string
local function range(r)
  if r == nil then
    return "none"
  end
  return r.from .. ".." .. r.to
end

-- Lines and tracks ---------------------------------------------------------------

t.eq(range(selection.lines({ start_line = 3, end_line = 9 }, 64)), "3..9", "lines")
t.eq(range(selection.lines({ start_line = 3, end_line = 99 }, 16)), "3..16", "lines: clamped")
t.eq(range(selection.lines({}, 16)), "1..16", "lines: empty bounds select all")
t.eq(range(selection.lines({ start_line = 20 }, 16)), "none", "lines: past the end")
t.eq(range(selection.tracks({ start_track = 2, end_track = 4 }, 8)), "2..4", "tracks")
t.eq(range(selection.tracks({}, 8)), "1..8", "tracks: empty bounds select all")

-- Note columns -------------------------------------------------------------------

local one = { start_track = 2, end_track = 2, start_column = 2, end_column = 3 }
t.eq(range(selection.note_columns(one, 2, 4)), "2..3", "one track, columns 2..3")
-- 1.11 bug 6: only visible note columns count.
local wide = { start_track = 1, end_track = 1, start_column = 1, end_column = 12 }
t.eq(range(selection.note_columns(wide, 1, 1)), "1..1", "clamped to the visible note columns")
local fx = { start_track = 1, end_track = 1, start_column = 5, end_column = 6 }
t.eq(range(selection.note_columns(fx, 1, 4)), "none", "effect columns only")

local multi = { start_track = 1, end_track = 3, start_column = 3, end_column = 2 }
t.eq(range(selection.note_columns(multi, 1, 4)), "3..4", "first track starts at start_column")
t.eq(range(selection.note_columns(multi, 2, 4)), "1..4", "middle track in full")
t.eq(range(selection.note_columns(multi, 3, 4)), "1..2", "last track ends at end_column")

local phrase = { start_line = 1, end_line = 8, start_column = 2, end_column = 7 }
t.eq(range(selection.note_columns(phrase, nil, 3)), "2..3", "phrase: no tracks")
t.eq(range(selection.note_columns({}, 1, 2)), "1..2", "no column bounds: all visible")
t.eq(range(selection.note_columns({}, 1, 0)), "none", "track without note columns")

-- Scopes -------------------------------------------------------------------------

t.eq(#scopes.labels "pattern", 5, "scopes: five pattern scopes")
t.eq(scopes.labels("phrase")[2], "Whole Phrase", "scopes: phrase labels")
t.eq(scopes.index("pattern", "whole_song"), 5, "scopes: index")
t.eq(scopes.index("phrase", "whole_song"), 1, "scopes: unknown id falls back to 1")
t.eq(scopes.at("pattern", 2), "track_in_pattern", "scopes: at")
t.eq(scopes.at("phrase", 9), "phrase_selection", "scopes: at out of range")
t.check(scopes.is_phrase "whole_phrase", "scopes: is_phrase")
t.check(not scopes.is_phrase "whole_pattern", "scopes: is_phrase pattern")
for id, label in pairs(scopes.LABELS) do
  t.check(type(label) == "string" and #label > 0, "scopes: label for " .. id)
end

-- Piano geometry ---------------------------------------------------------------

local kb = keyboard.layout(140, 50, 2)
t.eq(#kb.whites, 14, "keyboard: 14 white keys")
t.eq(#kb.blacks, 10, "keyboard: 10 black keys")
t.eq(kb.white_width, 10, "keyboard: white key width")
t.eq(kb.whites[3].pc, 4, "keyboard: third white key is E")
t.eq(kb.whites[8].octave, 1, "keyboard: eighth white key is in the second octave")

local key = keyboard.hit(kb, 10, 5)
t.eq(key and key.pc, 1, "hit: C# at the top of the C/D edge")
key = keyboard.hit(kb, 10, 45)
t.eq(key and key.pc, 2, "hit: D below the black key")
key = keyboard.hit(kb, 1, 45)
t.eq(key and key.pc, 0, "hit: C")
key = keyboard.hit(kb, 75, 45)
t.eq(key and key.pc .. "/" .. key.octave, "0/1", "hit: C of the second octave")
key = keyboard.hit(kb, 28, 5)
t.eq(key and key.pc, 4, "hit: E has no black key on its right")
t.eq(keyboard.hit(kb, 150, 10), nil, "hit: outside")

t.done()
