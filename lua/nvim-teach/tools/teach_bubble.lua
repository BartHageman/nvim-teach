-- teach_bubble: LLM tool to place an annotation bubble at a code location.
local M = {}

M.name = "teach_bubble"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_bubble",
    description = "Show an annotation bubble (floating window) at a specific line of code. By default blocks until the user replies (<CR> then text) or dismisses (q), returning { kind = 'reply'|'dismissed', reply = text? }. Pass wait=false to return immediately with just the bubble_id.",
    parameters = {
      type = "object",
      properties = {
        bufnr = {
          type = "integer",
          description = "Buffer number. 0 = current. Omit for session buffer.",
        },
        row = {
          type = "integer",
          description = "Anchor row for the bubble (0-indexed).",
        },
        col = {
          type = "integer",
          description = "Anchor column (0-indexed). Defaults to 0.",
        },
        title = {
          type = "string",
          description = "Title shown in the bubble border. E.g. 'Step 1'.",
        },
        body = {
          type = "string",
          description = "The annotation text shown in the bubble.",
        },
        highlight = {
          type = "boolean",
          description = "Whether to also highlight the anchor line. Defaults to true.",
        },
        callout = {
          type = "string",
          enum = { "note", "tip", "important", "warning", "caution" },
          description = "Callout kind. Picks the icon and accent color. Defaults to 'note'.",
        },
        icon_codepoint = {
          type = "integer",
          description = "Optional Unicode codepoint (integer, e.g. 0xf0eb) overriding the callout's default icon. Pass an integer, not a glyph.",
        },
        highlight_color = {
          type = "string",
          enum = { "green", "red", "blue", "yellow", "orange", "purple" },
          description = "Background color for the line highlight. Defaults to a color derived from the callout kind (note=blue, tip=green, important=red, warning=orange, caution=red).",
        },
        wait = {
          type = "boolean",
          description = "If true (default), block until the user replies or dismisses, and return the result. If false, return immediately with just bubble_id.",
        },
        timeout_seconds = {
          type = "integer",
          description = "Max seconds to wait for a reply when wait=true. Defaults to 300.",
        },
      },
      required = { "row", "body" },
    },
  },
}

M.opts = {
  requires_approval_before = false,
  requires_approval_after = false,
}

M.system_prompt = [[
Use teach_bubble to place an annotation bubble on a specific line of code.
The user will see a floating window with your annotation text.
They can press <CR> to reply to the bubble or q to dismiss it.
Wait for the user to respond before placing the next bubble.
All row numbers are 0-indexed.
]]

M.cmds = {
  function(self, args, _opts)
    local session   = require("nvim-teach.session")
    local bubble_m  = require("nvim-teach.bubble")
    local highlight = require("nvim-teach.highlight")
    local window    = require("nvim-teach.window")
    local keymaps   = require("nvim-teach.keymaps")

    -- We need the config; retrieve it from the main module.
    local cfg = require("nvim-teach").config or {}

    local bufnr = args.bufnr or session.bufnr or 0
    local row   = args.row   or 0
    local col   = args.col   or 0

    local bubble = bubble_m.new({
      kind           = "annotation",
      bufnr          = bufnr,
      anchor_row     = row,
      anchor_col     = col,
      title          = args.title,
      body           = args.body or "",
      callout        = args.callout,
      icon_codepoint = args.icon_codepoint,
    })

    -- Gutter sign.
    bubble.sign_extmark_id = highlight.set_sign(bufnr, session.ns_id, row, cfg.sign_text)

    -- Optional line highlight.
    if args.highlight ~= false then
      local callouts = require("nvim-teach.callouts")
      local hl_group = callouts.highlight_hl_group(args.highlight_color, args.callout)
      bubble.highlight_extmark_id = highlight.set_range_highlight(bufnr, session.ns_id, {
        start_row = row, start_col = 0,
        end_row   = row, end_col   = -1,
      }, hl_group)
    end

    -- Wire callbacks that stash the outcome on session.outcomes[bubble_id].
    -- teach_wait_reply polls that table to retrieve the result later.
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

    -- Register bubble (keymaps are shared via install_nav_keymaps).
    session.add_bubble(bubble)
    keymaps.install_bubble_keymaps(bufnr, bubble, cfg)

    if args.wait == false then
      return {
        status = "success",
        data = { bubble_id = bubble.id },
      }
    end

    -- Block until the user replies or dismisses. async.wait_for yields the
    -- enclosing coroutine and a libuv timer resumes it — neovim stays
    -- responsive throughout.
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
  success = function(self, stdout, meta)
    -- The float is the output; no chat message needed.
  end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_bubble error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
