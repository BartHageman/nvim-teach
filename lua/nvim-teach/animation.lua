-- Optional tiny-glimmer integration.
-- If tiny-glimmer is not installed, animate() is a no-op.
local M = {}

local _glimmer = nil
local _loaded = false

local function get_glimmer()
  if not _loaded then
    _loaded = true
    local ok, g = pcall(require, "tiny-glimmer")
    if ok then _glimmer = g end
  end
  return _glimmer
end

--- Animate a range highlight in the given buffer.
---@param bufnr integer
---@param range table { start_row, start_col, end_row, end_col }
function M.animate(bufnr, range)
  local g = get_glimmer()
  if not g then return end

  -- tiny-glimmer's public API varies by version; try the most likely entry points.
  if g.animate_range then
    pcall(g.animate_range, bufnr, {
      start_row = range.start_row,
      start_col = range.start_col,
      end_row   = range.end_row,
      end_col   = range.end_col,
    })
  elseif g.create_animation then
    pcall(g.create_animation, {
      bufnr = bufnr,
      range = { range.start_row, range.start_col, range.end_row, range.end_col },
    })
  end
  -- If neither API exists, silently do nothing.
end

return M
