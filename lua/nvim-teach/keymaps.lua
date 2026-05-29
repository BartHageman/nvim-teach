-- Buffer-local keymap management for nvim-teach.
local M = {}

local session  -- lazy
local window   -- lazy

local function S() if not session then session = require("nvim-teach.session") end return session end
local function W() if not window  then window  = require("nvim-teach.window")  end return window  end

--- Send a user-initiated question (with bubble context if any) to the active
--- CodeCompanion chat. Used only by the explicit ask-about-selection keymap.
---@param bubble table|nil
---@param text string
local function send_to_chat(bubble, text)
  local chat = S().chat
  if not chat then
    vim.notify("[nvim-teach] No active CodeCompanion chat.", vim.log.levels.WARN)
    return
  end

  if bubble then
    local ctx = string.format("[Bubble '%s' at line %d]\n%s",
      bubble.title or bubble.id,
      bubble.anchor_row + 1,
      text
    )
    chat:add_message({ role = "user", content = ctx })
  else
    chat:add_message({ role = "user", content = text })
  end

  local sel = S().pending_selection
  if sel then
    chat:add_message({
      role = "user",
      content = "Selected code:\n```\n" .. sel.text .. "\n```",
    })
    S().pending_selection = nil
  end

  local ok, err = pcall(function() chat:submit() end)
  if not ok then
    vim.notify("[nvim-teach] chat:submit() failed: " .. tostring(err), vim.log.levels.ERROR)
  end
end

--- Install a buffer-local <CR> keymap on `source_bufnr` that dismisses the
--- nearest bubble.
---@param source_bufnr integer
---@param bubble table
---@param config table
function M.install_bubble_keymaps(source_bufnr, bubble, config)
  -- Per-bubble registration is handled by install_nav_keymaps; nothing to do here.
  _ = source_bufnr
  _ = bubble
  _ = config
end

--- Install navigation keymaps (]t / [t / q / <CR> / <leader>ta) on the source buffer.
--- Call once per session start.
---@param source_bufnr integer
---@param config table
function M.install_nav_keymaps(source_bufnr, config)
  local km = config.keymaps or {}
  local next_key    = km.next         or "]t"
  local prev_key    = km.prev         or "[t"
  local dismiss_key = km.dismiss      or "q"
  local reply_key   = km.reply        or "<CR>"
  local back_key    = km.back         or "<BS>"
  local ask_sel_key = km.ask_selection or "<leader>ta"

  local opts = { buffer = source_bufnr, silent = true, nowait = false }

  -- ]t — move cursor to next bubble
  vim.keymap.set("n", next_key, function()
    local list = S().sorted_bubbles()
    if #list == 0 then return end
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    for _, b in ipairs(list) do
      if b.anchor_row > row then
        vim.api.nvim_win_set_cursor(0, { b.anchor_row + 1, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(0, { list[1].anchor_row + 1, 0 })
  end, opts)

  -- [t — move cursor to previous bubble
  vim.keymap.set("n", prev_key, function()
    local list = S().sorted_bubbles()
    if #list == 0 then return end
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    for i = #list, 1, -1 do
      if list[i].anchor_row < row then
        vim.api.nvim_win_set_cursor(0, { list[i].anchor_row + 1, 0 })
        return
      end
    end
    vim.api.nvim_win_set_cursor(0, { list[#list].anchor_row + 1, 0 })
  end, opts)

  -- <CR> — advance tour or dismiss nearest bubble
  vim.keymap.set("n", reply_key, function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local bubble = S().nearest_bubble(row)
    if not bubble then
      vim.notify("[nvim-teach] No bubble nearby.", vim.log.levels.INFO)
      return
    end
    if bubble.pages then
      M.advance_tour(bubble, config)
    else
      M.dismiss_bubble(bubble, config)
      S().remove_bubble(bubble.id)
    end
  end, opts)

  -- <BS> — rewind tour to previous page
  vim.keymap.set("n", back_key, function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local bubble = S().nearest_bubble(row)
    if not bubble or not bubble.pages then return end
    M.rewind_tour(bubble, config)
  end, opts)

  -- q — dismiss nearest bubble
  vim.keymap.set("n", dismiss_key, function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local bubble = S().nearest_bubble(row)
    if not bubble then return end
    M.dismiss_bubble(bubble, config)
    S().remove_bubble(bubble.id)
  end, opts)

  -- <leader>ta (visual mode) — capture selection and ask a question in chat
  vim.keymap.set("v", ask_sel_key, function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
    vim.schedule(function()
      local start_pos = vim.api.nvim_buf_get_mark(source_bufnr, "<")
      local end_pos   = vim.api.nvim_buf_get_mark(source_bufnr, ">")
      local lines = vim.api.nvim_buf_get_lines(
        source_bufnr,
        start_pos[1] - 1,
        end_pos[1],
        false
      )
      local ts = require("nvim-teach.treesitter")
      local node_type = ts.node_type_at(source_bufnr, start_pos[1] - 1, start_pos[2])

      S().pending_selection = {
        text = table.concat(lines, "\n"),
        range = {
          start_row = start_pos[1] - 1,
          start_col = start_pos[2],
          end_row   = end_pos[1] - 1,
          end_col   = end_pos[2],
        },
        node_type = node_type,
      }

      local row = start_pos[1] - 1
      local bubble = S().nearest_bubble(row)
      vim.ui.input({ prompt = "Ask about selection: " }, function(text)
        if not text or text == "" then
          S().pending_selection = nil
          return
        end
        send_to_chat(bubble, text)
      end)
    end)
  end, opts)
end

--- Apply page N of a tour to the bubble: update content + anchor, re-render
--- the float, move the line highlight, and jump the cursor to the new anchor.
local function apply_page(bubble, page, config)
  local hl = require("nvim-teach.highlight")
  local ts = require("nvim-teach.treesitter")
  local s  = S()

  hl.clear_bubble(bubble.bufnr, s.ns_id, bubble)

  bubble.anchor_row     = page.row or 0
  bubble.title          = page.title
  bubble.body           = page.body or ""
  bubble.callout        = page.callout
  bubble.icon_codepoint = page.icon_codepoint

  local range = {
    start_row = bubble.anchor_row, start_col = 0,
    end_row   = bubble.anchor_row, end_col   = -1,
  }
  if page.node_type and page.node_type ~= "" then
    range = ts.expand_range_to_node(bubble.bufnr, range, page.node_type)
  end
  bubble.range = range

  local callouts = require("nvim-teach.callouts")
  bubble.sign_extmark_id = hl.set_sign(bubble.bufnr, s.ns_id, bubble.anchor_row, config.sign_text)
  if page.highlight ~= false then
    local hl_group = callouts.highlight_hl_group(page.highlight_color, page.callout)
    bubble.highlight_extmark_id = hl.set_range_highlight(bubble.bufnr, s.ns_id, range, hl_group)
  end

  -- Re-render the float; open_bubble_win will jump the cursor to the new anchor.
  W().update_bubble_content(bubble, config)
end

--- Advance a tour bubble to the next page, or dismiss it if it was on the last.
function M.advance_tour(bubble, config)
  if not bubble.pages then return end
  local next_idx = (bubble.current_page or 1) + 1
  if next_idx > #bubble.pages then
    M.dismiss_bubble(bubble, config)
    S().remove_bubble(bubble.id)
    return
  end
  bubble.current_page = next_idx
  apply_page(bubble, bubble.pages[next_idx], config)
end

--- Rewind a tour bubble to the previous page. No-op on the first page.
function M.rewind_tour(bubble, config)
  if not bubble.pages then return end
  local prev_idx = (bubble.current_page or 1) - 1
  if prev_idx < 1 then
    vim.notify("[nvim-teach] Already at first step.", vim.log.levels.INFO)
    return
  end
  bubble.current_page = prev_idx
  apply_page(bubble, bubble.pages[prev_idx], config)
end

--- Dismiss a bubble: close its float, clear its extmarks, mark as dismissed.
function M.dismiss_bubble(bubble, config)
  W().close_bubble_win(bubble)
  local hl = require("nvim-teach.highlight")
  hl.clear_bubble(bubble.bufnr, S().ns_id, bubble)
  bubble.is_dismissed = true
end

--- Remove all keymaps set by install_nav_keymaps.
function M.remove_nav_keymaps(source_bufnr, config)
  local km = config.keymaps or {}
  local keys = {
    km.next         or "]t",
    km.prev         or "[t",
    km.dismiss      or "q",
    km.reply        or "<CR>",
    km.back         or "<BS>",
  }
  for _, k in ipairs(keys) do
    pcall(vim.keymap.del, "n", k, { buffer = source_bufnr })
  end
  pcall(vim.keymap.del, "v", km.ask_selection or "<leader>ta", { buffer = source_bufnr })
end

return M
