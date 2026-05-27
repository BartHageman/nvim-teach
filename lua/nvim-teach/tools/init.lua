-- Tool registry: assembles all tool definitions for injection into CodeCompanion.
local M = {}

function M.definitions()
  return {
    teach_highlight     = require("nvim-teach.tools.teach_highlight"),
    teach_bubble        = require("nvim-teach.tools.teach_bubble"),
    teach_tour          = require("nvim-teach.tools.teach_tour"),
    teach_ask           = require("nvim-teach.tools.teach_ask"),
    teach_clear         = require("nvim-teach.tools.teach_clear"),
    teach_get_selection = require("nvim-teach.tools.teach_get_selection"),
  }
end

--- Returns true if teach_bubble is already registered in CodeCompanion's tool table.
--- Used by the fallback injection path to avoid double-registration.
function M.is_registered()
  local ok, cc_tools = pcall(require, "codecompanion.strategies.chat.tools")
  if not ok then return false end
  return cc_tools["teach_bubble"] ~= nil
end

return M
