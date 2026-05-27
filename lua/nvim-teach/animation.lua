-- Breathing pulse backed by tiny-glimmer's animation factory.
-- We register a custom "breathe" effect that interpolates with a cosine so
-- the cycle has no sharp turning points (unlike the built-in "pulse" which
-- uses abs(sin) and feels jerky at the troughs).
local M = {}

local _lib = nil
local _registered = false
local _loaded = false

local function get_lib()
  if not _loaded then
    _loaded = true
    local ok, lib = pcall(require, "tiny-glimmer.lib")
    if ok then _lib = lib end
  end
  return _lib
end

--- Register our custom breathe effect into tiny-glimmer's effect pool.
--- Idempotent.
local function register_breathe()
  if _registered then return true end
  local ok_factory, AnimationFactory = pcall(require, "tiny-glimmer.animation.factory")
  local ok_utils, utils = pcall(require, "tiny-glimmer.utils")
  if not (ok_factory and ok_utils) then return false end

  local factory = AnimationFactory.get_instance()
  if not factory or not factory.effect_pool then return false end

  factory.effect_pool.breathe = {
    settings = {},
    builder = function(self)
      return {
        initial = utils.hex_to_rgb(self.settings.from_color),
        final   = utils.hex_to_rgb(self.settings.to_color),
      }
    end,
    build_starter = function(self)
      if self.builder then self.starter = self.builder(self) end
    end,
    update_settings = function(self, settings)
      self.settings = settings
    end,
    update_fn = function(self, progress)
      -- progress ∈ [0, 1] over one animation cycle. Cosine maps that to a
      -- smooth peak (t=1) → dim (t=0) → peak (t=1), no kinks.
      local t = (math.cos(progress * 2 * math.pi) + 1) / 2
      local from = self.starter.initial
      local to   = self.starter.final
      local current = {
        r = math.floor(from.r + (to.r - from.r) * (1 - t) + 0.5),
        g = math.floor(from.g + (to.g - from.g) * (1 - t) + 0.5),
        b = math.floor(from.b + (to.b - from.b) * (1 - t) + 0.5),
      }
      return utils.rgb_to_hex(current), 1
    end,
  }
  _registered = true
  return true
end

local function parse_hex(h)
  return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
end

local function blend(a, b, t)
  local ar, ag, ab = parse_hex(a)
  local br, bg, bb = parse_hex(b)
  local function mix(x, y) return math.floor(x * t + y * (1 - t) + 0.5) end
  return string.format("#%02x%02x%02x", mix(ar, br), mix(ag, bg), mix(ab, bb))
end

local function hex_of_bg(hl_group)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = hl_group, link = false })
  if not ok or not hl or not hl.bg then return nil end
  return string.format("#%06x", hl.bg)
end

--- Subtle peak: 12% toward white. Keeps text legibility intact.
local function peak_for(hl_group)
  local base = hex_of_bg(hl_group)
  if not base then return "#ffffff" end
  return blend("#ffffff", base, 0.12)
end

--- Whether tiny-glimmer is available and our breathe effect is registered.
function M.available()
  return get_lib() ~= nil and register_breathe()
end

--- Anchor a named breathe over a code range. Loops indefinitely until stopped.
--- Returns true on success, false if tiny-glimmer isn't available.
---@param name string  unique animation id (e.g. tostring(extmark_id))
---@param bufnr integer
---@param range table  { start_row, start_col, end_row, end_col } (0-indexed, end inclusive on rows)
---@param hl_group string  the highlight group whose bg color drives the pulse
function M.pulse_start(name, bufnr, range, hl_group)
  local lib = get_lib()
  if not lib then return false end
  if not register_breathe() then return false end

  local end_col = range.end_col
  if end_col == -1 or end_col == nil then
    local last_line = vim.api.nvim_buf_get_lines(bufnr, range.end_row, range.end_row + 1, false)[1] or ""
    end_col = #last_line
  end

  -- tiny-glimmer keys animations off nvim_get_current_buf() at call time, so
  -- run inside nvim_buf_call to make sure the pulse is registered against the
  -- source buffer rather than whatever's focused (e.g. the bubble's float).
  local ok = true
  vim.api.nvim_buf_call(bufnr, function()
    ok = pcall(lib.create_named_animation, name, {
      range = {
        start_line = range.start_row,
        start_col  = range.start_col or 0,
        end_line   = range.end_row,
        end_col    = end_col,
      },
      duration   = 2400,
      from_color = hl_group,
      to_color   = peak_for(hl_group),
      effect     = "breathe",
      loop       = true,
      loop_count = 0,
    })
  end)
  return ok
end

function M.pulse_stop(name, bufnr)
  local lib = get_lib()
  if not lib then return end
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_call(bufnr, function()
      pcall(lib.stop_animation, name)
    end)
  else
    pcall(lib.stop_animation, name)
  end
end

function M.stop_all()
  local lib = get_lib()
  if not lib or not M._names then return end
  for name in pairs(M._names) do pcall(lib.stop_animation, name) end
  M._names = {}
end

M._names = {}

function M.register(name)
  M._names[name] = true
end

--- Back-compat no-op: the continuous breathe is started inside
--- set_range_highlight, so this one-shot animate() is no longer needed.
function M.animate(_bufnr, _range) end

return M
