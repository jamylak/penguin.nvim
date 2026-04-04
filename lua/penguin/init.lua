local M = {}

M.config = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

function M.open()
  vim.notify("penguin.nvim: picker not implemented yet", vim.log.levels.INFO)
end

return M
