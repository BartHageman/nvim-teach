-- Session singleton: owns all active state for the current teaching session.
local M = {
  bufnr = nil,
  ns_id = nil,
  bubbles = {},      -- keyed by bubble.id
  chat = nil,        -- reference to active CodeCompanion chat object
  pending_selection = nil,  -- { text, range, node_type } set by visual-ask keymap
  _bubble_counter = 0,
}

function M.init(bufnr)
  M.bufnr = bufnr
  M.ns_id = vim.api.nvim_create_namespace("nvim_teach")
  M.bubbles = {}
  M.chat = nil
  M.pending_selection = nil
  M._bubble_counter = 0
end

function M.reset()
  M.bufnr = nil
  M.bubbles = {}
  M.chat = nil
  M.pending_selection = nil
  M._bubble_counter = 0
end

function M.next_id()
  M._bubble_counter = M._bubble_counter + 1
  return "teach_bubble_" .. M._bubble_counter
end

function M.add_bubble(bubble)
  M.bubbles[bubble.id] = bubble
end

function M.remove_bubble(id)
  M.bubbles[id] = nil
end

-- Returns the bubble whose anchor_row is closest to the given row.
-- Returns nil if no bubbles exist.
function M.nearest_bubble(row)
  local best = nil
  local best_dist = math.huge
  for _, b in pairs(M.bubbles) do
    if not b.is_dismissed then
      local dist = math.abs(b.anchor_row - row)
      if dist < best_dist then
        best_dist = dist
        best = b
      end
    end
  end
  return best
end

-- Returns bubbles sorted by anchor_row ascending.
function M.sorted_bubbles()
  local list = {}
  for _, b in pairs(M.bubbles) do
    if not b.is_dismissed then
      list[#list + 1] = b
    end
  end
  table.sort(list, function(a, b) return a.anchor_row < b.anchor_row end)
  return list
end

return M
