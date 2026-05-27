-- Minimal MCP server for nvim-teach.
-- Speaks MCP JSON-RPC over plain HTTP POST (no SSE).
-- Listens on 127.0.0.1:<port>; declare it in the claude_code ACP adapter:
--
--   defaults = {
--     mcpServers = {
--       ["nvim-teach"] = { type = "http", url = "http://127.0.0.1:7777/mcp" },
--     },
--   }
--
-- The handlers re-use the cmds[1] function from each tool in nvim-teach.tools.

local uv = vim.uv or vim.loop

local M = {}

local PROTOCOL_VERSION = "2024-11-05"
local SERVER_INFO      = { name = "nvim-teach", version = "0.1.0" }

local server_handle
local bound_port

-- ─── HTTP framing ──────────────────────────────────────────────────────────

local STATUS_TEXT = {
  [200] = "OK", [202] = "Accepted", [400] = "Bad Request",
  [404] = "Not Found", [500] = "Internal Server Error",
}

local function http_response(status, body)
  body = body or ""
  return table.concat({
    "HTTP/1.1" .. " " .. status .. " " .. (STATUS_TEXT[status] or "OK"),
    "Content-Type: application/json",
    "Content-Length: " .. #body,
    "Connection: close",
    "", body,
  }, "\r\n")
end

local function parse_request(raw)
  local header_end = raw:find("\r\n\r\n", 1, true)
  if not header_end then return nil end
  local head = raw:sub(1, header_end - 1)
  local body = raw:sub(header_end + 4)

  local request_line, header_block = head:match("^([^\r\n]+)\r?\n?(.*)$")
  local method, path = (request_line or ""):match("^(%S+)%s+(%S+)")
  local headers = {}
  for line in (header_block or ""):gmatch("[^\r\n]+") do
    local k, v = line:match("^([^:]+):%s*(.*)$")
    if k then headers[k:lower()] = v end
  end

  local cl = tonumber(headers["content-length"] or "0") or 0
  if #body < cl then return nil end  -- still receiving
  return { method = method, path = path, headers = headers, body = body:sub(1, cl) }
end

-- ─── MCP dispatch ──────────────────────────────────────────────────────────

local function tool_to_mcp(def)
  local fn = (def.schema or {})["function"] or {}
  local input_schema = fn.parameters or { type = "object", properties = vim.empty_dict() }
  if input_schema.properties and next(input_schema.properties) == nil then
    -- Empty Lua tables encode to JSON [] by default; MCP requires {} (record).
    input_schema = vim.tbl_extend("force", input_schema, { properties = vim.empty_dict() })
  end
  return {
    name        = fn.name or def.name,
    description = fn.description or "",
    inputSchema = input_schema,
  }
end

local function call_tool(name, args)
  local defs = require("nvim-teach.tools").definitions()
  local def  = defs[name]
  if not def then
    return { content = { { type = "text", text = "unknown tool: " .. name } }, isError = true }
  end

  -- Lazy-init the teaching session so MCP callers don't need a prior :NvimTeach.
  -- This also installs nav keymaps (<CR>/q/]t/[t) on the buffer so bubbles are
  -- actually interactive when driven purely from MCP.
  local session = require("nvim-teach.session")
  if not session.ns_id then
    local bufnr = vim.api.nvim_get_current_buf()
    session.init(bufnr)
    local cfg = require("nvim-teach").config or {}
    pcall(require("nvim-teach.keymaps").install_nav_keymaps, bufnr, cfg)
    -- Set up scroll tracking on the window currently showing this buffer.
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == bufnr then
        pcall(require("nvim-teach.window").setup_scroll_tracking, w, cfg)
        break
      end
    end
  end
  local cmd = def.cmds and def.cmds[1]
  if not cmd then
    return { content = { { type = "text", text = "tool has no command" } }, isError = true }
  end

  local ok, result = pcall(cmd, def, args or {}, {})
  if not ok then
    return { content = { { type = "text", text = "error: " .. tostring(result) } }, isError = true }
  end

  if type(result) == "table" and result.status == "error" then
    return { content = { { type = "text", text = tostring(result.data or "error") } }, isError = true }
  end

  local payload = (type(result) == "table" and result.data) or result or vim.empty_dict()
  return { content = { { type = "text", text = vim.json.encode(payload) } } }
end

local function dispatch(msg)
  local method = msg.method
  if method == "initialize" then
    return {
      protocolVersion = PROTOCOL_VERSION,
      capabilities    = { tools = vim.empty_dict() },
      serverInfo      = SERVER_INFO,
    }
  elseif method == "notifications/initialized" or method == "notifications/cancelled" then
    return nil  -- notification, no response
  elseif method == "tools/list" then
    local out = {}
    for _, def in pairs(require("nvim-teach.tools").definitions()) do
      table.insert(out, tool_to_mcp(def))
    end
    return { tools = out }
  elseif method == "tools/call" then
    local params = msg.params or {}
    return call_tool(params.name, params.arguments)
  else
    return nil, { code = -32601, message = "method not found: " .. tostring(method) }
  end
end

local function handle_jsonrpc(body)
  local ok, msg = pcall(vim.json.decode, body)
  if not ok or type(msg) ~= "table" then
    return vim.json.encode({
      jsonrpc = "2.0", id = vim.NIL,
      error = { code = -32700, message = "parse error" },
    })
  end
  if msg.id == nil then
    pcall(dispatch, msg)
    return nil  -- notification
  end
  local result, err = dispatch(msg)
  if err then
    return vim.json.encode({ jsonrpc = "2.0", id = msg.id, error = err })
  end
  return vim.json.encode({ jsonrpc = "2.0", id = msg.id, result = result or vim.empty_dict() })
end

-- ─── Connection handler ────────────────────────────────────────────────────

local function handle_request(req)
  if req.method == "POST" and (req.path == "/mcp" or req.path == "/") then
    local resp_body = handle_jsonrpc(req.body)
    if resp_body then
      return http_response(200, resp_body)
    end
    return http_response(202, "")
  end
  return http_response(404, vim.json.encode({ error = "not found" }))
end

local function handle_connection(client)
  local buf = ""
  client:read_start(vim.schedule_wrap(function(err, chunk)
    if err or not chunk then
      pcall(function() client:close() end)
      return
    end
    buf = buf .. chunk
    local req = parse_request(buf)
    if req then
      local resp = handle_request(req)
      client:write(resp, function()
        pcall(function() client:shutdown(function() client:close() end) end)
      end)
    end
  end))
end

-- ─── Public API ────────────────────────────────────────────────────────────

function M.start(opts)
  if server_handle then return bound_port end
  opts = opts or {}
  local host = opts.host or "127.0.0.1"
  local port = opts.port or 7777

  server_handle = uv.new_tcp()
  server_handle:bind(host, port)
  server_handle:listen(16, function(listen_err)
    if listen_err then return end
    local client = uv.new_tcp()
    server_handle:accept(client)
    vim.schedule(function() handle_connection(client) end)
  end)
  bound_port = server_handle:getsockname().port

  vim.notify(("[nvim-teach] MCP server on http://%s:%d/mcp"):format(host, bound_port),
             vim.log.levels.INFO)
  return bound_port
end

function M.stop()
  if not server_handle then return end
  pcall(function() server_handle:close() end)
  server_handle, bound_port = nil, nil
  vim.notify("[nvim-teach] MCP server stopped", vim.log.levels.INFO)
end

function M.port() return bound_port end

vim.api.nvim_create_user_command("NvimTeachMcp", function(args)
  local sub = args.args
  if sub == "" or sub == "start" then M.start()
  elseif sub == "stop" then M.stop()
  elseif sub == "status" then
    vim.notify(bound_port and ("running on port " .. bound_port) or "stopped")
  else vim.notify("[nvim-teach] unknown subcommand: " .. sub, vim.log.levels.WARN) end
end, {
  nargs = "?",
  complete = function() return { "start", "stop", "status" } end,
  desc = "nvim-teach MCP server: start | stop | status",
})

return M
