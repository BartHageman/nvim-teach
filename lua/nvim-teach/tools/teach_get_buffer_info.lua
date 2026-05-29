-- teach_get_buffer_info: LLM tool to inspect one buffer's state.
local M = {}

M.name = "teach_get_buffer_info"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_get_buffer_info",
    description = "Return detailed state for a single buffer: name, filetype, line count, modified flag, plus cursor/viewport/mode when visible, and any active teaching bubbles on it. Omit bufnr to inspect the current buffer.",
    parameters = {
      type = "object",
      properties = {
        bufnr = {
          type = "integer",
          description = "Buffer number to inspect. Omit (or 0) for the current buffer.",
        },
      },
    },
  },
}

M.opts = {
  requires_approval_before = false,
  requires_approval_after = false,
}

M.system_prompt = [[
Use teach_get_buffer_info to ground yourself in what the user is looking at.
Pass a bufnr from teach_list_buffers, or omit it to inspect the current buffer.
]]

M.cmds = {
  function(self, args, _opts)
    local session = require("nvim-teach.session")
    args = args or {}

    local bufnr = args.bufnr
    if not bufnr or bufnr == 0 then
      bufnr = vim.api.nvim_get_current_buf()
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
      return { status = "error", data = "Invalid bufnr: " .. tostring(bufnr) }
    end

    local data = {
      bufnr       = bufnr,
      name        = vim.api.nvim_buf_get_name(bufnr),
      filetype    = vim.bo[bufnr].filetype,
      line_count  = vim.api.nvim_buf_line_count(bufnr),
      is_modified = vim.bo[bufnr].modified,
      is_current  = bufnr == vim.api.nvim_get_current_buf(),
    }

    local winid = vim.fn.bufwinid(bufnr)
    if winid ~= -1 then
      local cur = vim.api.nvim_win_get_cursor(winid)
      data.cursor   = { row = cur[1] - 1, col = cur[2] }
      data.viewport = {
        top_line    = vim.fn.line("w0", winid) - 1,
        bottom_line = vim.fn.line("w$", winid) - 1,
      }
    end

    if data.is_current then
      data.mode = vim.api.nvim_get_mode().mode
    end

    local bubbles = {}
    for _, b in pairs(session.bubbles or {}) do
      if not b.is_dismissed and b.bufnr == bufnr then
        bubbles[#bubbles + 1] = {
          id         = b.id,
          anchor_row = b.anchor_row,
          title      = b.title,
        }
      end
    end
    data.active_bubbles = bubbles

    return { status = "success", data = data }
  end,
}

M.output = {
  success = function(self, stdout, meta)
    local raw = stdout and stdout[1]
    local data = (type(raw) == "table" and raw.data) or raw or {}
    local label = (data.name and data.name ~= "" and vim.fn.fnamemodify(data.name, ":t")) or ("buf " .. tostring(data.bufnr))
    meta.tools.chat:add_tool_output(self, vim.json.encode(data), "Buffer info: " .. label)
  end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_get_buffer_info error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
