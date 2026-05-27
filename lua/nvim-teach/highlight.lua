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

  local id = vim.api.nvim_buf_set_extmark(bufnr, ns, range.start_row, range.start_col or 0, {
    end_row = end_row,
    end_col = end_col,
    hl_group = hl_group,
    hl_eol = true,
    priority = 100,
  })
  pcall(function()
    local anim = require("nvim-teach.animation")
    local name = "nvim_teach_pulse_" .. id
    anim.pulse_start(name, bufnr, range, hl_group)
    anim.register(name)
  end)
  return id
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
    pcall(function()
      require("nvim-teach.animation").pulse_stop("nvim_teach_pulse_" .. bubble.highlight_extmark_id)
    end)
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
  pcall(function() require("nvim-teach.animation").stop_all() end)
end

--- Clear a single range-highlight extmark by id, stopping its pulse animation.
function M.clear_range_highlight(bufnr, ns, extmark_id)
  if not extmark_id then return end
  pcall(function()
    require("nvim-teach.animation").pulse_stop("nvim_teach_pulse_" .. extmark_id)
  end)
  pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, extmark_id)
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
--- Called once from init.lua on setup, and again on ColorScheme.
--- Force-sets every group — these names are plugin-private so we don't risk
--- stomping on the colorscheme. Skipping when "already exists" was leaving
--- groups cleared (empty dict) and breaking bubble bgs.
function M.define_highlights()
  local function def(name, opts)
    vim.api.nvim_set_hl(0, name, opts)
  end

  -- Tint bubble bgs by blending each accent color into Normal's bg.
  -- Fallback base if no Normal bg is set (e.g. transparent terminals).
  local base = normal_bg_hex() or "#1e1e2e"
  local neutral_bg = blend("#cdd6f4", base, 0.06)

  -- Accent colors per callout. Tweaked toward user prefs:
  --   note=blue, tip=green, important=red, warning=orange, caution=maroon.
  local callout_accents = {
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

  -- Highlight bg palette. Borrow accent colors from terminal colors so the
  -- bands pick up the user's colorscheme, with sensible hardcoded fallbacks.
  local function term_color(n, fallback)
    local v = vim.g["terminal_color_" .. n]
    if type(v) == "string" and v:match("^#%x%x%x%x%x%x$") then return v end
    return fallback
  end
  local accents = {
    red    = term_color(1, "#f38ba8"),
    green  = term_color(2, "#a6e3a1"),
    yellow = term_color(3, "#f9e2af"),
    blue   = term_color(4, "#89b4fa"),
    purple = term_color(5, "#cba6f7"),
    -- Orange isn't an ANSI slot (9 is bright red by spec). Always hardcode.
    orange = "#fab387",
  }
  for name, accent in pairs(accents) do
    def("NvimTeachHL" .. name:sub(1, 1):upper() .. name:sub(2),
        { bg = blend(accent, base, 0.22), fg = "NONE" })
  end

  for kind, accent in pairs(callout_accents) do
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
