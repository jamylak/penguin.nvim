local config = require("penguin.config")
local matcher = require("penguin.matcher")
local native = require("penguin.native")
local normal_enter = require("penguin.normal_enter")
local session = require("penguin.session")

local M = {
  _session = nil,
  config = config.defaults,
}

function M.setup(opts)
  M.config = config.merge(opts)

  if M.config.native.enabled then
    local ready = native.ensure_ready({
      auto_build = M.config.native.auto_build,
    })

    if not ready and not M.config.native.benchmark_only_lua then
      error(("penguin.nvim: native runtime unavailable: %s"):format(native.load_error or "unknown error"))
    end
  end

  matcher.configure(M.config)

  if M.config.open_on_bare_enter then
    normal_enter.enable()
  end
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

function M.handle_bare_enter()
  return normal_enter.handle_expr()
end

return M
