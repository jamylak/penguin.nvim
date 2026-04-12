local completion = require("penguin.completion")
local history = require("penguin.history")
local matcher = require("penguin.matcher")
local native = require("penguin.native")
local ui = require("penguin.ui")

local Session = {}
Session.__index = Session

local function execute_command(text)
  local command = vim.trim(text or "")

  if command == "" then
    return false
  end

  local ok, err = pcall(vim.cmd, command)

  if not ok then
    vim.notify(("penguin.nvim: %s"):format(err), vim.log.levels.ERROR)
  end

  return ok
end

local function run_after_close(text)
  vim.schedule(function()
    execute_command(text)
  end)
end

local function build_native_matcher(entries)
  if not native.available then
    return nil
  end

  return native.new_exact_matcher(entries)
end

local function merge_matches(history_matches, completion_matches, limit)
  local merged = {}
  local positions = {}

  local function add(result)
    local key = result.item.text
    local index = positions[key]

    if not index then
      positions[key] = #merged + 1
      table.insert(merged, result)
      return
    end

    if matcher.compare_results(result, merged[index]) then
      merged[index] = result
    end
  end

  for _, result in ipairs(history_matches) do
    add(result)
  end

  for _, result in ipairs(completion_matches) do
    add(result)
  end

  return matcher.sort_results(merged, limit)
end

function Session:new(config)
  local session = setmetatable({
    closed = false,
    config = config,
    entries = history.collect(),
    matches = {},
    query = "",
    selection = 0,
  }, self)

  return session
end

function Session:refresh()
  local limit = self.config.ui.max_results
  local completion_items = completion.collect(self.query)
  local history_matches = matcher.filter(self.entries, self.query, limit, {
    native_matcher = self.native_history_matcher,
  })
  local completion_matches = matcher.filter(completion_items, self.query, limit, {
    native_matcher = build_native_matcher(completion_items),
  })

  self.matches = merge_matches(history_matches, completion_matches, limit)

  if #self.matches == 0 then
    self.selection = 0
  else
    self.selection = math.min(math.max(self.selection, 1), #self.matches)
  end

  ui.render(self)
end

function Session:set_query(query)
  query = query or ""

  if query == self.query then
    return
  end

  self.query = query
  self.selection = 1
  self:refresh()
end

function Session:selected_text()
  local entry = self.matches[self.selection]

  if not entry then
    return nil
  end

  return entry.item.text
end

function Session:move_selection(delta)
  if #self.matches == 0 then
    return
  end

  self.selection = ((self.selection - 1 + delta) % #self.matches) + 1
  ui.render(self)
end

function Session:complete_selection()
  local text = self:selected_text()

  if not text then
    return
  end

  self:set_query(text)
  ui.set_prompt_text(self, text)
  ui.focus_prompt(self)
end

function Session:submit_query()
  local text = self.query

  if vim.trim(text or "") == "" then
    return
  end

  self:close()
  run_after_close(text)
end

function Session:confirm()
  local text = self:selected_text()

  if not text then
    return
  end

  self:close()
  run_after_close(text)
end

function Session:close()
  if self.closed then
    return
  end

  self.closed = true
  ui.close(self)

  if self.on_close then
    self.on_close()
  end
end

local M = {}

function M.open(config, on_close)
  local session = Session:new(config)
  session.native_history_matcher = build_native_matcher(session.entries)
  session.on_close = on_close
  ui.open(session)
  session:refresh()
  return session
end

return M
