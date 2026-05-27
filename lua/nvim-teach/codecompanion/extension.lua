-- CodeCompanion extension shim.
-- This is the sole file that imports from codecompanion.* at runtime.
-- CC calls M.setup(opts, cc_config) before finalising its own setup,
-- giving us a chance to inject our tools into cc_config by reference.
local M = {}

function M.setup(opts, cc_config)
  cc_config = cc_config or {}
  cc_config.strategies = cc_config.strategies or {}
  cc_config.strategies.chat = cc_config.strategies.chat or {}
  cc_config.strategies.chat.tools = cc_config.strategies.chat.tools or {}

  local tools = require("nvim-teach.tools")
  for name, def in pairs(tools.definitions()) do
    cc_config.strategies.chat.tools[name] = def
  end
end

M.exports = {}

return M
