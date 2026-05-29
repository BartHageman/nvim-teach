-- Floating window management for bubbles.
-- Uses plain nvim_open_win (no nui.nvim dependency).
local M = {}

local session   -- loaded lazily to avoid circular deps

local function get_session()
  if not session then session = require("nvim-teach.session") end
  return session
end

--- Normalize escape sequences that arrive as two-character literals in JSON
--- from the LLM (\n, \t, \r). Done at the rendering boundary so a future client
--- that sends real newlines still renders correctly.
---@param s string|nil
---@return string|nil
local function unescape(s)
  if s == nil then return nil end
  s = s:gsub("\\n", "\n")
  s = s:gsub("\\t", "\t")
  s = s:gsub("\\r", "")
  return s
end

--- Wrap a string to fit within max_width, splitting on word boundaries.
---@return string[]
local function wrap_text(text, max_width)
  local lines = {}
  text = unescape(text) or ""
  for _, raw_line in ipairs(vim.split(text, "\n", { plain = true })) do
    if #raw_line <= max_width then
      lines[#lines + 1] = raw_line
    else
      local words = vim.split(raw_line, "%s+")
      local current = ""
      for _, word in ipairs(words) do
        if #current == 0 then
          current = word
        elseif #current + 1 + #word <= max_width then
          current = current .. " " .. word
        else
          lines[#lines + 1] = current
          current = word
        end
      end
      if #current > 0 then lines[#lines + 1] = current end
    end
  end
  return lines
end

local callouts = require("nvim-teach.callouts")

local PAD_LEFT  = "  "  -- two-space inner padding
local SEP_CHAR  = "─"

--- Pick footer hint text based on bubble state.
local function footer_for(bubble)
  if bubble.pages then
    local total = #bubble.pages
    local cur   = bubble.current_page or 1
    local back  = cur > 1 and " · <BS> back" or ""
    if cur >= total then
      return string.format("[%d/%d · <CR> done%s · q quit]", cur, total, back)
    end
    return string.format("[%d/%d · <CR> next%s · q quit]", cur, total, back)
  end
  return "[<CR>/q dismiss]"
end

--- Build the rendered lines and per-line highlight spans for a bubble.
--- Returns:
---   lines: string[]
---   highlights: { {line=0-idx, col_start, col_end, hl_group}, ... }
---@param bubble table
---@param max_width integer
local function build_bubble_render(bubble, max_width)
  local inner_width = max_width - #PAD_LEFT * 2
  local glyph, callout_hl, _bubble_hl, _stripe_hl, kind_title = callouts.resolve(bubble)
  local title_hl  = "NvimTeachTitle"  .. kind_title
  local rule_hl   = "NvimTeachRule"   .. kind_title
  local footer_hl = "NvimTeachFooter" .. kind_title
  local lines = {}
  local hls   = {}

  -- Top padding.
  lines[#lines + 1] = ""

  -- Header line: "  <icon>  TITLE"
  local title = unescape(bubble.title) or "Note"
  title = title:gsub("\n", " ")
  local header = PAD_LEFT .. glyph .. "  " .. title
  lines[#lines + 1] = header
  do
    local i = #lines - 1  -- 0-indexed
    local icon_start = #PAD_LEFT
    local icon_end   = icon_start + #glyph
    hls[#hls + 1] = { line = i, col_start = icon_start, col_end = icon_end, hl_group = callout_hl }
    local title_start = icon_end + 2
    hls[#hls + 1] = { line = i, col_start = title_start, col_end = -1, hl_group = title_hl }
  end

  -- Separator rule.
  local rule = PAD_LEFT .. string.rep(SEP_CHAR, inner_width)
  lines[#lines + 1] = rule
  hls[#hls + 1] = { line = #lines - 1, col_start = #PAD_LEFT, col_end = -1, hl_group = rule_hl }

  -- Blank gap.
  lines[#lines + 1] = ""

  -- Body, wrapped + left-padded.
  for _, raw in ipairs(wrap_text(bubble.body, inner_width)) do
    lines[#lines + 1] = PAD_LEFT .. raw
  end

  -- Question (kept for back-compat with the "question" kind).
  if bubble.question then
    lines[#lines + 1] = ""
    for _, raw in ipairs(wrap_text("? " .. bubble.question, inner_width)) do
      lines[#lines + 1] = PAD_LEFT .. raw
    end
  end

  -- Choices.
  if bubble.choices and #bubble.choices > 0 then
    lines[#lines + 1] = ""
    for i, choice in ipairs(bubble.choices) do
      lines[#lines + 1] = PAD_LEFT .. string.format("%d. %s", i, choice)
    end
  end

  -- Footer.
  lines[#lines + 1] = ""
  lines[#lines + 1] = PAD_LEFT .. footer_for(bubble)
  hls[#hls + 1] = { line = #lines - 1, col_start = #PAD_LEFT, col_end = -1, hl_group = footer_hl }

  -- Bottom padding.
  lines[#lines + 1] = ""

  return lines, hls
end

--- Compute the screen row of anchor_row relative to the current window.
--- Returns nil if the anchor row is scrolled off-screen.
local function screen_row_for(winid, anchor_row)
  local top = vim.api.nvim_win_call(winid, function()
    return vim.fn.line("w0") - 1  -- 0-indexed top visible line
  end)
  local height = vim.api.nvim_win_get_height(winid)
  local bottom = top + height - 1

  if anchor_row < top or anchor_row > bottom then
    return nil  -- off-screen
  end
  return anchor_row - top  -- 0-indexed row within the window
end

--- Open a floating bubble window for the given bubble.
--- Modifies bubble.winid and bubble.win_bufnr in-place.
---@param bubble table
---@param config table  plugin config (for float.border, float.max_width, etc.)
---@param opts? table   { jump_cursor: boolean }  — when true (default) the source
---                      window's cursor moves to the anchor row so the bubble is
---                      guaranteed visible. Scroll-tracking re-opens pass false
---                      to avoid feedback with user-driven scrolling.
function M.open_bubble_win(bubble, config, opts)
  opts = opts or {}
  local jump_cursor = opts.jump_cursor ~= false
  local max_width = (config.float and config.float.max_width) or 60
  local max_height = (config.float and config.float.max_height) or 20
  local border = (config.float and config.float.border) or "rounded"

  local lines, hls = build_bubble_render(bubble, max_width)
  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + #PAD_LEFT, max_width)  -- right-side padding
  local height = math.min(#lines, max_height)

  -- Find the source window (the window displaying session.bufnr).
  local source_win = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == bubble.bufnr then
      source_win = w
      break
    end
  end
  if not source_win then return end

  -- Jump the cursor to the anchor so the bubble is always visible. Skipped by
  -- the scroll-tracking reopen path to avoid scroll feedback loops.
  if jump_cursor then
    local line_count = vim.api.nvim_buf_line_count(bubble.bufnr)
    local target_row = math.min(bubble.anchor_row + 1, line_count)
    pcall(vim.api.nvim_win_set_cursor, source_win, { target_row, 0 })
  end

  local screen_row = screen_row_for(source_win, bubble.anchor_row)
  if not screen_row then
    -- Anchor is off-screen; don't open the float now.
    return
  end

  -- Place float just below the anchor line.
  local float_row = screen_row + 1
  -- Make sure it doesn't overflow the window height.
  local win_height = vim.api.nvim_win_get_height(source_win)
  if float_row + height > win_height then
    float_row = math.max(0, screen_row - height - 1)
  end

  -- Create scratch buffer for the float.
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- Apply per-line highlights for icon, title, separator, footer.
  local ns = vim.api.nvim_create_namespace("nvim_teach_bubble_inline")
  for _, h in ipairs(hls) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, h.line, h.col_start, {
      end_col = h.col_end == -1 and #lines[h.line + 1] or h.col_end,
      hl_group = h.hl_group,
    })
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "win",
    win = source_win,
    row = float_row,
    col = 2,
    width = width,
    height = height,
    style = "minimal",
    border = border,
    zindex = 50,
    focusable = true,
  })

  -- Per-callout tinted background, plus accent-colored border when one is set.
  local _, callout_hl, bubble_hl = callouts.resolve(bubble)
  vim.wo[win].winhl = "Normal:" .. bubble_hl .. ",FloatBorder:" .. callout_hl
  vim.wo[win].wrap = true

  bubble.winid = win
  bubble.win_bufnr = buf

  -- Buffer-local keymaps on the float itself, so the user can interact with
  -- the bubble whether the cursor is in the source buffer or the bubble.
  local km = (config.keymaps or {})
  local reply_key   = km.reply   or "<CR>"
  local back_key    = km.back    or "<BS>"
  local dismiss_key = km.dismiss or "q"
  local kmap_opts = { buffer = buf, silent = true, nowait = true }
  vim.keymap.set("n", reply_key, function()
    local keymaps = require("nvim-teach.keymaps")
    if bubble.pages then
      keymaps.advance_tour(bubble, config)
    else
      keymaps.dismiss_bubble(bubble, config)
      get_session().remove_bubble(bubble.id)
    end
  end, kmap_opts)
  vim.keymap.set("n", back_key, function()
    if not bubble.pages then return end
    require("nvim-teach.keymaps").rewind_tour(bubble, config)
  end, kmap_opts)
  vim.keymap.set("n", dismiss_key, function()
    local keymaps = require("nvim-teach.keymaps")
    keymaps.dismiss_bubble(bubble, config)
    get_session().remove_bubble(bubble.id)
  end, kmap_opts)
end

--- Close a bubble's float window if it is open.
function M.close_bubble_win(bubble)
  if bubble.winid and vim.api.nvim_win_is_valid(bubble.winid) then
    vim.api.nvim_win_close(bubble.winid, true)
  end
  bubble.winid = nil
  bubble.win_bufnr = nil
end

--- Reopen a bubble's float if it is not currently open (e.g. after scroll back).
function M.ensure_bubble_win(bubble, config)
  if not bubble.winid or not vim.api.nvim_win_is_valid(bubble.winid) then
    M.open_bubble_win(bubble, config)
  end
end

--- Update the content of an already-open bubble window.
function M.update_bubble_content(bubble, config)
  M.close_bubble_win(bubble)
  M.open_bubble_win(bubble, config)
end

--- Set up a WinScrolled autocmd that hides/restores bubble floats as the user scrolls.
---@param source_win integer  the window id of the source (code) buffer
---@param config table
function M.setup_scroll_tracking(source_win, config)
  local group = vim.api.nvim_create_augroup("NvimTeachScroll", { clear = true })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = group,
    callback = function()
      local s = get_session()
      if not s.bufnr then return end

      for _, bubble in pairs(s.bubbles) do
        if bubble.is_dismissed then goto continue end

        local on_screen = screen_row_for(source_win, bubble.anchor_row) ~= nil

        if on_screen then
          -- Reopen if closed due to previous scroll. Don't jump the cursor —
          -- the user is the one scrolling.
          if not bubble.winid or not vim.api.nvim_win_is_valid(bubble.winid) then
            M.open_bubble_win(bubble, config, { jump_cursor = false })
          end
        else
          -- Hide when scrolled off.
          if bubble.winid and vim.api.nvim_win_is_valid(bubble.winid) then
            vim.api.nvim_win_close(bubble.winid, true)
            bubble.winid = nil
            bubble.win_bufnr = nil
          end
        end

        ::continue::
      end
    end,
  })
end

return M
