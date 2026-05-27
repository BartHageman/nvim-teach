-- teach_ask: LLM tool to place an interactive question bubble.
local M = {}

M.name = "teach_ask"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_ask",
    description = "Show an interactive question bubble. By default blocks until the user replies or dismisses, returning { kind, reply? }. Pass wait=false to return immediately.",
    parameters = {
      type = "object",
      properties = {
        bufnr = {
          type = "integer",
          description = "Buffer number. 0 = current. Omit for session buffer.",
        },
        row = {
          type = "integer",
          description = "Anchor row (0-indexed).",
        },
        col = {
          type = "integer",
          description = "Anchor column (0-indexed). Defaults to 0.",
        },
        title = {
          type = "string",
          description = "Title for the bubble border. E.g. 'Question'.",
        },
        body = {
          type = "string",
          description = "Context or preamble shown before the question.",
        },
        question = {
          type = "string",
          description = "The specific question for the user to answer.",
        },
        choices = {
          type = "array",
          description = "Optional list of multiple-choice answers (strings). User can press 1-9 to select.",
          items = { type = "string" },
        },
        highlight = {
          type = "boolean",
          description = "Whether to highlight the anchor line. Defaults to true.",
        },
        wait = {
          type = "boolean",
          description = "If true (default), block until the user replies or dismisses. If false, return immediately with just bubble_id.",
        },
        timeout_seconds = {
          type = "integer",
          description = "Max seconds to wait for a reply when wait=true. Defaults to 300.",
        },
      },
      required = { "row", "question" },
    },
  },
}

M.opts = {
  requires_approval_before = false,
  requires_approval_after = false,
}

M.system_prompt = [[
Use teach_ask to ask the user a question about the code.
The bubble will show both body text and the question.
The user presses <CR> to open a reply prompt.
Wait for their answer before continuing.
All row numbers are 0-indexed.
]]

M.cmds = {
  function(self, args, _opts)
    local session   = require("nvim-teach.session")
    local bubble_m  = require("nvim-teach.bubble")
    local highlight = require("nvim-teach.highlight")
    local window    = require("nvim-teach.window")
    local keymaps   = require("nvim-teach.keymaps")

    local cfg = require("nvim-teach").config or {}

    local bufnr = args.bufnr or session.bufnr or 0
    local row   = args.row   or 0
    local col   = args.col   or 0

    local bubble = bubble_m.new({
      kind       = "question",
      bufnr      = bufnr,
      anchor_row = row,
      anchor_col = col,
      title      = args.title or "Question",
      body       = args.body  or "",
      question   = args.question,
      choices    = args.choices,
    })

    bubble.sign_extmark_id = highlight.set_sign(bufnr, session.ns_id, row, cfg.sign_text)

    if args.highlight ~= false then
      bubble.highlight_extmark_id = highlight.set_range_highlight(bufnr, session.ns_id, {
        start_row = row, start_col = 0,
        end_row   = row, end_col   = -1,
      }, "NvimTeachQuestion")
    end

    session.outcomes = session.outcomes or {}
    bubble.on_reply = function(text)
      session.outcomes[bubble.id] = { kind = "reply", text = text }
    end
    bubble.on_dismiss = function()
      if not session.outcomes[bubble.id] then
        session.outcomes[bubble.id] = { kind = "dismissed" }
      end
    end

    window.open_bubble_win(bubble, cfg)
    session.add_bubble(bubble)
    keymaps.install_bubble_keymaps(bufnr, bubble, cfg)

    -- If choices provided, install number keymaps on the float buffer.
    if bubble.win_bufnr and bubble.choices and #bubble.choices > 0 then
      for i, choice in ipairs(bubble.choices) do
        local key = tostring(i)
        vim.keymap.set("n", key, function()
          keymaps.reply_with_text(bubble, key .. ". " .. choice)
        end, { buffer = bubble.win_bufnr, silent = true })
      end
    end

    if args.wait == false then
      return {
        status = "success",
        data = { bubble_id = bubble.id },
      }
    end

    local async = require("nvim-teach.mcp.async")
    local timeout_s = args.timeout_seconds or 300
    async.wait_for(function() return session.outcomes[bubble.id] ~= nil end, {
      timeout_ms  = timeout_s * 1000,
      interval_ms = 75,
    })

    local outcome = session.outcomes[bubble.id] or { kind = "timeout" }
    session.outcomes[bubble.id] = nil
    return {
      status = "success",
      data = {
        bubble_id = bubble.id,
        kind      = outcome.kind,
        reply     = outcome.text,
      },
    }
  end,
}

M.output = {
  success = function(self, stdout, meta) end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_ask error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
