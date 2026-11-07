--[[
  Scales and keys. Run with `just test tests/scales_test.lua`.
]]

local t = require "tests.helper"
local scales = require "src.scales"

---@param list integer[]|nil
---@return string
local function show(list)
  return table.concat(assert(list), ",")
end

---@param how string
---@param key integer
---@param custom string|nil
---@return integer[]
local function pcs_of(how, key, custom)
  return assert(scales.pitch_classes(how, key, custom))
end

-- Renoise 3.5's own list (`trigger_options.available_scale_modes`, without
-- "None"), read from a running Renoise. The How popup must match it.
local RENOISE = "Natural Major|Natural Minor|Pentatonic Major|Pentatonic Minor|Pentatonic Egyptian|"
  .. "Blues Major|Blues Minor|Whole Tone|Augmented|Prometheus|Tritone|Harmonic Major|"
  .. "Harmonic Minor|Melodic Minor|All Minor|Dorian|Phrygian|Phrygian Dominant|Lydian|"
  .. "Lydian Augmented|Mixolydian|Locrian|Locrian Major|Super Locrian|Neapolitan Major|"
  .. "Neapolitan Minor|Romanian Minor|Spanish Gypsy|Hungarian Gypsy|Enigmatic|Overtone|"
  .. "Diminished Half|Diminished Whole|Spanish Eight-Tone|Nine-Tone Scale"
t.eq(table.concat(scales.scale_names(), "|"), RENOISE, "scale names match Renoise")

local modes = scales.modes()
t.eq(#modes, 38, "modes: Shuffle, Chaos, Custom and 35 scales")
t.eq(modes[1], scales.SHUFFLE, "modes: Shuffle first")
t.eq(modes[2], scales.CHAOS, "modes: Chaos second")
t.eq(modes[3], scales.CUSTOM, "modes: Custom third")
t.check(scales.is_mode "Dorian", "is_mode: a scale")
t.check(not scales.is_mode "Hirajoshi", "is_mode: an old 1.11 name is gone")

-- Note counts per scale, from the `count` fields of Duplex HARMONIC_SCALES.
local COUNTS = {
  ["Natural Major"] = 7,
  ["Natural Minor"] = 7,
  ["Pentatonic Major"] = 5,
  ["Pentatonic Minor"] = 5,
  ["Pentatonic Egyptian"] = 5,
  ["Blues Major"] = 6,
  ["Blues Minor"] = 6,
  ["Whole Tone"] = 6,
  ["Augmented"] = 6,
  ["Prometheus"] = 6,
  ["Tritone"] = 6,
  ["All Minor"] = 9,
  ["Diminished Half"] = 8,
  ["Diminished Whole"] = 8,
  ["Spanish Eight-Tone"] = 8,
  ["Nine-Tone Scale"] = 9,
}
for _, name in ipairs(scales.scale_names()) do
  local want = COUNTS[name] or 7
  for key = 0, 11 do
    local pcs = pcs_of(name, key)
    if not t.eq(#pcs, want, name .. " key " .. key .. ": note count") then
      break
    end
    -- 1.11 bugs 1 and 2: no invalid notes (B#, E#), no duplicates, root included.
    local ok, last = true, -1
    for _, pc in ipairs(pcs) do
      ok = ok and pc > last and pc >= 0 and pc <= 11
      last = pc
    end
    t.check(ok, name .. " key " .. key .. ": sorted, unique, in 0..11")
    local has_root = false
    for _, pc in ipairs(pcs) do
      has_root = has_root or pc == key
    end
    t.check(has_root, name .. " key " .. key .. ": contains the root")
  end
end

t.eq(show(scales.pitch_classes("Natural Major", 0)), "0,2,4,5,7,9,11", "C major")
t.eq(show(scales.pitch_classes("Natural Major", 7)), "0,2,4,6,7,9,11", "G major has F#")
t.eq(show(scales.pitch_classes("Harmonic Minor", 0)), "0,2,3,5,7,8,11", "harmonic minor has B")
t.eq(show(scales.pitch_classes("Blues Minor", 0)), "0,3,5,6,7,10", "blues minor")
t.eq(show(scales.pitch_classes("Locrian", 0)), "0,1,3,5,6,8,10", "locrian lists C once")
t.eq(show(scales.pitch_classes("Pentatonic Major", 7)), "2,4,7,9,11", "G pentatonic major")
t.eq(#pcs_of(scales.CHAOS, 5), 12, "Chaos: all notes, key ignored")
t.eq(scales.pitch_classes(scales.SHUFFLE, 0), nil, "Shuffle: no scale")
t.eq(#pcs_of(scales.CUSTOM, 0, scales.EMPTY_CUSTOM), 0, "Custom: empty")
t.eq(show(scales.pitch_classes(scales.CUSTOM, 3, "100000010000")), "0,7", "Custom: key ignored")
t.eq(#pcs_of(scales.CUSTOM, 0, nil), 0, "Custom: nil mask is empty")
t.fails(function()
  scales.pitch_classes("Nope", 0)
end, "unknown scale", "unknown scale")

t.eq(scales.root("Dorian", 14), 2, "root: key wraps")
t.eq(scales.root(scales.CHAOS, 2), nil, "root: none for Chaos")
t.eq(scales.root(scales.CUSTOM, 2), nil, "root: none for Custom")
t.check(scales.uses_key "Dorian", "uses_key: scale")
t.check(not scales.uses_key(scales.CUSTOM), "uses_key: Custom")

t.eq(scales.to_mask { 0, 4, 7 }, "100010010000", "to_mask")
t.eq(scales.to_mask(pcs_of("Natural Major", 0)), "101011010101", "to_mask round trip")
t.eq(scales.toggle("100000000000", 0), "000000000000", "toggle: off")
t.eq(scales.toggle("100000000000", 11), "100000000001", "toggle: on")
t.eq(
  show(scales.from_root({ 0, 2, 4, 7, 9 }, 9)),
  "9,0,2,4,7",
  "from_root: A minor pentatonic starts on A"
)
t.eq(show(scales.from_root({ 0, 2, 4 }, nil)), "0,2,4", "from_root: no root")
t.eq(show(scales.from_root({ 0, 2, 4 }, 5)), "0,2,4", "from_root: root not in the list")
t.eq(scales.names { 0, 3, 7 }, "C  D#  G", "names")
t.eq(scales.names({ 1, 6 }, " "), "C# F#", "names: separator")

t.done()
