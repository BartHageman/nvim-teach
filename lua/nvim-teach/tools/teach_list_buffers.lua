-- teach_list_buffers: LLM tool to list all loaded, listed buffers.
local M = {}

M.name = "teach_list_buffers"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_list_buffers",
    description = "List all loaded, listed buffers with their bufnr, name, filetype, modified flag, and a flag marking the current one. Use this to discover what files the user has open before choosing what to teach.",
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
Use teach_list_buffers to see which buffers the user has open. Pair with
teach_get_buffer_info to drill into one specific buffer.
]]

M.cmds = {
  function(self, _args, _opts)
    local current = vim.api.nvim_get_current_buf()
    local result = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buflisted then
        result[#result + 1] = {
          bufnr        = bufnr,
          name         = vim.api.nvim_buf_get_name(bufnr),
          filetype     = vim.bo[bufnr].filetype,
          is_current   = bufnr == current,
          is_modified  = vim.bo[bufnr].modified,
          line_count   = vim.api.nvim_buf_line_count(bufnr),
        }
      end
    end
    return { status = "success", data = { buffers = result } }
  end,
}

M.output = {
  success = function(self, stdout, meta)
    local raw = stdout and stdout[1]
    local data = (type(raw) == "table" and raw.data) or raw or {}
    local count = data.buffers and #data.buffers or 0
    meta.tools.chat:add_tool_output(self, vim.json.encode(data), ("Listed %d buffer(s)"):format(count))
  end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_list_buffers error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
