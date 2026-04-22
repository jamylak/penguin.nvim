local M = {}
local command_strategies = {
  checkhealth = "prefix_cached_deferred",
}
local all_commands_cache_key = "__penguin_all_commands__"
local command_fuzzy_fallback_min_query_length = 4

M._complete = function(query, kind)
  return vim.fn.getcompletion(query, kind)
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

    return
  end

  command_strategies = {
    checkhealth = "prefix_cached_deferred",
  }
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
---@param name string Typed Ex command name with no arguments, e.g. `che`.
---@return string Strategy lookup key, either the exact configured command name
---or the original input when no unique configured match exists.
local function strategy_command_name(name)
  local normalized = vim.trim(name or ""):lower()

  if normalized == "" then
    return ""
  end

  if command_strategies[normalized] ~= nil then
    return normalized
  end

  local matched = nil

  -- `command_strategies` is a map like:
  --   {
  --     checkhealth = "prefix_cached_deferred",
  --     slowcmd = "deferred",
  --   }
  --
  -- Iterate over those configured command names and see whether the typed
  -- command is a prefix of exactly one of them.
  for candidate in pairs(command_strategies) do
    -- Ex commands accept unique abbreviations, so `:che` executes
    -- `:checkhealth`. Strategy lookup needs to mirror that behavior or slow
    -- commands fall back to live per-keystroke completion until the full name
    -- is typed out.
    if vim.startswith(candidate, normalized) then
      -- Only inherit the strategy when the abbreviation is unambiguous.
      -- Ambiguous prefixes should behave like a normal live command probe.
      if matched ~= nil then
        return normalized
      end

      matched = candidate
    end
  end

  return matched or normalized
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
