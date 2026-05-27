-- Bubble constructor. Does not hold global state; that lives in session.lua.
local session = require("nvim-teach.session")

local M = {}

---@param opts table
---  kind: "annotation" | "question" | "tour_step"
---  bufnr: integer (defaults to session.bufnr)
---  anchor_row: integer (0-indexed)
---  anchor_col: integer (0-indexed, default 0)
---  range: { start_row, start_col, end_row, end_col } (defaults to anchor line)
---  title: string|nil
---  body: string
---  question: string|nil  (only for kind == "question")
---@return table bubble
function M.new(opts)
  local bufnr = opts.bufnr or session.bufnr or 0
  local anchor_row = opts.anchor_row or 0
  local anchor_col = opts.anchor_col or 0

  local range = opts.range or {
    start_row = anchor_row,
    start_col = 0,
    end_row = anchor_row,
    end_col = -1,
  }

  return {
    id = session.next_id(),
    kind = opts.kind or "annotation",

    bufnr = bufnr,
    anchor_row = anchor_row,
    anchor_col = anchor_col,
    range = range,

    -- Extmark IDs (so we can clean up precisely)
    highlight_extmark_id = nil,
    sign_extmark_id = nil,

    -- Floating window
    winid = nil,
    win_bufnr = nil,

    -- Content
    title = opts.title,
    body = opts.body or "",
    question = opts.question,
    choices = opts.choices,

    -- Callout style: kind name from callouts.kinds, plus optional explicit
    -- codepoint override. Both are nil for default ("note").
    callout = opts.callout,
    icon_codepoint = opts.icon_codepoint,

    -- Tour state. pages is an array of page descriptors; current_page is
    -- 1-indexed. Non-tour bubbles leave both nil.
    pages = opts.pages,
    current_page = opts.pages and 1 or nil,

    -- Per-bubble conversation thread
    thread = {},

    -- State
    is_dismissed = false,
    is_answered = false,
  }
end

return M
