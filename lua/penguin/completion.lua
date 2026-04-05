local M = {}

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

function M.collect(query)
  if vim.trim(query or "") == "" then
    return {}
  end

  local ok, values = pcall(vim.fn.getcompletion, query, completion_type(query))

  if not ok then
    return {}
  end

  local prefix = completion_prefix(query)
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

return M
