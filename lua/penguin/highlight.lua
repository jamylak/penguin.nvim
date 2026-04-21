local M = {}

-- Lua highlight baseline for benchmarking only.
-- Normal runtime should render match spans from native result metadata.
-- Keep this module around only to measure the old UI-side derivation cost
-- against the native score-plus-span path before removing it entirely.

local function merge_ranges(ranges)
  if #ranges == 0 then
    return ranges
  end

  table.sort(ranges, function(left, right)
    if left[1] == right[1] then
      return left[2] < right[2]
    end

    return left[1] < right[1]
  end)

  local merged = { { ranges[1][1], ranges[1][2] } }

  for index = 2, #ranges do
    local range = ranges[index]
    local last = merged[#merged]

    if range[1] > last[2] then
      merged[#merged + 1] = { range[1], range[2] }
    elseif range[2] > last[2] then
      last[2] = range[2]
    end
  end

  return merged
end

function M.query_tokens(query)
  local tokens = {}
  local seen = {}

  for token in (query or ""):gmatch("%S+") do
    local normalized = token:lower()

    if normalized ~= "" and not seen[normalized] then
      seen[normalized] = true
      tokens[#tokens + 1] = normalized
    end
  end

  return tokens
end

local function find_subsequence_ranges(lower_text, token)
  local ranges = {}
  local start_at = 1

  for index = 1, #token do
    local character = token:sub(index, index)
    local start_pos, end_pos = lower_text:find(character, start_at, true)

    if not start_pos then
      return {}
    end

    ranges[#ranges + 1] = { start_pos - 1, end_pos }
    start_at = start_pos + 1
  end

  return ranges
end

function M.find_match_ranges(text, query)
  local tokens = M.query_tokens(query)

  if #tokens == 0 or text == "" then
    return {}
  end

  local lower_text = text:lower()
  local ranges = {}

  for _, token in ipairs(tokens) do
    local found_exact = false
    local start_at = 1

    while true do
      local start_pos, end_pos = lower_text:find(token, start_at, true)

      if not start_pos then
        break
      end

      ranges[#ranges + 1] = { start_pos - 1, end_pos }
      start_at = start_pos + 1
      found_exact = true
    end

    if not found_exact then
      local fuzzy = find_subsequence_ranges(lower_text, token)

      for _, range in ipairs(fuzzy) do
        ranges[#ranges + 1] = range
      end
    end
  end

  return merge_ranges(ranges)
end

return M
