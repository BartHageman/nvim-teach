-- teach_bubble: LLM tool to place an annotation bubble at a code location.
-- Read-only annotation: bubbles never collect user input. All replies come
-- through the chat on a subsequent turn.
local M = {}

M.name = "teach_bubble"

local DESCRIPTION = [[Place a read-only annotation bubble (floating window) at a code line. Returns immediately with the bubble_id; the bubble cannot collect user input.

User input always arrives through the chat on a later turn. Pick one of these pacing patterns deliberately:

  1. Single bubble, then yield: post one bubble whose body asks a question or invites a reply (e.g. "What do you think this does? Reply in chat."), then end your turn and wait for the user's next chat message.
  2. Multi-bubble sequence: post several bubbles in one turn to walk through code, then end your turn. The user reads them and dismisses each with <CR>; nothing is sent back automatically.
  3. No bubble, just highlight: use teach_highlight to mark code and ask your question in the chat directly.

Bubbles never return user replies via the tool result. The cursor jumps to the bubble's anchor row when it opens, so the bubble is guaranteed visible.]]

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_bubble",
    description = DESCRIPTION,
    parameters = {
      type = "object",
      properties = {
        bufnr = {
          type = "integer",
          description = "Target buffer number (from teach_list_buffers). Required unless `path` is given.",
        },
        path = {
          type = "string",
          description = "Target buffer's file path (alternative to bufnr; more robust across sessions). Required unless `bufnr` is given. Must match a buffer that is currently loaded.",
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
          description = "Background color for the line highlight. Defaults to a color derived from the callout kind.",
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

M.system_prompt = DESCRIPTION

M.cmds = {
  function(self, args, _opts)
    local session   = require("nvim-teach.session")
    local bubble_m  = require("nvim-teach.bubble")
    local highlight = require("nvim-teach.highlight")
    local window    = require("nvim-teach.window")
    local keymaps   = require("nvim-teach.keymaps")

    local cfg = require("nvim-teach").config or {}

    local bufnr, err = require("nvim-teach.bufref").resolve(args)
    if not bufnr then
      return { status = "error", data = err }
    end
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

    bubble.sign_extmark_id = highlight.set_sign(bufnr, session.ns_id, row, cfg.sign_text)

    if args.highlight ~= false then
      local callouts = require("nvim-teach.callouts")
      local hl_group = callouts.highlight_hl_group(args.highlight_color, args.callout)
      bubble.highlight_extmark_id = highlight.set_range_highlight(bufnr, session.ns_id, {
        start_row = row, start_col = 0,
        end_row   = row, end_col   = -1,
      }, hl_group)
    end

    window.open_bubble_win(bubble, cfg)

    session.add_bubble(bubble)
    keymaps.install_bubble_keymaps(bufnr, bubble, cfg)

    return {
      status = "success",
      data = { bubble_id = bubble.id },
    }
  end,
}

M.output = {
  success = function(self, stdout, meta) end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_bubble error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
