-- teach_navigate: open another file with a quick centered flash so the user
-- sees where they're being taken. The explanation belongs in the chat — this
-- tool just signals the transition visually.
local M = {}

M.name = "teach_navigate"

local DESCRIPTION = [[Move the user to another file with a brief centered flash showing the filename and target line. The flash is just a transition signal — explain WHY you're navigating in the chat BEFORE calling this tool, not in the bubble.

The flash shows the file icon + path:line for ~1500ms (configurable via flash_ms), then the buffer swaps and the cursor lands on the target row centered with `zz`. A small breadcrumb appears at the destination for ~2500ms (configurable via breadcrumb_ms) so the user can see where they landed even if they were reading the chat during the flash. No bubble is left at the destination by default — if you need to annotate the destination, call teach_bubble after.

Pattern:
  1. In the chat, tell the user where you're going and why ("Let's check parser.lua to see how this is consumed.").
  2. Call teach_navigate.
  3. Optionally call teach_bubble at the destination to annotate.

Do not stack multiple teach_navigate calls — give the user a chance to read in between.]]

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_navigate",
    description = DESCRIPTION,
    parameters = {
      type = "object",
      properties = {
        file = {
          type = "string",
          description = "Absolute or workspace-relative path of the file to open.",
        },
        row = {
          type = "integer",
          description = "1-indexed line number to land on in the target file.",
        },
        col = {
          type = "integer",
          description = "0-indexed column. Defaults to 0.",
        },
        split = {
          type = "string",
          enum = { "none", "horizontal", "vertical" },
          description = "How to open the file. 'none' (default) replaces the current window; 'horizontal' / 'vertical' open in a split so the previous file stays visible.",
        },
        flash_ms = {
          type = "integer",
          description = "Milliseconds to show the centered flash before swapping the buffer. Defaults to 1500. Keep this short — it's a transition signal, not reading material.",
        },
        breadcrumb_ms = {
          type = "integer",
          description = "Milliseconds to show the destination breadcrumb after landing. Defaults to 2500. Set to 0 to disable.",
        },
      },
      required = { "file", "row" },
    },
  },
}

M.opts = {
  requires_approval_before = false,
  requires_approval_after = false,
}

M.system_prompt = DESCRIPTION

local uv = vim.uv or vim.loop

--- Open a small centered floating window showing "  <icon> <path>:<row>".
--- Returns { win, buf } for the caller to close. Falls back to no icon if
--- nvim-web-devicons isn't installed.
local function open_flash(short_path, row)
  local name = vim.fn.fnamemodify(short_path, ":t")
  local ext  = vim.fn.fnamemodify(name, ":e")
  local icon = ""
  local ok_dev, devicons = pcall(require, "nvim-web-devicons")
  if ok_dev then
    local got = devicons.get_icon(name, ext, { default = true })
    if got then icon = got end
  end
  if icon ~= "" then icon = icon .. " " end

  local text  = "  " .. icon .. short_path .. ":" .. row .. "  "
  local width = vim.fn.strdisplaywidth(text)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { text })

  local win = vim.api.nvim_open_win(buf, false, {
    relative  = "editor",
    row       = math.floor(vim.o.lines / 2) - 1,
    col       = math.floor((vim.o.columns - width) / 2),
    width     = width,
    height    = 1,
    style     = "minimal",
    border    = "rounded",
    focusable = false,
    zindex    = 100,
  })
  pcall(vim.api.nvim_set_hl, 0, "NvimTeachNavFlash", { bg = "NONE", fg = "#cdd6f4", bold = true })
  pcall(vim.api.nvim_win_set_option, win, "winhl", "Normal:NvimTeachNavFlash,FloatBorder:Comment")

  return { win = win, buf = buf }
end

local function close_flash(flash)
  if not flash then return end
  if flash.win and vim.api.nvim_win_is_valid(flash.win) then
    pcall(vim.api.nvim_win_close, flash.win, true)
  end
  if flash.buf and vim.api.nvim_buf_is_valid(flash.buf) then
    pcall(vim.api.nvim_buf_delete, flash.buf, { force = true })
  end
end

M.cmds = {
  function(self, args, _opts)
    local session = require("nvim-teach.session")
    local window  = require("nvim-teach.window")
    local keymaps = require("nvim-teach.keymaps")
    local cfg = require("nvim-teach").config or {}

    local file = args.file
    if not file or file == "" then
      return { status = "error", data = { message = "file is required" } }
    end
    local stat = uv.fs_stat(file)
    if not stat then
      return { status = "error", data = { message = "file not found: " .. file } }
    end

    local row           = args.row or 1
    local col           = args.col or 0
    local split         = args.split or "none"
    local flash_ms      = args.flash_ms or 1500
    local breadcrumb_ms = args.breadcrumb_ms or 2500

    local short_path = vim.fn.fnamemodify(file, ":~:.")
    local flash = open_flash(short_path, row)

    vim.defer_fn(function()
      close_flash(flash)

      local escaped = vim.fn.fnameescape(file)
      local cmd
      if split == "horizontal" then
        cmd = "split " .. escaped
      elseif split == "vertical" then
        cmd = "vsplit " .. escaped
      else
        cmd = "edit " .. escaped
      end
      local ok, err = pcall(vim.cmd, cmd)
      if not ok then
        vim.notify("[nvim-teach] teach_navigate: " .. tostring(err), vim.log.levels.ERROR)
        return
      end

      local target_bufnr = vim.api.nvim_get_current_buf()
      local line_count = vim.api.nvim_buf_line_count(target_bufnr)
      local target_row = math.min(math.max(row, 1), line_count)
      pcall(vim.api.nvim_win_set_cursor, 0, { target_row, col })
      pcall(vim.cmd, "normal! zz")

      if breadcrumb_ms > 0 then
        local ns = vim.api.nvim_create_namespace("nvim_teach_breadcrumb")
        pcall(vim.api.nvim_set_hl, 0, "NvimTeachBreadcrumb", { fg = "#1e1e2e", bg = "#89b4fa", bold = true })
        local label = "  ↳ landed here (line " .. target_row .. ")  "
        local anchor_line = math.max(target_row - 2, 0)
        local ok_ext, ext_id = pcall(vim.api.nvim_buf_set_extmark, target_bufnr, ns, anchor_line, 0, {
          virt_lines = { { { label, "NvimTeachBreadcrumb" } } },
          virt_lines_above = false,
        })
        if ok_ext then
          vim.defer_fn(function()
            if vim.api.nvim_buf_is_valid(target_bufnr) then
              pcall(vim.api.nvim_buf_del_extmark, target_bufnr, ns, ext_id)
            end
          end, breadcrumb_ms)
        end
      end

      -- Track the new buffer for subsequent tool calls.
      session.bufnr = target_bufnr
      pcall(keymaps.install_nav_keymaps, target_bufnr, cfg)
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(w) == target_bufnr then
          pcall(window.setup_scroll_tracking, w, cfg)
          break
        end
      end
    end, flash_ms)

    return {
      status = "success",
      data = { file = file, row = row, flash_ms = flash_ms },
    }
  end,
}

M.output = {
  success = function(self, stdout, meta) end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_navigate error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
