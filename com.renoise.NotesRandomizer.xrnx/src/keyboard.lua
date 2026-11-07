--[[
  Piano keyboard geometry: where each key is, and which key is under a point.
  Pure Lua: no `renoise.*`, so `just test` can run it under plain LuaJIT.
  `src/piano.lua` draws it on a canvas.

  Coordinates start at the top left. The keyboard starts on C.
]]

local M = {}

---Black key width, relative to a white key.
M.BLACK_WIDTH = 0.6
---Black key height, relative to the keyboard.
M.BLACK_HEIGHT = 0.6

local WHITE_PCS = { 0, 2, 4, 5, 7, 9, 11 }

---Black keys by pitch class, with the white key (1-based, within the octave)
---whose right edge they sit on.
local BLACKS = {
  { pc = 1, edge = 1 },
  { pc = 3, edge = 2 },
  { pc = 6, edge = 4 },
  { pc = 8, edge = 5 },
  { pc = 10, edge = 6 },
}

---@class PianoKey
---@field pc integer Pitch class 0..11.
---@field octave integer Octave within the keyboard, from 0.
---@field black boolean
---@field x number
---@field y number
---@field w number
---@field h number

---@class PianoLayout
---@field width number
---@field height number
---@field white_width number
---@field whites PianoKey[] Left to right.
---@field blacks PianoKey[] Left to right.

---@param width number
---@param height number
---@param octaves integer
---@return PianoLayout
function M.layout(width, height, octaves)
  local ww = width / (7 * octaves)
  local bw = ww * M.BLACK_WIDTH
  local bh = height * M.BLACK_HEIGHT
  local whites, blacks = {}, {}
  for o = 0, octaves - 1 do
    for i, pc in ipairs(WHITE_PCS) do
      local x = (o * 7 + i - 1) * ww
      whites[#whites + 1] = { pc = pc, octave = o, black = false, x = x, y = 0, w = ww, h = height }
    end
    for _, b in ipairs(BLACKS) do
      local x = (o * 7 + b.edge) * ww - bw / 2
      blacks[#blacks + 1] = { pc = b.pc, octave = o, black = true, x = x, y = 0, w = bw, h = bh }
    end
  end
  return { width = width, height = height, white_width = ww, whites = whites, blacks = blacks }
end

---@param key PianoKey
---@param x number
---@param y number
---@return boolean
local function inside(key, x, y)
  return x >= key.x and x < key.x + key.w and y >= key.y and y < key.y + key.h
end

---The key under a point. Black keys sit on top, so they are tested first.
---@param layout PianoLayout
---@param x number
---@param y number
---@return PianoKey|nil
function M.hit(layout, x, y)
  for _, key in ipairs(layout.blacks) do
    if inside(key, x, y) then
      return key
    end
  end
  for _, key in ipairs(layout.whites) do
    if inside(key, x, y) then
      return key
    end
  end
  return nil
end

return M
