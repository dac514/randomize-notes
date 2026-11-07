--[[
  Note randomizing and shuffling. Pure Lua: no `renoise.*`, no Renoise
  additions to the standard library, so `just test` can run it under plain
  LuaJIT.

  Notes are Renoise `note_value` integers: 0 is C-0 and 119 is B-9. The pitch
  class is `value % 12` and the octave is `math.floor(value / 12)`. Every
  function here returns a value in 0..119 for a note in 0..119.

  The random source is passed in, so tests can make it predictable. It is
  called like `math.random(m, n)` and returns an integer in m..n.
]]

local scales = require "src.scales"

local M = {}

M.LOWEST = 0
M.HIGHEST = 119

---Direction names of the Nearest Neighbour switch, by switch index.
M.SHIFTS = { "rand", "up", "down" }

---@alias NotesRng fun(m: integer, n: integer): integer

---@alias NotesShift "rand"|"up"|"down"

---Settings as the tool stores them, in plain Lua values.
---@class NotesSettings
---@field how string A name from `scales.modes()`.
---@field key integer Pitch class 0..11.
---@field custom string 12 characters, "1" for each Custom note.
---@field neighbour boolean
---@field shift NotesShift
---@field preserve_notes boolean
---@field preserve_octaves boolean
---@field octave_min integer 0..9
---@field octave_max integer 0..9

---Everything `randomize` needs, already resolved.
---@class NotesOptions
---@field pitch_classes integer[] Sorted, never empty.
---@field in_scale table<integer, boolean> Set of `pitch_classes`.
---@field neighbour boolean
---@field shift NotesShift
---@field preserve_notes boolean
---@field preserve_octaves boolean
---@field octave_min integer
---@field octave_max integer

---@param value any
---@return boolean
function M.is_note(value)
  return type(value) == "number" and value >= M.LOWEST and value <= M.HIGHEST
end

---@param n integer
---@param lo integer
---@param hi integer
---@return integer
local function clamp(n, lo, hi)
  if n < lo then
    return lo
  elseif n > hi then
    return hi
  end
  return n
end

---Resolve stored settings into options for `randomize`.
---Returns nil and a message when the settings cannot randomize anything.
---Chaos allows every note, so Nearest Neighbour and Preserve Notes do not
---apply to it and are switched off here.
---@param settings NotesSettings
---@return NotesOptions|nil options, string|nil message
function M.options(settings)
  local pcs = scales.pitch_classes(settings.how, settings.key, settings.custom)
  if pcs == nil then
    return nil, "Shuffle does not use a scale"
  end
  if #pcs == 0 then
    return nil, "The Custom scale has no notes. Click the piano keys to add some."
  end
  local in_scale = {}
  for _, pc in ipairs(pcs) do
    in_scale[pc] = true
  end
  local chaos = settings.how == scales.CHAOS
  local lo = clamp(math.floor(settings.octave_min or 0), 0, 9)
  local hi = clamp(math.floor(settings.octave_max or 9), 0, 9)
  if lo > hi then
    lo, hi = hi, lo
  end
  return {
    pitch_classes = pcs,
    in_scale = in_scale,
    neighbour = settings.neighbour and not chaos or false,
    shift = settings.shift or "rand",
    preserve_notes = settings.preserve_notes and not chaos or false,
    preserve_octaves = settings.preserve_octaves and true or false,
    octave_min = lo,
    octave_max = hi,
  }
end

---The closest note above (`step` = 1) or below (`step` = -1) `value` whose
---pitch class is in the scale. Nil when there is none inside 0..119.
---@param value integer
---@param in_scale table<integer, boolean>
---@param step integer 1 or -1
---@return integer|nil
local function scan(value, in_scale, step)
  local v = value + step
  while v >= M.LOWEST and v <= M.HIGHEST do
    if in_scale[v % 12] then
      return v
    end
    v = v + step
  end
  return nil
end

---Move a note to the next scale note up or down. At the edge of the note
---range, where there is no scale note in that direction, a note in the scale
---stays where it is and a note outside the scale goes the other way. So the
---result is always in the scale and in 0..119.
---@param value integer
---@param in_scale table<integer, boolean>
---@param shift "up"|"down"
---@return integer
function M.neighbour(value, in_scale, shift)
  local step = shift == "down" and -1 or 1
  local found = scan(value, in_scale, step)
  if found then
    return found
  end
  if in_scale[value % 12] then
    return value
  end
  return scan(value, in_scale, -step) or value
end

---Return a new note for `value`. Values outside 0..119 (note-off, empty) are
---returned unchanged.
---@param value integer
---@param options NotesOptions
---@param rng NotesRng
---@return integer
function M.randomize(value, options, rng)
  if not M.is_note(value) then
    return value
  end
  local pc = value % 12
  local octave = math.floor(value / 12)
  local keep = options.preserve_notes and options.in_scale[pc]

  if options.neighbour then
    local moved = value
    if not keep then
      local shift = options.shift
      if shift == "rand" then
        shift = rng(1, 2) == 1 and "up" or "down"
      end
      moved = M.neighbour(value, options.in_scale, shift --[[@as "up"|"down"]])
    end
    if options.preserve_octaves then
      return moved
    end
    pc = moved % 12
  elseif not keep then
    pc = options.pitch_classes[rng(1, #options.pitch_classes)]
  end

  if not options.preserve_octaves then
    octave = rng(options.octave_min, options.octave_max)
  end
  return pc + 12 * octave
end

---Return the values in a random order (Fisher-Yates). The input is not changed.
---@param values integer[]
---@param rng NotesRng
---@return integer[]
function M.shuffle(values, rng)
  local out = {}
  for i = 1, #values do
    out[i] = values[i]
  end
  for i = #out, 2, -1 do
    local j = rng(1, i)
    out[i], out[j] = out[j], out[i]
  end
  return out
end

return M
