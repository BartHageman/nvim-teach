local M = {}

M.defaults = {
  highlight_group = "NvimTeachHL",
  sign_text = "▶",
  animate = true,
  keymaps = {
    reply = "<CR>",
    next = "]t",
    prev = "[t",
    dismiss = "q",
    ask_selection = "<leader>ta",
  },
  float = {
    border = "none",
    max_width = 60,
    max_height = 20,
  },
}

function M.merge(user_opts)
  return vim.tbl_deep_extend("force", M.defaults, user_opts or {})
end

return M
