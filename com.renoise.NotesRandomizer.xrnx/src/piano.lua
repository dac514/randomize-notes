--[[
  The piano under How and Key: a two-octave keyboard on a canvas that marks
  the notes of the current scale. Renoise side; the geometry lives in the pure
  module `src/keyboard.lua`.

  Keys use fixed colours so a light theme does not invert the keyboard. Only
  the markers use the theme accent, so they follow the user's colours.
]]

local keyboard = require "src.keyboard"

local M = {}

M.OCTAVES = 2

local WHITE_TOP = { 252, 252, 250, 255 }
local WHITE_BOTTOM = { 222, 222, 218, 255 }
local WHITE_FACE = { 238, 238, 235, 255 }
local BLACK_TOP = { 64, 64, 68, 255 }
local BLACK_BOTTOM = { 18, 18, 20, 255 }
local BLACK_FACE = { 36, 36, 40, 255 }
local GAP = { 16, 16, 18, 255 }
local ACCENT = "selected_button_back"

---@class PianoState
---@field pitch_classes integer[]|nil Notes to mark; nil draws a dimmed keyboard.
---@field root integer|nil Pitch class drawn as a ring.

---Path of a key with rounded bottom corners.
---@param ctx renoise.Views.Canvas.Context
---@param x number
---@param y number
---@param w number
---@param h number
---@param r number
local function key_path(ctx, x, y, w, h, r)
  ctx:begin_path()
  ctx:move_to(x, y)
  ctx:line_to(x + w, y)
  ctx:line_to(x + w, y + h - r)
  ctx:arc_to(x + w, y + h, x + w - r, y + h, r)
  ctx:line_to(x + r, y + h)
  ctx:arc_to(x, y + h, x, y + h - r, r)
  ctx:close_path()
end

---@param ctx renoise.Views.Canvas.Context
---@param x number
---@param y number
---@param r number
---@param color RGBAColor|ThemeColor
local function disc(ctx, x, y, r, color)
  ctx.fill_color = color
  ctx:begin_path()
  ctx:arc(x, y, r, 0, 2 * math.pi)
  ctx:fill()
end

---Draw a scale marker: a dot for a scale note, a ring for the root.
---@param ctx renoise.Views.Canvas.Context
---@param key PianoKey
---@param r number
---@param is_root boolean
local function marker(ctx, key, r, is_root)
  local x = key.x + key.w / 2
  local y = key.y + key.h - key.w / 2 - (key.black and 2 or 3)
  if is_root then
    disc(ctx, x, y, r * 1.3, ACCENT)
    disc(ctx, x, y, r * 0.55, key.black and BLACK_FACE or WHITE_FACE)
  else
    disc(ctx, x, y, r, ACCENT)
  end
end

---@param ctx renoise.Views.Canvas.Context
---@param state PianoState
function M.render(ctx, state)
  local w, h = ctx.size.width, ctx.size.height
  local layout = keyboard.layout(w, h, M.OCTAVES)
  local marks = {}
  for _, pc in ipairs(state.pitch_classes or {}) do
    marks[pc] = true
  end

  ctx.global_alpha = state.pitch_classes and 255 or 110

  -- Dark backdrop: the gaps between the white keys show it.
  ctx.fill_color = GAP
  key_path(ctx, 0, 0, w, h, 3)
  ctx:fill()

  for _, key in ipairs(layout.whites) do
    ctx:set_fill_linear_gradient(0, 0, 0, h)
    ctx:add_fill_color_stop(0, WHITE_TOP)
    ctx:add_fill_color_stop(1, WHITE_BOTTOM)
    key_path(ctx, key.x + 0.5, 0, key.w - 1, h - 1, 2)
    ctx:fill()
  end

  for _, key in ipairs(layout.blacks) do
    ctx.fill_color = GAP
    key_path(ctx, key.x - 0.5, 0, key.w + 1, key.h + 1, 2)
    ctx:fill()
    ctx:set_fill_linear_gradient(0, 0, 0, key.h)
    ctx:add_fill_color_stop(0, BLACK_TOP)
    ctx:add_fill_color_stop(1, BLACK_BOTTOM)
    key_path(ctx, key.x + 0.5, 0, key.w - 1, key.h - 1, 1.5)
    ctx:fill()
  end

  if state.pitch_classes then
    local white_r = layout.white_width * 0.26
    local black_r = layout.white_width * keyboard.BLACK_WIDTH * 0.3
    for _, key in ipairs(layout.whites) do
      if marks[key.pc] then
        marker(ctx, key, white_r, key.pc == state.root)
      end
    end
    for _, key in ipairs(layout.blacks) do
      if marks[key.pc] then
        marker(ctx, key, black_r, key.pc == state.root)
      end
    end
  end
end

---The pitch class under a point of a piano of this size, or nil.
---@param width number
---@param height number
---@param x number
---@param y number
---@return integer|nil
function M.hit(width, height, x, y)
  local key = keyboard.hit(keyboard.layout(width, height, M.OCTAVES), x, y)
  return key and key.pc
end

return M
