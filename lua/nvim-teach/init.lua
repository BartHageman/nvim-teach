-- nvim-teach: Public API
local M = {}

-- Holds the merged config after setup(). Exposed so tool files can read it.
M.config = {}

local SYSTEM_PROMPT = [[
You are an interactive code tutor. Your job is to help the user understand
the code that is currently open in their editor.

You have access to these tools:

- teach_highlight  : highlight a range of code to draw attention
- teach_bubble     : show an annotation floating window at a specific line
- teach_tour       : walk the user through code as a sequence of pages (one bubble hops)
- teach_ask        : show an interactive question bubble the user must answer
- teach_clear      : remove bubbles and highlights
- teach_get_selection : see what code the user currently has selected

Guidelines:
- Place ONE bubble at a time, or use teach_tour for a planned walkthrough.
- Wait for the user to reply (they press <CR> on the bubble) before continuing.
- Use teach_ask when you want the user to think actively before you explain.
- Use teach_get_selection if the user's reply seems to reference specific code.
- Pick a callout per bubble/page: note, tip, important, warning, caution.
- All row numbers are 0-indexed.
- Keep bubble body text concise (2-4 sentences). Use the chat for longer explanations.
- When the user says "next" or "continue", proceed to the next concept.
]]

--- Initial setup. Call once in your neovim config.
---@param opts table|nil  Override default config values.
function M.setup(opts)
  local config_m = require("nvim-teach.config")
  M.config = config_m.merge(opts)

  -- Define highlight groups (only if not already set by a colorscheme).
  -- Re-run on ColorScheme so the bubble bg stays in sync with Normal's bg.
  require("nvim-teach.highlight").define_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("NvimTeachHighlights", { clear = true }),
    callback = function() require("nvim-teach.highlight").define_highlights() end,
  })
end

--- Start a teaching session on the given buffer.
--- Opens a CodeCompanion chat pre-loaded with the teaching system prompt.
---@param bufnr integer|nil  Defaults to current buffer (0).
function M.start_session(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local session  = require("nvim-teach.session")
  local keymaps  = require("nvim-teach.keymaps")
  local window   = require("nvim-teach.window")

  session.init(bufnr)

  -- Find the source window to set up scroll tracking.
  local source_win = nil
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(w) == bufnr then
      source_win = w
      break
    end
  end
  if source_win then
    window.setup_scroll_tracking(source_win, M.config)
  end

  -- Open a CodeCompanion chat with the system prompt pre-loaded.
  local ok, cc = pcall(require, "codecompanion")
  if not ok then
    vim.notify("[nvim-teach] CodeCompanion is not installed.", vim.log.levels.ERROR)
    return
  end

  local chat = cc.chat({
    messages = {},
    hidden = false,
    callbacks = {
      on_created = function(c)
        session.chat = c
        -- Inject the teaching system prompt.
        pcall(function() c:set_system_prompt(SYSTEM_PROMPT) end)
        -- Add buffer context so the LLM can see the code.
        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local ft = vim.bo[bufnr].filetype
        local code = table.concat(lines, "\n")
        c:add_message({
          role = "user",
          content = "Here is the file I'd like you to teach me about:\n\n```"
            .. ft .. "\n" .. code .. "\n```\n\n"
            .. "Please start the tour — one bubble at a time.",
        })
      end,
    },
  })

  if not chat then
    vim.notify("[nvim-teach] Failed to open CodeCompanion chat.", vim.log.levels.ERROR)
    return
  end

  -- Install navigation keymaps on the source buffer.
  keymaps.install_nav_keymaps(bufnr, M.config)

  vim.notify("[nvim-teach] Teaching session started. Switch to the chat to begin.", vim.log.levels.INFO)
end

--- Clear all bubbles and highlights, and reset the session.
function M.clear_session()
  local session  = require("nvim-teach.session")
  local highlight= require("nvim-teach.highlight")
  local window   = require("nvim-teach.window")
  local keymaps  = require("nvim-teach.keymaps")

  for _, bubble in pairs(session.bubbles) do
    window.close_bubble_win(bubble)
  end

  if session.bufnr then
    highlight.clear_all(session.bufnr, session.ns_id)
    keymaps.remove_nav_keymaps(session.bufnr, M.config)
  end

  -- Remove scroll tracking autocmds.
  pcall(vim.api.nvim_del_augroup_by_name, "NvimTeachScroll")

  session.reset()
  vim.notify("[nvim-teach] Session cleared.", vim.log.levels.INFO)
end

-- Expose a :NvimTeach command for convenience.
vim.api.nvim_create_user_command("NvimTeach", function(args)
  local sub = args.args
  if sub == "start" or sub == "" then
    M.start_session()
  elseif sub == "clear" then
    M.clear_session()
  else
    vim.notify("[nvim-teach] Unknown subcommand: " .. sub, vim.log.levels.WARN)
  end
end, {
  nargs = "?",
  desc  = "nvim-teach: start | clear",
  complete = function() return { "start", "clear" } end,
})

return M
