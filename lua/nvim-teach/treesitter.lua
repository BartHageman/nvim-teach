-- TreeSitter helpers. Gracefully degrades if TS is not available.
local M = {}

--- Get the range of the smallest named TS node at (row, col).
---@return table|nil { start_row, start_col, end_row, end_col }
function M.get_node_range(bufnr, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return nil end

  local ok2, trees = pcall(function() return parser:parse() end)
  if not ok2 or not trees or not trees[1] then return nil end

  local root = trees[1]:root()
  local node = root:named_descendant_for_range(row, col, row, col)
  if not node then return nil end

  local sr, sc, er, ec = node:range()
  return { start_row = sr, start_col = sc, end_row = er, end_col = ec }
end

--- Expand a range upward in the TS tree to the nearest ancestor of node_type.
--- Returns the expanded range, or the original range if no such ancestor is found.
---@param bufnr integer
---@param range table { start_row, start_col, end_row, end_col }
---@param node_type string  e.g. "function_definition", "class_declaration"
---@return table range
function M.expand_range_to_node(bufnr, range, node_type)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return range end

  local ok2, trees = pcall(function() return parser:parse() end)
  if not ok2 or not trees or not trees[1] then return range end

  local root = trees[1]:root()

  -- Start from the node at the range's start position.
  local node = root:named_descendant_for_range(
    range.start_row, range.start_col,
    range.start_row, range.start_col
  )

  -- Walk up the tree looking for node_type.
  while node do
    if node:type() == node_type then
      local sr, sc, er, ec = node:range()
      return { start_row = sr, start_col = sc, end_row = er, end_col = ec }
    end
    node = node:parent()
  end

  return range
end

--- Return the node type at a given position, or nil.
---@return string|nil
function M.node_type_at(bufnr, row, col)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if not ok or not parser then return nil end

  local ok2, trees = pcall(function() return parser:parse() end)
  if not ok2 or not trees or not trees[1] then return nil end

  local root = trees[1]:root()
  local node = root:named_descendant_for_range(row, col, row, col)
  return node and node:type() or nil
end

return M
