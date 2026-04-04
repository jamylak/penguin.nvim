local M = {}

local function normalize(text)
  return (text or ""):lower()
end

local function compact(text)
  return normalize(text):gsub("[^%w]+", "")
end

local function tokenize_words(text)
  local words = {}

  for word in normalize(text):gmatch("[%w_]+") do
    table.insert(words, word)
  end

  return words
end

local function subsequence_score(needle, haystack)
  if needle == "" or haystack == "" then
    return nil
  end

  local substring_start = haystack:find(needle, 1, true)

  if substring_start then
    local score = 300 - (substring_start * 4) - (#haystack - #needle)

    if substring_start == 1 then
      score = score + 30
    end

    return score
  end

  local position = 1
  local first_index = nil
  local gaps = 0
  local adjacent = 0
  local previous = nil

  for index = 1, #needle do
    local character = needle:sub(index, index)
    local found = haystack:find(character, position, true)

    if not found then
      return nil
    end

    if not first_index then
      first_index = found
    end

    if previous and found == previous + 1 then
      adjacent = adjacent + 1
    end

    gaps = gaps + math.max(0, found - position)
    previous = found
    position = found + 1
  end

  local score = 120 - (gaps * 3) + (adjacent * 8) - ((first_index or 1) * 2)

  if first_index == 1 then
    score = score + 15
  end

  return score
end

local function best_token_score(token, candidate)
  local best = subsequence_score(token, candidate.compact)

  for _, word in ipairs(candidate.words) do
    local score = subsequence_score(token, word)

    if score and (not best or score > best) then
      best = score
    end
  end

  return best
end

local function token_score(tokens, candidate)
  local total = 0

  for _, token in ipairs(tokens) do
    local score = best_token_score(token, candidate)

    if not score then
      return nil
    end

    total = total + score
  end

  if #tokens > 1 then
    total = total + (#tokens * 12)
  end

  return total
end

local function segmented_score(query, candidate)
  local length = #query

  if length < 4 or #candidate.words < 2 then
    return nil
  end

  local best = nil

  local function evaluate(segments)
    local total = 0

    for _, segment in ipairs(segments) do
      local score = nil

      for _, word in ipairs(candidate.words) do
        local word_score = subsequence_score(segment, word)

        if word_score and (not score or word_score > score) then
          score = word_score
        end
      end

      if not score then
        return
      end

      total = total + score
    end

    total = total + (#segments * 12) - ((#segments - 1) * 6)

    if not best or total > best then
      best = total
    end
  end

  for first = 2, length - 2 do
    evaluate({
      query:sub(1, first),
      query:sub(first + 1),
    })
  end

  if length >= 6 then
    for first = 2, length - 4 do
      for second = first + 2, length - 2 do
        evaluate({
          query:sub(1, first),
          query:sub(first + 1, second),
          query:sub(second + 1),
        })
      end
    end
  end

  return best
end

local function prepare_candidate(text)
  return {
    compact = compact(text),
    words = tokenize_words(text),
  }
end

function M.score(query, text)
  local normalized_query = normalize(query)

  if vim.trim(normalized_query) == "" then
    return 0
  end

  local candidate = prepare_candidate(text)
  local tokens = {}

  for token in normalized_query:gmatch("%S+") do
    local normalized_token = compact(token)

    if normalized_token ~= "" then
      table.insert(tokens, normalized_token)
    end
  end

  if #tokens == 0 then
    return 0
  end

  local best = token_score(tokens, candidate)

  if #tokens == 1 then
    local merged = tokens[1]
    local segmented = segmented_score(merged, candidate)

    if segmented and (not best or segmented > best) then
      best = segmented
    end
  end

  return best
end

function M.filter(items, query, limit)
  if vim.trim(query or "") == "" then
    local results = {}
    local max_items = math.min(limit or #items, #items)

    for index = 1, max_items do
      table.insert(results, {
        item = items[index],
        score = 0,
      })
    end

    return results
  end

  local results = {}

  for _, item in ipairs(items) do
    local score = M.score(query, item.text)

    if score then
      table.insert(results, {
        item = item,
        score = score,
      })
    end
  end

  table.sort(results, function(left, right)
    if left.score == right.score then
      return left.item.recency < right.item.recency
    end

    return left.score > right.score
  end)

  if limit and #results > limit then
    for index = #results, limit + 1, -1 do
      results[index] = nil
    end
  end

  return results
end

return M
