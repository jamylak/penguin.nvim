local M = {}

M.defaults = {
  native = {
    -- Temporary development-only switch for Step C of the native rollout.
    -- This only touches the native boundary and still keeps Lua scoring active.
    dev_probe = false,
  },
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
