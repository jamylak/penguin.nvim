local history = require("penguin.history")
local matcher = require("penguin.matcher")
local ui = require("penguin.ui")

local Session = {}
Session.__index = Session

function Session:new(config)
  local session = setmetatable({
    closed = false,
    config = config,
    entries = history.collect(),
    matches = {},
    query = "",
    selection = 0,
  }, self)

  ui.open(session)
  session:refresh()

  return session
end

function Session:refresh()
  self.matches = matcher.filter(self.entries, self.query, self.config.ui.max_results)

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

function Session:move_selection(delta)
  if #self.matches == 0 then
    return
  end

  self.selection = ((self.selection - 1 + delta) % #self.matches) + 1
  ui.render(self)
end

function Session:confirm()
  local entry = self.matches[self.selection]

  if not entry then
    return
  end

  vim.notify(("penguin.nvim: selected `%s`"):format(entry.item.text), vim.log.levels.INFO)
  self:close()
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
  session.on_close = on_close
  return session
end

return M
