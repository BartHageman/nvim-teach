-- teach_tour: LLM tool to walk the user through code as a sequence of pages.
-- Renders one bubble that hops between anchor rows as the user presses <CR>.
local M = {}

M.name = "teach_tour"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_tour",
    description = "Create a multi-page tour. One bubble hops between anchor rows as the user advances with <CR>. Final page dismisses on <CR>.",
    parameters = {
      type = "object",
      properties = {
        bufnr = {
          type = "integer",
          description = "Buffer number. 0 = current. Omit for session buffer.",
        },
        pages = {
          type = "array",
          description = "Ordered tour pages. The bubble starts on page 1 and advances on <CR>.",
          items = {
            type = "object",
            properties = {
              row = {
                type = "integer",
                description = "Anchor row for this page (0-indexed).",
              },
              title = {
                type = "string",
                description = "Title shown on the page header.",
              },
              body = {
                type = "string",
                description = "Page body text.",
              },
              callout = {
                type = "string",
                enum = { "note", "tip", "important", "warning", "caution" },
                description = "Callout kind for this page. Defaults to 'note'.",
              },
              icon_codepoint = {
                type = "integer",
                description = "Optional Unicode codepoint (integer) overriding the page's callout icon.",
              },
              node_type = {
                type = "string",
                description = "Optional TreeSitter node type; expands the line highlight to the nearest ancestor of this type.",
              },
              highlight = {
                type = "boolean",
                description = "Whether to highlight the anchor line/range on this page. Defaults to true.",
              },
              highlight_color = {
                type = "string",
                enum = { "green", "red", "blue", "yellow", "orange", "purple" },
                description = "Background color for the line highlight on this page. Defaults to a color derived from the page's callout kind.",
              },
            },
            required = { "row", "body" },
          },
        },
      },
      required = { "pages" },
    },
  },
}

M.opts = {
  requires_approval_before = false,
  requires_approval_after = false,
}

M.system_prompt = [[
Use teach_tour to lead the user through code as a sequence of pages.
Each page anchors at a row and gets a title + body. The user presses <CR>
to advance to the next page (the bubble moves) or q to quit. Order pages
in reading order. Pick a callout kind per page (note/tip/important/warning/caution)
to match the content's emphasis.
]]

M.cmds = {
  function(self, args, _opts)
    local session   = require("nvim-teach.session")
    local bubble_m  = require("nvim-teach.bubble")
    local highlight = require("nvim-teach.highlight")
    local window    = require("nvim-teach.window")
    local treesitter = require("nvim-teach.treesitter")
    local cfg = require("nvim-teach").config or {}

    local pages = args.pages or {}
    if #pages == 0 then
      return { status = "error", data = { message = "teach_tour requires at least one page" } }
    end

    local bufnr = args.bufnr or session.bufnr or 0
    local first = pages[1]

    local bubble = bubble_m.new({
      kind           = "tour",
      bufnr          = bufnr,
      anchor_row     = first.row or 0,
      title          = first.title,
      body           = first.body or "",
      callout        = first.callout,
      icon_codepoint = first.icon_codepoint,
      pages          = pages,
    })

    -- Initial range + extmarks for page 1.
    local range = {
      start_row = bubble.anchor_row, start_col = 0,
      end_row   = bubble.anchor_row, end_col   = -1,
    }
    if first.node_type and first.node_type ~= "" then
      range = treesitter.expand_range_to_node(bufnr, range, first.node_type)
    end
    bubble.range = range

    local callouts = require("nvim-teach.callouts")
    bubble.sign_extmark_id = highlight.set_sign(bufnr, session.ns_id, bubble.anchor_row, cfg.sign_text)
    if first.highlight ~= false then
      local hl_group = callouts.highlight_hl_group(first.highlight_color, first.callout)
      bubble.highlight_extmark_id = highlight.set_range_highlight(bufnr, session.ns_id, range, hl_group)
    end

    -- Jump cursor to first anchor so the float lands in view.
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == bufnr then
        pcall(vim.api.nvim_win_set_cursor, w, { bubble.anchor_row + 1, 0 })
        break
      end
    end

    window.open_bubble_win(bubble, cfg)
    session.add_bubble(bubble)

    return {
      status = "success",
      data = { bubble_id = bubble.id, total_pages = #pages },
    }
  end,
}

M.output = {
  success = function(self, stdout, meta) end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_tour error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
