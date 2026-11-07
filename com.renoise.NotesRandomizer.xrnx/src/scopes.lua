--[[
  Where to randomize. Pure Lua: no `renoise.*`, so `just test` can run it
  under plain LuaJIT.

  The Where popup lists the scopes of the editor that is active: the pattern
  editor or the phrase editor. Scopes are stored by id, so the list can change
  without breaking saved preferences.
]]

local M = {}

---@alias ScopeId "pattern_selection"|"track_in_pattern"|"track_in_song"|"whole_pattern"|"whole_song"|"phrase_selection"|"whole_phrase"

---@alias ScopeEditor "pattern"|"phrase"

---@type table<ScopeEditor, ScopeId[]>
M.BY_EDITOR = {
  pattern = {
    "pattern_selection",
    "track_in_pattern",
    "track_in_song",
    "whole_pattern",
    "whole_song",
  },
  phrase = { "phrase_selection", "whole_phrase" },
}

---@type table<ScopeId, string>
M.LABELS = {
  pattern_selection = "Selection in Pattern",
  track_in_pattern = "Track in Pattern",
  track_in_song = "Track in Song",
  whole_pattern = "Whole Pattern",
  whole_song = "Whole Song",
  phrase_selection = "Selection in Phrase",
  whole_phrase = "Whole Phrase",
}

---@param id string
---@return boolean
function M.is_phrase(id)
  return id == "phrase_selection" or id == "whole_phrase"
end

---Popup labels for an editor.
---@param editor ScopeEditor
---@return string[]
function M.labels(editor)
  local list = {}
  for i, id in ipairs(M.BY_EDITOR[editor]) do
    list[i] = M.LABELS[id]
  end
  return list
end

---Popup index of a scope id in an editor's list; 1 when it is not there.
---@param editor ScopeEditor
---@param id string
---@return integer
function M.index(editor, id)
  for i, s in ipairs(M.BY_EDITOR[editor]) do
    if s == id then
      return i
    end
  end
  return 1
end

---Scope id at a popup index; the first one when the index is out of range.
---@param editor ScopeEditor
---@param index integer
---@return ScopeId
function M.at(editor, index)
  local list = M.BY_EDITOR[editor]
  return list[index] or list[1]
end

return M
