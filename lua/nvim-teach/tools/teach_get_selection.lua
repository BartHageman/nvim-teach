-- teach_get_selection: LLM tool to read the user's current visual selection.
local M = {}

M.name = "teach_get_selection"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_get_selection",
    description = "Returns the text and position of the user's current (or last) visual selection, plus the nearest bubble ID and TreeSitter node type at that position.",
    parameters = {
      type = "object",
      properties = {},
    },
  },
}

M.opts = {
  requires_approval_before = false,
  requires_approval_after = false,
}

M.system_prompt = [[
Use teach_get_selection to see what code the user has currently selected or highlighted.
This helps you understand what they are confused about or interested in.
]]

M.cmds = {
  function(self, _args, _opts)
    local session    = require("nvim-teach.session")
    local treesitter = require("nvim-teach.treesitter")

    local bufnr = session.bufnr or 0

    -- Read visual marks (set after the user exits visual mode).
    local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")  -- {line, col} 1-indexed
    local end_pos   = vim.api.nvim_buf_get_mark(bufnr, ">")

    if start_pos[1] == 0 then
      -- No selection has been made yet.
      return {
        status = "success",
        data = {
          text = "",
          range = nil,
          node_type = nil,
          nearest_bubble_id = nil,
          message = "No selection available.",
        },
      }
    end

    local lines = vim.api.nvim_buf_get_lines(bufnr, start_pos[1] - 1, end_pos[1], false)
    local text = table.concat(lines, "\n")

    local range = {
      start_row = start_pos[1] - 1,
      start_col = start_pos[2],
      end_row   = end_pos[1] - 1,
      end_col   = end_pos[2],
    }

    local node_type = treesitter.node_type_at(bufnr, range.start_row, range.start_col)

    local nearest = session.nearest_bubble(range.start_row)

    return {
      status = "success",
      data = {
        text              = text,
        range             = range,
        node_type         = node_type,
        nearest_bubble_id = nearest and nearest.id or nil,
      },
    }
  end,
}

M.output = {
  success = function(self, stdout, meta)
    -- stdout[1] is the return value of the cmds function: { status, data }
    local raw = stdout and stdout[1]
    local data = (type(raw) == "table" and raw.data) or raw or {}
    local text = (type(data) == "table" and data.text) or ""

    local json_out = vim.json.encode(data)
    local display  = text ~= "" and ("Selection: " .. text:sub(1, 80) .. (text:len() > 80 and "..." or "")) or "(no selection)"
    meta.tools.chat:add_tool_output(self, json_out, display)
  end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_get_selection error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
