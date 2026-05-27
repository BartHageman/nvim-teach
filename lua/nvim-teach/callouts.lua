-- Callout kinds for bubbles. Nerd font glyphs live here as integer codepoints
-- so they're never written into LLM output, source files, or anywhere they
-- might get mangled by encoding round-trips.
local M = {}

-- Codepoints reference nerd-fonts.com (Font Awesome v4 region, stable).
M.kinds = {
  note      = { codepoint = 0xf05a, hl = "NvimTeachCalloutNote"      },
  tip       = { codepoint = 0xf0eb, hl = "NvimTeachCalloutTip"       },
  important = { codepoint = 0xf06a, hl = "NvimTeachCalloutImportant" },
  warning   = { codepoint = 0xf071, hl = "NvimTeachCalloutWarning"   },
  caution   = { codepoint = 0xf057, hl = "NvimTeachCalloutCaution"   },
}

M.default = "note"

-- Map a callout kind to a default highlight color name. Used when the LLM
-- doesn't supply an explicit `highlight_color`.
M.default_highlight_color = {
  note      = "blue",
  tip       = "green",
  important = "red",
  warning   = "orange",
  caution   = "red",
}

local VALID_COLORS = {
  green = true, red = true, blue = true, yellow = true, orange = true, purple = true,
}

--- Resolve a highlight color name into a highlight group, falling back to
--- the callout-derived default and finally to plain NvimTeachHL.
---@param color string|nil
---@param callout string|nil
---@return string hl_group
function M.highlight_hl_group(color, callout)
  if color and not VALID_COLORS[color] then color = nil end
  color = color or M.default_highlight_color[callout or M.default] or "green"
  return "NvimTeachHL" .. color:sub(1, 1):upper() .. color:sub(2)
end

--- Resolve a bubble's callout to { glyph, accent_hl, bubble_hl, stripe_hl, kind_title }.
--- Honors explicit icon_codepoint override; otherwise looks up `kind`.
---@param bubble table
function M.resolve(bubble)
  local kind = bubble.callout or M.default
  if not M.kinds[kind] then kind = M.default end
  local spec = M.kinds[kind]
  local cp = bubble.icon_codepoint or spec.codepoint
  local title_case = kind:sub(1, 1):upper() .. kind:sub(2)
  return vim.fn.nr2char(cp),
         spec.hl,
         "NvimTeachBubble" .. title_case,
         "NvimTeachStripe" .. title_case,
         title_case
end

return M
