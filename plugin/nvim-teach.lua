-- Auto-load entrypoint. Runs after all plugins are loaded.
-- Provides a fallback tool injection path in case the CC extension API
-- passes a config copy rather than a reference (see plan risks section).

vim.api.nvim_create_autocmd("User", {
  pattern = "CodeCompanionLoaded",  -- emitted by CC after it finishes setup
  once = true,
  callback = function()
    local tools_m = require("nvim-teach.tools")
    if tools_m.is_registered() then return end  -- already injected via extension API

    -- Fallback: monkey-patch CC's internal tool registry.
    -- This path is only taken if the extension shim did not work.
    local ok, cc_tools = pcall(require, "codecompanion.strategies.chat.tools")
    if not ok then return end

    for name, def in pairs(tools_m.definitions()) do
      if not cc_tools[name] then
        cc_tools[name] = def
      end
    end
  end,
})
