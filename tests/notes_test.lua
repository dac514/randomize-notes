--[[
  Note randomizing and shuffling. Run with `just test tests/notes_test.lua`.
]]

local t = require "tests.helper"
local notes = require "src.notes"
local scales = require "src.scales"

---A random source that returns `values` in order, and checks each one is in
---the range the caller asked for.
---@param values integer[]
---@return NotesRng
local function fixed(values)
  local i = 0
  return function(m, n)
    i = i + 1
    local v = values[i]
    assert(v ~= nil, "fixed rng: out of values")
    assert(v >= m and v <= n, ("fixed rng: %d not in %d..%d"):format(v, m, n))
    return v
  end
end

---@param over table|nil
---@return NotesSettings
local function settings(over)
  local s = {
    how = "Natural Major",
    key = 0,
    custom = scales.EMPTY_CUSTOM,
    neighbour = false,
    shift = "rand",
    preserve_notes = false,
    preserve_octaves = true,
    octave_min = 0,
    octave_max = 9,
  }
  for k, v in pairs(over or {}) do
    s[k] = v
  end
  return s
end

---@param over table|nil
---@return NotesOptions
local function options(over)
  return assert(notes.options(settings(over)))
end

-- options ----------------------------------------------------------------------

local o, msg = notes.options(settings { how = scales.SHUFFLE })
t.eq(o, nil, "options: Shuffle has none")
t.check(msg ~= nil, "options: Shuffle message")
o, msg = notes.options(settings { how = scales.CUSTOM })
t.eq(o, nil, "options: empty Custom has none")
t.check(msg and msg:find "Custom", "options: empty Custom message")
o = options { how = scales.CHAOS, neighbour = true, preserve_notes = true }
t.eq(o.neighbour, false, "options: Chaos turns Nearest Neighbour off")
t.eq(o.preserve_notes, false, "options: Chaos turns Preserve Notes off")
o = options { octave_min = 7, octave_max = 3 }
t.eq(o.octave_min, 3, "options: swapped octave range, min")
t.eq(o.octave_max, 7, "options: swapped octave range, max")
o = options { octave_min = -4, octave_max = 30 }
t.eq(o.octave_min, 0, "options: octave min clamped")
t.eq(o.octave_max, 9, "options: octave max clamped")

-- randomize: fixed cases ------------------------------------------------------

o = options()
t.eq(notes.randomize(120, o, fixed {}), 120, "note-off is unchanged")
t.eq(notes.randomize(121, o, fixed {}), 121, "empty note is unchanged")
-- C major, octave kept: the 3rd scale note is E. C-4 is 48, E-4 is 52.
t.eq(notes.randomize(48, o, fixed { 3 }), 52, "random note, same octave")
o = options { preserve_octaves = false, octave_min = 2, octave_max = 2 }
t.eq(notes.randomize(48, o, fixed { 1, 2 }), 24, "random note, octave from the range")
o = options { preserve_notes = true }
t.eq(notes.randomize(50, o, fixed { 1 }), 50, "preserve notes: D stays in C major")
t.eq(notes.randomize(49, o, fixed { 1 }), 48, "preserve notes: C# is replaced")

-- Nearest neighbour ------------------------------------------------------------

local g_penta = options { how = "Pentatonic Major", key = 7, neighbour = true, shift = "up" }
-- 1.11 bug 3: B-4 up in G pentatonic major returned G-5; the next note up is D-5.
t.eq(notes.randomize(59, g_penta, fixed {}), 62, "neighbour up wraps to the next octave correctly")
g_penta = options { how = "Pentatonic Major", key = 7, neighbour = true, shift = "down" }
t.eq(notes.randomize(60, g_penta, fixed {}), 59, "neighbour down wraps to the octave below")
t.eq(notes.randomize(62, g_penta, fixed {}), 59, "neighbour moves in-scale notes too")
local keep = options {
  how = "Pentatonic Major",
  key = 7,
  neighbour = true,
  shift = "down",
  preserve_notes = true,
}
t.eq(notes.randomize(62, keep, fixed {}), 62, "neighbour + preserve notes keeps D")
local rand = options { neighbour = true, shift = "rand" }
t.eq(notes.randomize(49, rand, fixed { 1 }), 50, "neighbour rand: up")
t.eq(notes.randomize(49, rand, fixed { 2 }), 48, "neighbour rand: down")
local rand_oct = options {
  neighbour = true,
  shift = "up",
  preserve_octaves = false,
  octave_min = 1,
  octave_max = 1,
}
t.eq(notes.randomize(59, rand_oct, fixed { 1 }), 12, "neighbour with a random octave")

-- 1.11 bug 4: the octave edges reversed the direction.
local c_major = options().in_scale
t.eq(notes.neighbour(119, c_major, "up"), 119, "edge: B-9 up stays on B-9")
t.eq(notes.neighbour(0, c_major, "down"), 0, "edge: C-0 down stays on C-0")
local d_major = options({ key = 2 }).in_scale
t.eq(notes.neighbour(0, d_major, "down"), 1, "edge: C-0 down in D major goes up to C#-0")
local c_minor = options({ how = "Natural Minor" }).in_scale
t.eq(notes.neighbour(119, c_minor, "up"), 118, "edge: B-9 up in C minor goes down to A#-9")

-- randomize: properties over every mode, key and option -----------------------

math.randomseed(1234)
local rng = math.random
local bad = 0
local runs = 0
for _, how in ipairs(scales.modes()) do
  if how ~= scales.SHUFFLE then
    for key = 0, 11, 5 do
      for flags = 0, 15 do
        local s = settings {
          how = how,
          key = key,
          custom = "100100010010",
          neighbour = flags % 2 == 1,
          preserve_notes = math.floor(flags / 2) % 2 == 1,
          preserve_octaves = math.floor(flags / 4) % 2 == 1,
          shift = notes.SHIFTS[flags % 3 + 1],
          octave_min = 2,
          octave_max = math.floor(flags / 8) % 2 == 1 and 9 or 5,
        }
        local opts = assert(notes.options(s))
        for _ = 1, 40 do
          local v = rng(0, 119)
          local r = notes.randomize(v, opts, rng)
          runs = runs + 1
          local ok = notes.is_note(r) and opts.in_scale[r % 12]
          if s.preserve_octaves and not opts.neighbour then
            ok = ok and math.floor(r / 12) == math.floor(v / 12)
          end
          if not s.preserve_octaves then
            local oct = math.floor(r / 12)
            ok = ok and oct >= opts.octave_min and oct <= opts.octave_max
          end
          if opts.preserve_notes and opts.in_scale[v % 12] then
            ok = ok and r % 12 == v % 12
          end
          if not ok then
            bad = bad + 1
            if bad <= 5 then
              print(("  %s key %d flags %d: %d -> %d"):format(how, key, flags, v, r))
            end
          end
        end
      end
    end
  end
end
t.eq(bad, 0, ("randomize: %d results stay valid, in scale and in range"):format(runs))

-- shuffle ------------------------------------------------------------------------

local input = { 10, 20, 30, 40 }
local out = notes.shuffle(input, fixed { 1, 1, 1 })
t.eq(table.concat(out, ","), "20,30,40,10", "shuffle: Fisher-Yates with a fixed source")
t.eq(table.concat(input, ","), "10,20,30,40", "shuffle: input unchanged")
out = notes.shuffle(input, rng)
table.sort(out)
t.eq(table.concat(out, ","), "10,20,30,40", "shuffle: same values")
t.eq(#notes.shuffle({}, fixed {}), 0, "shuffle: empty")

t.done()
