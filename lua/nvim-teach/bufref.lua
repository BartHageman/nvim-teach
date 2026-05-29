-- Resolve a {bufnr, path} reference to a concrete buffer number.
-- Tools that mutate the editor (place bubbles, highlights, run tours) must
-- pass an explicit target so they can't silently land in the wrong buffer.
local M = {}

--- Resolve args.bufnr / args.path to a valid bufnr.
---@param args table tool arguments
---@return integer|nil bufnr, string|nil err
function M.resolve(args)
  args = args or {}

  if args.bufnr ~= nil then
    if type(args.bufnr) ~= "number" then
      return nil, "bufnr must be an integer"
    end
    if not vim.api.nvim_buf_is_valid(args.bufnr) then
      return nil, "bufnr is not a valid buffer: " .. tostring(args.bufnr)
    end
    return args.bufnr
  end

  if args.path ~= nil then
    if type(args.path) ~= "string" or args.path == "" then
      return nil, "path must be a non-empty string"
    end
    local bufnr = vim.fn.bufnr(args.path)
    if bufnr == -1 then
      return nil, "no loaded buffer matches path: " .. args.path .. " (call teach_list_buffers to see what's open)"
    end
    return bufnr
  end

  return nil, "must pass either bufnr or path to identify the target buffer (call teach_list_buffers first)"
end

return M
