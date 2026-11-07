--[[
  Selection bounds. Pure Lua: no `renoise.*`, so `just test` can run it under
  plain LuaJIT.

  Renoise describes a selection with `start_line`, `end_line`, `start_track`,
  `end_track`, `start_column` and `end_column` (`song.selection_in_pattern`;
  `song.selection_in_phrase` has no track fields). Column indexes count the
  visible note columns first, then the effect columns. Any field may be nil.
]]

local M = {}

---@class SelectionBounds
---@field start_line integer?
---@field end_line integer?
---@field start_track integer?
---@field end_track integer?
---@field start_column integer?
---@field end_column integer?

---@alias AnySelection SelectionBounds|PatternSelection|PhraseSelection

---An inclusive range of indexes.
---@class SelectionRange
---@field from integer
---@field to integer

---@param from integer
---@param to integer
---@return SelectionRange|nil
local function range(from, to)
  if from > to then
    return nil
  end
  return { from = from, to = to }
end

---The selected lines, clamped to 1..`number_of_lines`. Nil when none.
---@param sel AnySelection
---@param number_of_lines integer
---@return SelectionRange|nil
function M.lines(sel, number_of_lines)
  return range(
    math.max(1, sel.start_line or 1),
    math.min(number_of_lines, sel.end_line or number_of_lines)
  )
end

---The selected tracks, clamped to 1..`track_count`. Nil when none.
---@param sel AnySelection
---@param track_count integer
---@return SelectionRange|nil
function M.tracks(sel, track_count)
  return range(
    math.max(1, sel.start_track or 1),
    math.min(track_count, sel.end_track or track_count)
  )
end

---The selected note columns of one track (or of a phrase), clamped to
---1..`visible_note_columns`. Nil when none. The start column only applies to
---the first selected track and the end column only to the last one; tracks in
---between are selected in full.
---@param sel AnySelection
---@param track_index integer|nil Nil for a phrase, which has no tracks.
---@param visible_note_columns integer
---@return SelectionRange|nil
function M.note_columns(sel, track_index, visible_note_columns)
  local first, last = 1, visible_note_columns
  local is_first = track_index == nil or sel.start_track == nil or track_index == sel.start_track
  local is_last = track_index == nil or sel.end_track == nil or track_index == sel.end_track
  if is_first and sel.start_column then
    first = math.max(first, sel.start_column)
  end
  if is_last and sel.end_column then
    last = math.min(last, sel.end_column)
  end
  return range(first, last)
end

return M
