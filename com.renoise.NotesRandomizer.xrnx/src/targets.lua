--[[
  Collect the note columns a scope covers. Renoise side: it reads the song,
  and the caller writes the new notes back into the returned columns.

  Rules for every scope:
  * Only visible note columns count. Hidden columns can still hold notes.
  * Only note columns that hold a note (0..119) are returned; note-offs and
    empty columns are left alone.
  * With `ignore_muted`, muted tracks and muted note columns are skipped.
  * Song scopes visit each pattern of the sequence once.
  * An aliased pattern track is read through its source pattern, so the notes
    you hear are the ones that change, and each source is visited once.
  * Script phrases have no note lines to edit, so they are refused.
]]

local notes = require "src.notes"
local scopes = require "src.scopes"
local selection = require "src.selection"

local M = {}

---@class TargetRange
---@field lines_from integer
---@field lines_to integer
---@field cols_from integer
---@field cols_to integer

---@class Collector
---@field columns renoise.NoteColumn[]
---@field seen table<string, boolean>
---@field ignore_muted boolean

---@param out Collector
---@param lines renoise.PatternLine[]
---@param cols_from integer
---@param cols_to integer
---@param is_muted fun(column: integer): boolean
local function add_lines(out, lines, cols_from, cols_to, is_muted)
  for _, line in ipairs(lines) do
    if not line.is_empty then
      for c = cols_from, cols_to do
        if not (out.ignore_muted and is_muted(c)) then
          local column = line:note_column(c)
          if notes.is_note(column.note_value) then
            out.columns[#out.columns + 1] = column
          end
        end
      end
    end
  end
end

---Follow an alias to the pattern that holds the data.
---@param song renoise.Song
---@param pattern_index integer
---@param track_index integer
---@return integer
local function source_pattern(song, pattern_index, track_index)
  local index = pattern_index
  for _ = 1, #song.patterns do
    local alias = song:pattern(index):track(track_index).alias_pattern_index
    if alias == 0 or alias == index then
      break
    end
    index = alias
  end
  return index
end

---Add one pattern track, or part of it.
---@param out Collector
---@param song renoise.Song
---@param pattern_index integer
---@param track_index integer
---@param range TargetRange|nil Nil for the whole pattern track.
local function add_pattern_track(out, song, pattern_index, track_index, range)
  local track = song.tracks[track_index]
  local visible = track.visible_note_columns
  if track.type ~= renoise.Track.TRACK_TYPE_SEQUENCER or visible == 0 then
    return
  end
  if out.ignore_muted and track.mute_state ~= renoise.Track.MUTE_STATE_ACTIVE then
    return
  end
  local source = source_pattern(song, pattern_index, track_index)
  local seen_key = source .. ":" .. track_index
  if range == nil then
    if out.seen[seen_key] then
      return
    end
    out.seen[seen_key] = true
  end
  local pattern_track = song:pattern(source):track(track_index)
  if pattern_track.is_empty then
    return
  end
  local number_of_lines = song:pattern(source).number_of_lines
  local lines_from, lines_to, cols_from, cols_to = 1, number_of_lines, 1, visible
  if range then
    lines_from = range.lines_from
    lines_to = math.min(range.lines_to, number_of_lines)
    cols_from = range.cols_from
    cols_to = math.min(range.cols_to, visible)
  end
  if lines_from > lines_to or cols_from > cols_to then
    return
  end
  add_lines(out, pattern_track:lines_in_range(lines_from, lines_to), cols_from, cols_to, function(c)
    return track:column_is_muted(c)
  end)
end

---Pattern indexes of the sequence, each one once, in sequence order.
---@param song renoise.Song
---@return integer[]
local function song_patterns(song)
  local list, seen = {}, {}
  for _, index in ipairs(song.sequencer.pattern_sequence) do
    if not seen[index] then
      seen[index] = true
      list[#list + 1] = index
    end
  end
  return list
end

---@param out Collector
---@param song renoise.Song
---@return string|nil message
local function add_pattern_selection(out, song)
  local sel = song.selection_in_pattern
  if sel == nil then
    return "Nothing is selected in the pattern editor."
  end
  local pattern_index = song.selected_pattern_index
  local lines = selection.lines(sel, song:pattern(pattern_index).number_of_lines)
  local tracks = selection.tracks(sel, #song.tracks)
  if lines == nil or tracks == nil then
    return "Nothing is selected in the pattern editor."
  end
  for t = tracks.from, tracks.to do
    local cols = selection.note_columns(sel, t, song.tracks[t].visible_note_columns)
    if cols then
      add_pattern_track(out, song, pattern_index, t, {
        lines_from = lines.from,
        lines_to = lines.to,
        cols_from = cols.from,
        cols_to = cols.to,
      })
    end
  end
  return nil
end

---@param out Collector
---@param song renoise.Song
---@param scope ScopeId
---@return string|nil message
local function add_phrase(out, song, scope)
  local phrase = song.selected_phrase
  if phrase == nil then
    return "No phrase is selected."
  end
  if phrase.playback_mode == renoise.InstrumentPhrase.PLAY_SCRIPT then
    return "The selected phrase is a script phrase. Only note phrases can be randomized."
  end
  local visible = phrase.visible_note_columns
  local lines_from, lines_to, cols_from, cols_to = 1, phrase.number_of_lines, 1, visible
  if scope == "phrase_selection" then
    local sel = song.selection_in_phrase
    if sel == nil then
      return "Nothing is selected in the phrase editor."
    end
    local lines = selection.lines(sel, phrase.number_of_lines)
    local cols = selection.note_columns(sel, nil, visible)
    if lines == nil or cols == nil then
      return "No note columns are selected in the phrase editor."
    end
    lines_from, lines_to, cols_from, cols_to = lines.from, lines.to, cols.from, cols.to
  end
  add_lines(out, phrase:lines_in_range(lines_from, lines_to), cols_from, cols_to, function(c)
    return phrase:column_is_muted(c)
  end)
  return nil
end

---The note columns with a note in them that `scope` covers.
---Returns nil and a message when the scope has nothing to work on, for
---example when nothing is selected.
---@param song renoise.Song
---@param scope ScopeId
---@param ignore_muted boolean
---@return renoise.NoteColumn[]|nil columns, string|nil message
function M.collect(song, scope, ignore_muted)
  ---@type Collector
  local out = { columns = {}, seen = {}, ignore_muted = ignore_muted }
  local message = nil
  if scopes.is_phrase(scope) then
    message = add_phrase(out, song, scope)
  elseif scope == "pattern_selection" then
    message = add_pattern_selection(out, song)
  elseif scope == "track_in_pattern" then
    add_pattern_track(out, song, song.selected_pattern_index, song.selected_track_index, nil)
  elseif scope == "whole_pattern" then
    for t = 1, #song.tracks do
      add_pattern_track(out, song, song.selected_pattern_index, t, nil)
    end
  elseif scope == "track_in_song" then
    for _, p in ipairs(song_patterns(song)) do
      add_pattern_track(out, song, p, song.selected_track_index, nil)
    end
  elseif scope == "whole_song" then
    for _, p in ipairs(song_patterns(song)) do
      for t = 1, #song.tracks do
        add_pattern_track(out, song, p, t, nil)
      end
    end
  else
    error("unknown scope: " .. tostring(scope))
  end
  if message then
    return nil, message
  end
  return out.columns, nil
end

return M
