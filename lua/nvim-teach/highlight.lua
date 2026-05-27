-- All nvim_buf_set_extmark calls live here. Nothing else touches the extmarks API.
local M = {}

--- Place a background highlight over a range.
--- Translates an end_col of -1 / nil into the next-line / col-0 form so that
--- single-row ranges still produce a visible line highlight (an extmark with
--- end_row == start_row and end_col == nil is treated as a zero-length point).
---@return integer extmark_id
function M.set_range_highlight(bufnr, ns, range, hl_group)
  hl_group = hl_group or "NvimTeachHL"
  local end_row, end_col = range.end_row, range.end_col
  if end_col == -1 or end_col == nil then
    end_row = end_row + 1
    end_col = 0
  end

  return vim.api.nvim_buf_set_extmark(bufnr, ns, range.start_row, range.start_col or 0, {
    end_row = end_row,
    end_col = end_col,
    hl_group = hl_group,
    hl_eol = true,
    priority = 100,
  })
end

--- Place a gutter sign on a single row.
---@return integer extmark_id
function M.set_sign(bufnr, ns, row, sign_text, hl_group)
  sign_text = sign_text or "▶"
  hl_group = hl_group or "NvimTeachSign"

  return vim.api.nvim_buf_set_extmark(bufnr, ns, row, 0, {
    sign_text = sign_text,
    sign_hl_group = hl_group,
    priority = 100,
  })
end

--- Clear extmarks belonging to a specific bubble (by stored extmark IDs).
function M.clear_bubble(bufnr, ns, bubble)
  if bubble.highlight_extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, bubble.highlight_extmark_id)
    bubble.highlight_extmark_id = nil
  end
  if bubble.sign_extmark_id then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, bubble.sign_extmark_id)
    bubble.sign_extmark_id = nil
  end
end

--- Clear every extmark in the namespace (used for clear-all).
function M.clear_all(bufnr, ns)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
end

--- Parse "#rrggbb" into r,g,b integers.
local function parse_hex(h)
  return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
end

--- Blend `accent` toward `base` by `t` (0 = pure base, 1 = pure accent).
local function blend(accent, base, t)
  local ar, ag, ab = parse_hex(accent)
  local br, bg, bb = parse_hex(base)
  local function mix(a, b) return math.floor(a * t + b * (1 - t) + 0.5) end
  return string.format("#%02x%02x%02x", mix(ar, br), mix(ag, bg), mix(ab, bb))
end

--- Resolve Normal's bg as a hex string, or nil if not set.
local function normal_bg_hex()
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = "Normal", link = false })
  if not ok or not hl or not hl.bg then return nil end
  return string.format("#%06x", hl.bg)
end

--- Register the plugin's default highlight groups.
--- Called once from init.lua on setup.
function M.define_highlights()
  -- Only define if not already set by the colorscheme.
  local function def(name, opts)
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, opts)
    end
  end

  -- Tint bubble bgs by blending each accent color into Normal's bg.
  -- Fallback base if no Normal bg is set (e.g. transparent terminals).
  local base = normal_bg_hex() or "#1e1e2e"
  local neutral_bg = blend("#cdd6f4", base, 0.06)

  -- Accent colors per callout. Tweaked toward user prefs:
  --   note=blue, tip=green, important=red, warning=orange, caution=maroon.
  local accents = {
    note      = "#89b4fa",
    tip       = "#a6e3a1",
    important = "#f38ba8",
    warning   = "#fab387",
    caution   = "#eba0ac",
  }

  def("NvimTeachHL",       { bg = "#2d4a3e", fg = "NONE" })  -- default (green); alias of NvimTeachHLGreen below.
  def("NvimTeachSign",     { fg = "#7ec8a0", bold = true })
  def("NvimTeachBubble",   { bg = neutral_bg, fg = "#cdd6f4" })
  def("NvimTeachBorder",   { fg = "#7ec8a0" })
  def("NvimTeachTitle",    { fg = "#cdd6f4", bold = true })
  def("NvimTeachQuestion", { fg = "#f9c74f", bold = true })
  def("NvimTeachFooter",   { fg = "#6c7086", italic = true })
  def("NvimTeachRule",     { fg = blend("#cdd6f4", base, 0.4) })

  -- Highlight bg palette. The LLM picks a color via the `highlight_color`
  -- tool param; each name maps to one of these groups.
  local hl_bgs = {
    green  = "#2d4a3e",
    red    = "#4a2d33",
    blue   = "#2d3a4a",
    yellow = "#4a432d",
    orange = "#4a3a2d",
    purple = "#3a2d4a",
  }
  for name, bg in pairs(hl_bgs) do
    def("NvimTeachHL" .. name:sub(1, 1):upper() .. name:sub(2), { bg = bg, fg = "NONE" })
  end

  for kind, accent in pairs(accents) do
    local title = kind:sub(1, 1):upper() .. kind:sub(2)
    local bg = blend(accent, base, 0.18)
    def("NvimTeachCallout" .. title,       { fg = accent, bold = true })
    def("NvimTeachBubble"  .. title,       { bg = bg, fg = "#cdd6f4" })
    -- Rule + footer colors that read against the tinted bubble bg.
    def("NvimTeachRule"   .. title,        { bg = bg, fg = blend(accent, "#cdd6f4", 0.55) })
    def("NvimTeachFooter" .. title,        { bg = bg, fg = blend("#cdd6f4", bg, 0.55), italic = true })
    def("NvimTeachTitle"  .. title,        { bg = bg, fg = "#cdd6f4", bold = true })
  end
end

return M
