-- teach_clear: LLM tool to remove annotations/bubbles.
local M = {}

M.name = "teach_clear"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_clear",
    description = "Remove annotation bubbles and/or highlights from the editor.",
    parameters = {
      type = "object",
      properties = {
        bubble_id = {
          type = "string",
          description = "ID of a specific bubble to remove. Omit to clear all bubbles.",
        },
        highlights_only = {
          type = "boolean",
          description = "If true, only remove highlight extmarks but keep floats visible.",
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
Use teach_clear to remove bubbles and highlights when moving to a new section.
Omit bubble_id to clear everything. Provide bubble_id to remove one specific bubble.
]]

M.cmds = {
  function(self, args, _opts)
    local session   = require("nvim-teach.session")
    local highlight = require("nvim-teach.highlight")
    local window    = require("nvim-teach.window")

    if args.bubble_id then
      -- Clear a specific bubble.
      local bubble = session.bubbles[args.bubble_id]
      if not bubble then
        return { status = "error", data = { message = "Bubble not found: " .. args.bubble_id } }
      end
      if not args.highlights_only then
        window.close_bubble_win(bubble)
      end
      highlight.clear_bubble(bubble.bufnr, session.ns_id, bubble)
      bubble.is_dismissed = true
      session.remove_bubble(args.bubble_id)
    else
      -- Clear everything.
      for _, bubble in pairs(session.bubbles) do
        if not args.highlights_only then
          window.close_bubble_win(bubble)
        end
      end
      local bufnr = session.bufnr or 0
      highlight.clear_all(bufnr, session.ns_id)
      session.bubbles = {}
      session.active_highlight = nil
    end

    return { status = "success", data = {} }
  end,
}

M.output = {
  success = function(self, stdout, meta) end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_clear error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
