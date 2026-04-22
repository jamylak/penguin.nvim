local M = {}
local command_strategies = {
  checkhealth = "prefix_cached_deferred",
}
-- Maps unique typed command prefixes to the configured strategy key they should
-- inherit.
--
-- Example with:
--   command_strategies = {
--     checkhealth = "prefix_cached_deferred",
--   }
--
-- the rebuilt lookup table becomes:
--   {
--     che = "checkhealth",
--     chec = "checkhealth",
--     check = "checkhealth",
--     checkh = "checkhealth",
--     checkhe = "checkhealth",
--     checkhea = "checkhealth",
--     checkheal = "checkhealth",
--     checkhealt = "checkhealth",
--     checkhealth = "checkhealth",
--   }
--
-- Ambiguous prefixes are stored as `false`, which makes them fall back to the
-- original typed command name instead of inheriting a strategy.
local strategy_command_lookup = {}
local all_commands_cache_key = "__penguin_all_commands__"
local command_fuzzy_fallback_min_query_length = 4

M._complete = function(query, kind)
  return vim.fn.getcompletion(query, kind)
end

---Build the abbreviation lookup derived from `command_strategies`.
---
---This keeps the hot lookup path in `strategy_command_name()` table-based.
---Whenever configuration changes the set of slow-command strategies, regenerate
---all unique prefixes once up front instead of scanning every configured
---command on each query refresh.
local function build_strategy_command_lookup()
  local lookup = {}

  for command in pairs(command_strategies) do
    for length = 1, #command do
      local prefix = command:sub(1, length)
      local existing = lookup[prefix]

      if existing == nil then
        lookup[prefix] = command
      elseif existing ~= command then
        lookup[prefix] = false
      end
    end
  end

  strategy_command_lookup = lookup
end

function M.configure(config)
  local strategies = config
    and config.completion
    and config.completion.command_strategies

  if type(strategies) == "table" then
    command_strategies = {}

    for command, strategy in pairs(strategies) do
      local normalized_command = vim.trim(command or ""):lower()
      local normalized_strategy = vim.trim(strategy or "")

      if normalized_command ~= "" and normalized_strategy ~= "" then
        command_strategies[normalized_command] = normalized_strategy
      end
    end
  else
    command_strategies = {
      checkhealth = "prefix_cached_deferred",
    }
  end

  build_strategy_command_lookup()
end

---@param query string
---@return string
local function completion_type(query)
  if query:find("%s") then
    return "cmdline"
  end

  return "command"
end

local function completion_prefix(query)
  if not query:find("%s") then
    return ""
  end

  if query:match("%s$") then
    return query
  end

  return query:match("^(.*%s)") or ""
end

---@param query string
---@return string
local function command_name(query)
  return ((query:match("^%s*(%S+)") or ""):gsub("!$", "")):lower()
end

---Resolve the command key used for completion strategy lookup.
---
---This maps the typed Ex command name to the configured strategy entry in
---`command_strategies`:
---
---  input `checkhealth` -> `checkhealth`
---  input `che`         -> `checkhealth`  when `che` is a unique abbreviation
---  input `ch`          -> `ch`           when no configured strategy matches
---  input `c`           -> `c`            when multiple configured commands
---                                      would share that prefix
---
---Why this exists:
---Neovim accepts unique Ex-command abbreviations, so `:che` runs
---`:checkhealth`. Penguin needs to mirror that rule during strategy lookup or
---the `checkhealth = "prefix_cached_deferred"` setting will not apply until
---the full command name is typed.
---
---Example:
---  typed command name = `che`
---  strategy_command_lookup = {
---    che = "checkhealth",
---    chec = "checkhealth",
---    ....
---    checkhealth = "checkhealth",
---  }
---
---  strategy_command_name("che")         -> "checkhealth"
---  strategy_command_name("checkhealth") -> "checkhealth"
---  strategy_command_name("zzz")         -> "zzz"
---
---This function reads the precomputed `strategy_command_lookup` table built by
---`build_strategy_command_lookup()`, so the runtime path stays a single table
---lookup instead of scanning every configured strategy command each time.
---
---@param name string Typed Ex command name with no arguments, e.g. `che`.
---@return string Strategy lookup key, either the exact configured command name
---or the original input when no unique configured match exists.
local function strategy_command_name(name)
  local normalized = vim.trim(name or ""):lower()

  if normalized == "" then
    return ""
  end

  local resolved = strategy_command_lookup[normalized]

  if type(resolved) == "string" then
    return resolved
  end

  return normalized
end

---@param query string|nil
---@return { cache_key: string|nil, defer: boolean, kind: string, lookup_query: string, prefix: string }|nil
local function completion_plan(query)
  if vim.trim(query or "") == "" then
    return nil
  end

  local kind = completion_type(query)
  local prefix = completion_prefix(query)
  local lookup_query = query
  local cache_key = nil
  local defer = false

  if kind == "cmdline" then
    local strategy = command_strategies[strategy_command_name(command_name(query))] or "live"

    if strategy == "deferred" then
      defer = true
      cache_key = query
    elseif strategy == "prefix_cached_deferred" then
      -- `:checkhealth` is the motivating case: argument completion can be
      -- slow, and the candidates depend mostly on the command name rather than
      -- the typed suffix. Collapse related suffix probes to a stable prefix so
      -- repeated typing does not keep recomputing the same expensive result.
      defer = true
      cache_key = prefix
      lookup_query = prefix
    end
  end

  return {
    cache_key = cache_key,
    defer = defer,
    kind = kind,
    lookup_query = lookup_query,
    prefix = prefix,
  }
end

local function build_items(prefix, values)
  local items = {}
  local seen = {}

  for index, value in ipairs(values) do
    local text = vim.trim(prefix .. value)

    if text ~= "" and not seen[text] then
      seen[text] = true

      table.insert(items, {
        completion_rank = index,
        recency = math.huge,
        source = "completion",
        source_rank = 2,
        text = text,
      })
    end
  end

  return items
end

---@param context { cache_key: string|nil, defer: boolean, kind: string, lookup_query: string, prefix: string }
---@param values string[]
---@return boolean
local function should_fallback_to_all_commands(context, values)
  if context.kind ~= "command" or #values > 0 then
    return false
  end

  if #context.lookup_query < command_fuzzy_fallback_min_query_length then
    return false
  end

  return true
end

---@param cache table<string, string[]>|nil
---@return string[]
local function fetch_all_command_values(cache)
  local cached = cache and cache[all_commands_cache_key]

  if cached ~= nil then
    return cached
  end

  local ok, values = pcall(M._complete, "", "command")

  if not ok then
    values = {}
  end

  if cache then
    cache[all_commands_cache_key] = values
  end

  return values
end

---@param context { cache_key: string|nil, defer: boolean, kind: string, lookup_query: string, prefix: string }
---@param cache table<string, string[]>|nil
---@return string[]
local function fetch_values(context, cache)
  local cached = cache and context.cache_key and cache[context.cache_key]

  if cached ~= nil then
    return cached
  end

  local ok, values = pcall(M._complete, context.lookup_query, context.kind)

  if not ok then
    values = {}
  end

  if should_fallback_to_all_commands(context, values) then
    -- Repro from the Neogit case:
    --   getcompletion("Neogit", "command")
    --     -> { "Neogit", "NeogitDiff", "NeogitDiffMain", ... }
    --   getcompletion("Neogitdiff", "command")
    --     -> {}
    --
    -- Neovim only answers literal-prefix command completion here, so the more
    -- specific probe loses `NeogitDiff` entirely even though Penguin's fuzzy
    -- matcher would still rank it as the best hit. Falling back to the full
    -- command list once lets the native matcher recover that result.
    --
    -- The minimum length keeps short misses like `ckh` from pulling the whole
    -- command table into Lua. This fallback is intentionally lazy and cached:
    -- one extra `getcompletion("", "command")` on the first long prefix miss,
    -- then reuse that list for the rest of the session.
    values = fetch_all_command_values(cache)
  end

  if cache and context.cache_key then
    cache[context.cache_key] = values
  end

  return values
end

function M.cached(query, cache)
  local context = completion_plan(query)

  if not context or not context.defer or not context.cache_key then
    return {}
  end

  local values = cache and cache[context.cache_key]

  if values == nil then
    return {}
  end

  return build_items(context.prefix, values)
end

---@param query string|nil
---@param cache table<string, string[]>|nil
---@return boolean
function M.needs_deferred_fetch(query, cache)
  local context = completion_plan(query)

  if not context or not context.defer or not context.cache_key then
    -- Command-name completion (`:set`, `:check`, etc.) stays synchronous.
    return false
  end

  return not (cache and cache[context.cache_key] ~= nil)
end

function M.collect(query, cache)
  local context = completion_plan(query)

  if not context then
    return {}
  end

  return build_items(context.prefix, fetch_values(context, cache))
end

function M.plan(query, cache)
  local context = completion_plan(query)

  if not context then
    return {
      cache_key = nil,
      defer = false,
      immediate_items = {},
      lookup_query = nil,
      needs_fetch = false,
      query = query,
    }
  end

  return {
    cache_key = context.cache_key,
    defer = context.defer,
    immediate_items = context.defer and M.cached(query, cache) or {},
    lookup_query = context.lookup_query,
    needs_fetch = context.defer and not (cache and context.cache_key and cache[context.cache_key] ~= nil),
    query = query,
  }
end

return M
