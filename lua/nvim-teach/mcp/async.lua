-- Async helper for nvim-teach MCP tools.
--
-- Tools are run inside a coroutine by the MCP server (mcp/init.lua). When a
-- tool wants to wait for some condition without blocking neovim's input loop,
-- it calls `wait_for(cond_fn)`: the helper yields the coroutine, and a libuv
-- timer polls the condition. When it becomes true the coroutine is resumed.
-- nvim is fully responsive throughout.
local M = {}

local uv = vim.uv or vim.loop

---@param condition_fn fun(): boolean
---@param opts table|nil  { interval_ms?: number, timeout_ms?: number }
---@return boolean got  true if condition_fn returned truthy before timeout
function M.wait_for(condition_fn, opts)
  opts = opts or {}
  local interval = opts.interval_ms or 100
  local timeout  = opts.timeout_ms  or (5 * 60 * 1000)

  if condition_fn() then return true end

  local co, is_main = coroutine.running()
  if not co or is_main then
    -- Not inside a coroutine — fall back to vim.wait. Blocks input but only
    -- used when something other than the MCP server is driving the tool.
    return vim.wait(timeout, condition_fn, interval)
  end

  return coroutine.yield(function(resume)
    local timer = uv.new_timer()
    local elapsed = 0
    timer:start(interval, interval, vim.schedule_wrap(function()
      elapsed = elapsed + interval
      if condition_fn() then
        timer:stop(); timer:close()
        resume(true)
      elseif elapsed >= timeout then
        timer:stop(); timer:close()
        resume(false)
      end
    end))
  end)
end

return M
