local config = require("penguin.config")
local matcher = require("penguin.matcher")
local session = require("penguin.session")

local M = {
  _session = nil,
  config = config.defaults,
}

function M.setup(opts)
  M.config = config.merge(opts)
  matcher.configure(M.config)
end

function M.open()
  if M._session and not M._session.closed then
    M._session:close()
  end

  M._session = session.open(M.config, function()
    M._session = nil
  end)
end

function M.close()
  if M._session and not M._session.closed then
    M._session:close()
  end
end

return M
