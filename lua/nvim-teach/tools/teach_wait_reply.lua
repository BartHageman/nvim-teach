-- teach_wait_reply: LLM tool to block until a previously-shown bubble has
-- been replied to (or dismissed) by the user.
local M = {}

M.name = "teach_wait_reply"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_wait_reply",
    description = "Block until the user replies to or dismisses the bubble with the given bubble_id. Returns { kind = 'reply'|'dismissed', reply = text? }.",
    parameters = {
      type = "object",
      properties = {
        bubble_id = {
          type = "string",
          description = "ID returned by teach_bubble / teach_ask.",
        },
        timeout_seconds = {
          type = "integer",
          description = "Maximum seconds to wait. Defaults to 300 (5 minutes). Pass 0 to return immediately with whatever state is currently available.",
        },
      },
      required = { "bubble_id" },
    },
  },
}

M.opts = {
  requires_approval_before = false,
  requires_approval_after  = false,
}

M.system_prompt = [[
Use teach_wait_reply after teach_bubble or teach_ask when you want to wait
for the user's response. Pass the bubble_id from the previous call.
]]

M.cmds = {
  function(self, args, _opts)
    local session = require("nvim-teach.session")
    local async   = require("nvim-teach.mcp.async")
    session.outcomes = session.outcomes or {}

    local id = args.bubble_id
    if not id then
      return { status = "error", data = { message = "bubble_id is required" } }
    end

    local timeout_s = args.timeout_seconds or 300

    -- Non-blocking probe.
    if timeout_s <= 0 then
      local existing = session.outcomes[id]
      session.outcomes[id] = nil
      local out = existing or { kind = "pending" }
      return {
        status = "success",
        data = { bubble_id = id, kind = out.kind, reply = out.text },
      }
    end

    -- Wait via coroutine yield (mcp/init.lua runs us in a coroutine; the
    -- libuv timer in async.wait_for resumes us when the outcome arrives,
    -- without blocking neovim's input loop).
    async.wait_for(function() return session.outcomes[id] ~= nil end, {
      timeout_ms  = timeout_s * 1000,
      interval_ms = 75,
    })

    local outcome = session.outcomes[id] or { kind = "timeout" }
    session.outcomes[id] = nil
    return {
      status = "success",
      data = { bubble_id = id, kind = outcome.kind, reply = outcome.text },
    }
  end,
}

M.output = {
  success = function(self, stdout, meta) end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_wait_reply error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
