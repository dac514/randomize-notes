--[[
  Scales and keys. Pure Lua: no `renoise.*`, no Renoise additions to the
  standard library, so `just test` can run it under plain LuaJIT.

  A pitch class is an integer from 0 (C) to 11 (B). A key is a pitch class too.

  The named scales are Renoise's own list (the instrument "Scale" menu,
  `trigger_options.available_scale_modes`), in the same order. Each mask has
  12 characters for C, C#, D ... B, rooted on C. The masks match the
  `SCALE_MODES` table of Renoise's pattrns library (renoise/pattrns,
  `src/note/scale.rs`) and the xLib and Duplex tables by the Renoise team.
]]

local M = {}

---Note names as shown in the Key popup, the piano caption and status messages.
M.NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

M.SHUFFLE = "Shuffle"
M.CHAOS = "Chaos"
M.CUSTOM = "Custom"

---An empty Custom scale, as stored in the preferences.
M.EMPTY_CUSTOM = "000000000000"

---@type { name: string, mask: string }[]
local SCALES = {
  { name = "Natural Major", mask = "101011010101" },
  { name = "Natural Minor", mask = "101101011010" },
  { name = "Pentatonic Major", mask = "101010010100" },
  { name = "Pentatonic Minor", mask = "100101010010" },
  { name = "Pentatonic Egyptian", mask = "101001010010" },
  { name = "Blues Major", mask = "101110010100" },
  { name = "Blues Minor", mask = "100101110010" },
  { name = "Whole Tone", mask = "101010101010" },
  { name = "Augmented", mask = "100110011001" },
  { name = "Prometheus", mask = "101010100110" },
  { name = "Tritone", mask = "110010110010" },
  { name = "Harmonic Major", mask = "101011011001" },
  { name = "Harmonic Minor", mask = "101101011001" },
  { name = "Melodic Minor", mask = "101101010101" },
  { name = "All Minor", mask = "101101011111" },
  { name = "Dorian", mask = "101101010110" },
  { name = "Phrygian", mask = "110101011010" },
  { name = "Phrygian Dominant", mask = "110011011010" },
  { name = "Lydian", mask = "101010110101" },
  { name = "Lydian Augmented", mask = "101010101101" },
  { name = "Mixolydian", mask = "101011010110" },
  { name = "Locrian", mask = "110101101010" },
  { name = "Locrian Major", mask = "101011101010" },
  { name = "Super Locrian", mask = "110110101010" },
  { name = "Neapolitan Major", mask = "110101010101" },
  { name = "Neapolitan Minor", mask = "110101011001" },
  { name = "Romanian Minor", mask = "101100110110" },
  { name = "Spanish Gypsy", mask = "110011011001" },
  { name = "Hungarian Gypsy", mask = "101100111001" },
  { name = "Enigmatic", mask = "110010101011" },
  { name = "Overtone", mask = "101010110110" },
  { name = "Diminished Half", mask = "110110110110" },
  { name = "Diminished Whole", mask = "101101101101" },
  { name = "Spanish Eight-Tone", mask = "110111101010" },
  { name = "Nine-Tone Scale", mask = "101110111101" },
}

---@type table<string, string>
local MASKS = {}
for _, s in ipairs(SCALES) do
  MASKS[s.name] = s.mask
end

---Every entry of the How popup, in order: Shuffle, Chaos, Custom, then the
---named scales.
---@return string[]
function M.modes()
  local list = { M.SHUFFLE, M.CHAOS, M.CUSTOM }
  for _, s in ipairs(SCALES) do
    list[#list + 1] = s.name
  end
  return list
end

---The named scales only (Renoise's list).
---@return string[]
function M.scale_names()
  local list = {}
  for _, s in ipairs(SCALES) do
    list[#list + 1] = s.name
  end
  return list
end

---@param how string
---@return boolean
function M.is_mode(how)
  return how == M.SHUFFLE or how == M.CHAOS or how == M.CUSTOM or MASKS[how] ~= nil
end

---True for the named scales, the only modes where the Key matters.
---@param how string
---@return boolean
function M.uses_key(how)
  return MASKS[how] ~= nil
end

---Turn a 12-character mask ("1" = in the scale) into sorted pitch classes,
---transposed by `key`.
---@param mask string
---@param key integer Pitch class 0..11.
---@return integer[]
local function from_mask(mask, key)
  local set = {}
  for i = 1, 12 do
    if mask:sub(i, i) == "1" then
      set[(i - 1 + key) % 12] = true
    end
  end
  local list = {}
  for pc = 0, 11 do
    if set[pc] then
      list[#list + 1] = pc
    end
  end
  return list
end

---The pitch classes a mode allows, sorted from C to B.
---Returns nil for Shuffle, which does not use a scale. A Custom scale with no
---notes returns an empty list.
---@param how string A name from `modes()`.
---@param key integer Pitch class 0..11. Used by the named scales only.
---@param custom string|nil 12 characters, "1" for each Custom note (C first).
---@return integer[]|nil
function M.pitch_classes(how, key, custom)
  if how == M.SHUFFLE then
    return nil
  elseif how == M.CHAOS then
    return from_mask("111111111111", 0)
  elseif how == M.CUSTOM then
    return from_mask(custom or M.EMPTY_CUSTOM, 0)
  end
  local mask = MASKS[how]
  assert(mask, "unknown scale: " .. tostring(how))
  return from_mask(mask, key % 12)
end

---The root to mark on the piano: the key for named scales, nil otherwise.
---@param how string
---@param key integer
---@return integer|nil
function M.root(how, key)
  if M.uses_key(how) then
    return key % 12
  end
  return nil
end

---Turn pitch classes into a 12-character Custom mask.
---@param pitch_classes integer[]
---@return string
function M.to_mask(pitch_classes)
  local chars = {}
  for i = 1, 12 do
    chars[i] = "0"
  end
  for _, pc in ipairs(pitch_classes) do
    chars[pc % 12 + 1] = "1"
  end
  return table.concat(chars)
end

---Flip one note of a Custom mask.
---@param mask string
---@param pc integer Pitch class 0..11.
---@return string
function M.toggle(mask, pc)
  local i = pc % 12 + 1
  local flipped = mask:sub(i, i) == "1" and "0" or "1"
  return mask:sub(1, i - 1) .. flipped .. mask:sub(i + 1)
end

---The same pitch classes, starting at `root` and going up. Unchanged when
---`root` is nil or not in the list.
---@param pitch_classes integer[]
---@param root integer|nil
---@return integer[]
function M.from_root(pitch_classes, root)
  local start = nil
  for i, pc in ipairs(pitch_classes) do
    if pc == root then
      start = i
    end
  end
  if start == nil then
    return pitch_classes
  end
  local list = {}
  for i = 0, #pitch_classes - 1 do
    list[#list + 1] = pitch_classes[(start - 1 + i) % #pitch_classes + 1]
  end
  return list
end

---Note names for a list of pitch classes, for example "C  D  D#  G  G#".
---@param pitch_classes integer[]
---@param separator string|nil Default: two spaces.
---@return string
function M.names(pitch_classes, separator)
  local names = {}
  for _, pc in ipairs(pitch_classes) do
    names[#names + 1] = M.NOTE_NAMES[pc % 12 + 1]
  end
  return table.concat(names, separator or "  ")
end

---Note names for the piano caption. Uses two spaces between names, or one
---space when two would make the text longer than `max_chars`.
---@param pitch_classes integer[]
---@param max_chars integer
---@return string
function M.caption(pitch_classes, max_chars)
  local wide = M.names(pitch_classes, "  ")
  if #wide <= max_chars then
    return wide
  end
  return M.names(pitch_classes, " ")
end

return M
