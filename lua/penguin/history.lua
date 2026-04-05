local M = {}

function M.collect()
  local items = {}
  local latest = vim.fn.histnr(":")

  for index = latest, 1, -1 do
    local text = vim.trim(vim.fn.histget(":", index) or "")

    if text ~= "" then
      table.insert(items, {
        recency = latest - index,
        source = "history",
        source_rank = 1,
        text = text,
      })
    end
  end

  return items
end

return M
