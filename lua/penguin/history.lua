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

function M.delete(text)
  text = vim.trim(text or "")

  if text == "" then
    return false
  end

  local deleted = false

  for index = vim.fn.histnr(":"), 1, -1 do
    if vim.trim(vim.fn.histget(":", index) or "") == text then
      if vim.fn.histdel(":", index) ~= 0 then
        deleted = true
      end
    end
  end

  if deleted then
    pcall(vim.cmd, "wshada!")
  end

  return deleted
end

return M
