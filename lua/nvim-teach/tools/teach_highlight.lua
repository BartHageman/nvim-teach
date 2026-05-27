-- teach_highlight: LLM tool to highlight a code range.
local M = {}

M.name = "teach_highlight"

M.schema = {
  type = "function",
  ["function"] = {
    name = "teach_highlight",
    description = "Highlight a range of code to draw the user's attention. Only one teach_highlight range can exist at a time — calling this tool automatically clears any previous range highlight. Bubble line highlights are separate and are not affected.",
    parameters = {
      type = "object",
      properties = {
        bufnr = {
          type = "integer",
          description = "Buffer number. 0 = current buffer. Omit to use the teaching session buffer.",
        },
        start_row = {
          type = "integer",
          description = "Start row of the highlight range (0-indexed).",
        },
        start_col = {
          type = "integer",
          description = "Start column (0-indexed). Defaults to 0.",
        },
        end_row = {
          type = "integer",
          description = "End row of the highlight range (0-indexed, inclusive).",
        },
        end_col = {
          type = "integer",
          description = "End column (0-indexed). Use -1 for end of line.",
        },
        node_type = {
          type = "string",
          description = "Optional TreeSitter node type (e.g. 'function_definition'). Expands range to the nearest ancestor of this type.",
        },
        animate = {
          type = "boolean",
          description = "Whether to animate the highlight. Defaults to true.",
        },
        highlight_color = {
          type = "string",
          enum = { "green", "red", "blue", "yellow", "orange", "purple" },
          description = "Background color for the highlight. Defaults to green.",
        },
      },
      required = { "start_row", "end_row" },
    },
  },
}

M.opts = {
  requires_approval_before = false,
  requires_approval_after = false,
}

M.system_prompt = [[
You can use teach_highlight to draw the user's attention to a specific range of code.
Provide start_row and end_row (0-indexed).
Optionally set node_type to expand the range to the nearest TreeSitter node of that type
(e.g. "function_definition", "class_declaration", "if_statement").
]]

M.cmds = {
  function(self, args, _opts)
    local session = require("nvim-teach.session")
    local highlight = require("nvim-teach.highlight")
    local treesitter = require("nvim-teach.treesitter")
    local animation = require("nvim-teach.animation")

    local bufnr = args.bufnr or session.bufnr or 0
    local range = {
      start_row = args.start_row or 0,
      start_col = args.start_col or 0,
      end_row   = args.end_row   or args.start_row or 0,
      end_col   = args.end_col   ~= nil and args.end_col or -1,
    }

    -- Expand to TreeSitter node if requested.
    if args.node_type and args.node_type ~= "" then
      range = treesitter.expand_range_to_node(bufnr, range, args.node_type)
    end

    -- Enforce one-highlight-at-a-time: clear the previous teach_highlight range
    -- before placing the new one.
    if session.active_highlight then
      highlight.clear_range_highlight(
        session.active_highlight.bufnr,
        session.ns_id,
        session.active_highlight.extmark_id
      )
      session.active_highlight = nil
    end

    local callouts = require("nvim-teach.callouts")
    local hl_group = callouts.highlight_hl_group(args.highlight_color, nil)
    local eid = highlight.set_range_highlight(bufnr, session.ns_id, range, hl_group)
    session.active_highlight = { bufnr = bufnr, extmark_id = eid }

    local should_animate = args.animate ~= false
    if should_animate then
      animation.animate(bufnr, range)
    end

    return {
      status = "success",
      data = {
        extmark_id = eid,
        resolved_range = range,
      },
    }
  end,
}

M.output = {
  success = function(self, stdout, meta)
    -- No visible chat output needed; the highlight IS the output.
  end,
  error = function(self, stderr, meta)
    vim.notify("[nvim-teach] teach_highlight error: " .. tostring(stderr[1]), vim.log.levels.ERROR)
  end,
}

return M
