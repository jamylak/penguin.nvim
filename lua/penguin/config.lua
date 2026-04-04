local M = {}

M.defaults = {
  ui = {
    border = "rounded",
    max_results = 12,
    width = 72,
  },
}

function M.merge(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
