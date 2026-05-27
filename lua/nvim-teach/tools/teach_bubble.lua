-- teach_bubble: LLM tool to place an annotation bubble at a code location.
local M = {}

M.name = "teach_bubble"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_bubble",
    description = "Show an annotation bubble (floating window) at a specific line of code.",
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

    -- Open floating window.
    window.open_bubble_win(bubble, cfg)

    -- Register bubble (keymaps are shared via install_nav_keymaps).
    session.add_bubble(bubble)
    keymaps.install_bubble_keymaps(bufnr, bubble, cfg)

    return {
      status = "success",
      data = { bubble_id = bubble.id },
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
