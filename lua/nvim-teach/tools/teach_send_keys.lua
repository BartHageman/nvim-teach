-- teach_send_keys: agent-driven keystrokes, gated by a per-call consent prompt.
local M = {}

M.name = "teach_send_keys"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_send_keys",
    description = "Ask the user for permission to feed a key sequence into Neovim (motions, ex-commands, mappings). Every call shows the user the keys plus your explanation and waits for Accept/Reject. Use this to demonstrate motions or run commands the user can then learn from.",
    parameters = {
      type = "object",
      properties = {
        keys = {
          type = "string",
          description = "Key sequence in Vim notation, e.g. 'gg', '<C-w>v', ':Telescope find_files<CR>'. Translated via nvim_replace_termcodes.",
        },
        mode = {
          type = "string",
          description = "feedkeys mode flag. Default 'n' (no remap). Use 'm' to honor user remaps, 't' for terminal-mode literal.",
        },
        explanation = {
          type = "string",
          description = "One-sentence reason shown to the user explaining why these keys help them learn.",
        },
      },
      required = { "keys", "explanation" },
    },
  },
}

M.opts = {
  requires_approval_before = true,
  requires_approval_after  = false,
}

M.system_prompt = [[
Use teach_send_keys to demonstrate motions or run a command in the user's
Neovim. The user is prompted to Accept or Reject every call; always provide
a clear `explanation` so they can decide. Prefer small, single-purpose key
sequences over long chains, and pair with a teach_bubble or chat message that
explains what the keys do.
]]

local function feed(keys, mode)
  local termed = vim.api.nvim_replace_termcodes(keys, true, false, true)
  vim.api.nvim_feedkeys(termed, mode or "n", false)
end

M.cmds = {
  function(self, args, _opts)
    args = args or {}
    local keys = args.keys
    local explanation = args.explanation
    local mode = args.mode or "n"

    if type(keys) ~= "string" or keys == "" then
      return { status = "error", data = "Missing required arg: keys" }
    end
    if type(explanation) ~= "string" or explanation == "" then
      return { status = "error", data = "Missing required arg: explanation" }
    end

    local prompt = string.format("Agent wants to send: %s  —  %s", keys, explanation)

    -- MCP path: we're inside the coroutine in mcp/init.lua:call_tool_async.
    -- Yield a setup function that drives vim.ui.select and resumes us with the choice.
    if coroutine.isyieldable() then
      local choice = coroutine.yield(function(resume)
        vim.schedule(function()
          vim.ui.select({ "Accept", "Reject" }, { prompt = prompt }, function(c) resume(c) end)
        end)
      end)
      if choice == "Accept" then
        feed(keys, mode)
        return { status = "success", data = { sent = keys } }
      end
      return { status = "rejected", data = { message = "User declined." } }
    end

    -- Non-coroutine path (CodeCompanion native, etc.): blocking confirm fallback.
    local ok = vim.fn.confirm(prompt, "&Accept\n&Reject", 2) == 1
    if ok then
      feed(keys, mode)
      return { status = "success", data = { sent = keys } }
    end
    return { status = "rejected", data = { message = "User declined." } }
  end,
}

M.output = {
  success = function(self, stdout, meta)
    local raw = stdout and stdout[1]
    local data = (type(raw) == "table" and raw.data) or raw or {}
    local status = (type(raw) == "table" and raw.status) or "success"
    local display
    if status == "rejected" then
      display = "Keys rejected by user"
    else
      display = "Sent: " .. tostring(data.sent or "")
    end
    meta.tools.chat:add_tool_output(self, vim.json.encode({ status = status, data = data }), display)
  end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_send_keys error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
