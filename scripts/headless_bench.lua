local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(source))
end

local function hrtime_ms()
  return vim.uv.hrtime() / 1e6
end

local function bar(value, max_value, width)
  local filled

  if max_value <= 0 then
    return string.rep(".", width)
  end

  filled = math.max(1, math.floor((value / max_value) * width + 0.5))

  return string.rep("#", math.min(filled, width)) .. string.rep(".", math.max(0, width - filled))
end

local function normalize(text)
  return (text or ""):lower()
end

local function lua_exact_substring_score(query, text)
  local needle = normalize(query)
  local haystack = normalize(text)
  local start

  if needle == "" or haystack == "" or #needle > #haystack then
    return nil
  end

  start = haystack:find(needle, 1, true)

  if not start then
    return nil
  end

  local score = 300 - (start * 4) - (#haystack - #needle)

  if start == 1 then
    score = score + 30
  end

  return score
end

local function build_history(size)
  local entries = {}
  local templates = {
    function(index)
      return ("checkhealth mason %05d"):format(index)
    end,
    function(index)
      return ("vertical botright split +%d"):format((index % 80) + 1)
    end,
    function(index)
      return ("Git checkout feature/penguin-speed-%05d"):format(index)
    end,
    function(index)
      return ("write ++p /tmp/penguin-%05d.log"):format(index)
    end,
    function(index)
      return ("let g:penguin_selected = %d"):format((index % 97) + 1)
    end,
    function(index)
      return ("set number relativenumber winwidth=%d"):format((index % 40) + 40)
    end,
    function(index)
      return ("edit lua/penguin/session.lua | %d"):format((index % 200) + 1)
    end,
    function(index)
      return ("lua require('penguin').open() -- run %05d"):format(index)
    end,
    function(index)
      return ("30verbose set numberwidth=%d"):format((index % 9) + 1)
    end,
    function(index)
      return ("MasonInstall lua-language-server-%05d"):format(index)
    end,
    function(index)
      return ("Telescope find_files cwd=~/src/penguin.nvim/%05d"):format(index)
    end,
    function(index)
      return ("bdelete %d"):format((index % 300) + 1)
    end,
  }

  for index = 1, size do
    entries[index] = {
      text = templates[((index - 1) % #templates) + 1](index),
    }
  end

  return entries
end

local function run_lua_exact(entries, queries, iterations)
  local start_ms = hrtime_ms()
  local total_matches = 0
  local total_score = 0

  for _ = 1, iterations do
    for _, query in ipairs(queries) do
      for _, entry in ipairs(entries) do
        local score = lua_exact_substring_score(query, entry.text)

        if score then
          total_matches = total_matches + 1
          total_score = total_score + score
        end
      end
    end
  end

  return {
    total_ms = hrtime_ms() - start_ms,
    total_matches = total_matches,
    total_score = total_score,
  }
end

local function run_native_exact(native, entries, queries, iterations)
  local matcher = native.new_exact_matcher(entries)
  local start_ms = hrtime_ms()
  local total_matches = 0
  local total_score = 0

  for _ = 1, iterations do
    for _, query in ipairs(queries) do
      local normalized_query = normalize(query)
      local query_result = native.library.penguin_exact_matcher_find_exact(
        matcher.handle,
        normalized_query,
        #normalized_query
      )

      total_matches = total_matches + query_result.count

      for index = 0, query_result.count - 1 do
        total_score = total_score + query_result.results[index].score
      end
    end
  end

  return {
    total_ms = hrtime_ms() - start_ms,
    total_matches = total_matches,
    total_score = total_score,
  }
end

local function run_native_fuzzy_raw(native, entries, queries, iterations, limit)
  local fuzzy_matcher = native.new_exact_matcher(entries)
  local start_ms = hrtime_ms()
  local total_matches = 0
  local total_score = 0

  for _ = 1, iterations do
    for _, query in ipairs(queries) do
      local query_result = native.library.penguin_exact_matcher_find_fuzzy(
        fuzzy_matcher.handle,
        query,
        #query,
        limit or 0
      )

      total_matches = total_matches + query_result.count

      for index = 0, query_result.count - 1 do
        total_score = total_score + query_result.results[index].score
      end
    end
  end

  return {
    total_ms = hrtime_ms() - start_ms,
    total_matches = total_matches,
    total_score = total_score,
  }
end

local root = repo_root()

vim.opt.runtimepath:append(root)
vim.cmd.source(vim.fs.joinpath(root, "plugin", "penguin.lua"))

local highlight_baseline = require("penguin.highlight")
local matcher = require("penguin.matcher")
local native = require("penguin.native")

assert(native.available)

local function configure_matcher(benchmark_only_lua)
  matcher.configure({
    native = {
      benchmark_only_lua = benchmark_only_lua,
    },
  })
end

local function run_matcher_filter(entries, queries, iterations, benchmark_only_lua, limit)
  local native_matcher = benchmark_only_lua and nil or native.new_exact_matcher(entries)
  local start_ms = hrtime_ms()
  local total_matches = 0
  local total_score = 0

  configure_matcher(benchmark_only_lua)

  for _ = 1, iterations do
    for _, query in ipairs(queries) do
      local results = matcher.filter(entries, query, limit, {
        native_matcher = native_matcher,
      })

      total_matches = total_matches + #results

      for _, result in ipairs(results) do
        total_score = total_score + result.score
      end
    end
  end

  return {
    total_ms = hrtime_ms() - start_ms,
    total_matches = total_matches,
    total_score = total_score,
  }
end

local function run_highlight_runtime(entries, queries, iterations, use_lua_baseline)
  local native_matcher = native.new_exact_matcher(entries)
  local start_ms = hrtime_ms()
  local total_matches = 0
  local total_spans = 0
  local total_span_bytes = 0

  configure_matcher(false)

  for _ = 1, iterations do
    for _, query in ipairs(queries) do
      local results = matcher.filter(entries, query, 12, {
        native_matcher = native_matcher,
      })

      total_matches = total_matches + #results

      for _, result in ipairs(results) do
        local ranges = result.match_ranges or {}

        if use_lua_baseline then
          ranges = highlight_baseline.find_match_ranges(result.item.text, query)
        end

        total_spans = total_spans + #ranges

        for _, range in ipairs(ranges) do
          total_span_bytes = total_span_bytes + (range[2] - range[1])
        end
      end
    end
  end

  return {
    total_ms = hrtime_ms() - start_ms,
    total_matches = total_matches,
    total_spans = total_spans,
    total_span_bytes = total_span_bytes,
  }
end

local scenarios = {
  {
    name = "small",
    size = 100,
    iterations = 250,
    exact_queries = { "checkhealth", "split", "write", "number", "session.lua", "penguin" },
    fuzzy_queries = { "spl bot", "set nu", "peng sel", "nvim/lua", "gitco", "health mason", "zz", "30" },
  },
  {
    name = "medium",
    size = 1000,
    iterations = 75,
    exact_queries = { "checkhealth", "split", "write", "number", "session.lua", "penguin" },
    fuzzy_queries = { "spl bot", "set nu", "peng sel", "nvim/lua", "gitco", "health mason", "zz", "30" },
  },
  {
    name = "large",
    size = 10000,
    iterations = 10,
    exact_queries = { "checkhealth", "split", "write", "number", "session.lua", "penguin" },
    fuzzy_queries = { "spl bot", "set nu", "peng sel", "nvim/lua", "gitco", "health mason", "zz", "30" },
  },
}

local ui_limit = 12

for _, scenario in ipairs(scenarios) do
  local entries = build_history(scenario.size)
  local lua_result = run_lua_exact(entries, scenario.exact_queries, scenario.iterations)
  local native_result = run_native_exact(native, entries, scenario.exact_queries, scenario.iterations)
  local native_fuzzy_raw_all = run_native_fuzzy_raw(native, entries, scenario.fuzzy_queries, scenario.iterations, nil)
  local native_fuzzy_raw_topk = run_native_fuzzy_raw(native, entries, scenario.fuzzy_queries, scenario.iterations, ui_limit)
  local matcher_lua_all = run_matcher_filter(entries, scenario.fuzzy_queries, scenario.iterations, true, nil)
  local matcher_native_all = run_matcher_filter(entries, scenario.fuzzy_queries, scenario.iterations, false, nil)
  local matcher_lua_topk = run_matcher_filter(entries, scenario.fuzzy_queries, scenario.iterations, true, ui_limit)
  local matcher_native_topk = run_matcher_filter(entries, scenario.fuzzy_queries, scenario.iterations, false, ui_limit)
  local exact_query_count = #scenario.exact_queries * scenario.iterations
  local fuzzy_query_count = #scenario.fuzzy_queries * scenario.iterations
  local lua_per_query_ms = lua_result.total_ms / exact_query_count
  local native_per_query_ms = native_result.total_ms / exact_query_count
  local max_per_query_ms = math.max(lua_per_query_ms, native_per_query_ms)
  local raw_fuzzy_all_per_query_ms = native_fuzzy_raw_all.total_ms / fuzzy_query_count
  local raw_fuzzy_topk_per_query_ms = native_fuzzy_raw_topk.total_ms / fuzzy_query_count
  local matcher_lua_all_per_query_ms = matcher_lua_all.total_ms / fuzzy_query_count
  local matcher_native_all_per_query_ms = matcher_native_all.total_ms / fuzzy_query_count
  local matcher_lua_topk_per_query_ms = matcher_lua_topk.total_ms / fuzzy_query_count
  local matcher_native_topk_per_query_ms = matcher_native_topk.total_ms / fuzzy_query_count

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=lua_exact",
      ("total_ms=%.3f"):format(lua_result.total_ms),
      ("per_query_ms=%.6f"):format(lua_per_query_ms),
      "matches=" .. lua_result.total_matches,
      "score_sum=" .. lua_result.total_score,
    }, " ")
  )

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=native_exact",
      ("total_ms=%.3f"):format(native_result.total_ms),
      ("per_query_ms=%.6f"):format(native_per_query_ms),
      "matches=" .. native_result.total_matches,
      "score_sum=" .. native_result.total_score,
    }, " ")
  )

  print(
    table.concat({
      "chart",
      scenario.name,
      ("lua_exact    |%s| %.6f ms/query"):format(bar(lua_per_query_ms, max_per_query_ms, 32), lua_per_query_ms),
      ("native_exact |%s| %.6f ms/query"):format(bar(native_per_query_ms, max_per_query_ms, 32), native_per_query_ms),
      ("speedup=%.2fx"):format(lua_per_query_ms / native_per_query_ms),
    }, "\n")
  )

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=native_fuzzy_raw_all",
      ("total_ms=%.3f"):format(native_fuzzy_raw_all.total_ms),
      ("per_query_ms=%.6f"):format(raw_fuzzy_all_per_query_ms),
      "matches=" .. native_fuzzy_raw_all.total_matches,
      "score_sum=" .. native_fuzzy_raw_all.total_score,
    }, " ")
  )

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=native_fuzzy_raw_topk12",
      ("total_ms=%.3f"):format(native_fuzzy_raw_topk.total_ms),
      ("per_query_ms=%.6f"):format(raw_fuzzy_topk_per_query_ms),
      "matches=" .. native_fuzzy_raw_topk.total_matches,
      "score_sum=" .. native_fuzzy_raw_topk.total_score,
    }, " ")
  )

  print(
    table.concat({
      "chart",
      scenario.name .. "_native_fuzzy",
      ("native_raw_all  |%s| %.6f ms/query"):format(
        bar(raw_fuzzy_all_per_query_ms, math.max(raw_fuzzy_all_per_query_ms, raw_fuzzy_topk_per_query_ms), 32),
        raw_fuzzy_all_per_query_ms
      ),
      ("native_raw_topk|%s| %.6f ms/query"):format(
        bar(raw_fuzzy_topk_per_query_ms, math.max(raw_fuzzy_all_per_query_ms, raw_fuzzy_topk_per_query_ms), 32),
        raw_fuzzy_topk_per_query_ms
      ),
      ("speedup=%.2fx"):format(raw_fuzzy_all_per_query_ms / raw_fuzzy_topk_per_query_ms),
    }, "\n")
  )

  local native_highlight_result = run_highlight_runtime(
    entries,
    scenario.fuzzy_queries,
    scenario.iterations,
    false
  )
  local lua_baseline_highlight_result = run_highlight_runtime(
    entries,
    scenario.fuzzy_queries,
    scenario.iterations,
    true
  )
  local native_highlight_per_query_ms = native_highlight_result.total_ms / fuzzy_query_count
  local lua_baseline_highlight_per_query_ms =
    lua_baseline_highlight_result.total_ms / fuzzy_query_count
  local highlight_max_per_query_ms =
    math.max(native_highlight_per_query_ms, lua_baseline_highlight_per_query_ms)

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=matcher_lua_all",
      ("total_ms=%.3f"):format(matcher_lua_all.total_ms),
      ("per_query_ms=%.6f"):format(matcher_lua_all_per_query_ms),
      "matches=" .. matcher_lua_all.total_matches,
      "score_sum=" .. matcher_lua_all.total_score,
    }, " ")
  )

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=matcher_native_all",
      ("total_ms=%.3f"):format(matcher_native_all.total_ms),
      ("per_query_ms=%.6f"):format(matcher_native_all_per_query_ms),
      "matches=" .. matcher_native_all.total_matches,
      "score_sum=" .. matcher_native_all.total_score,
    }, " ")
  )

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=matcher_lua_topk12",
      ("total_ms=%.3f"):format(matcher_lua_topk.total_ms),
      ("per_query_ms=%.6f"):format(matcher_lua_topk_per_query_ms),
      "matches=" .. matcher_lua_topk.total_matches,
      "score_sum=" .. matcher_lua_topk.total_score,
    }, " ")
  )

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=matcher_native_topk12",
      ("total_ms=%.3f"):format(matcher_native_topk.total_ms),
      ("per_query_ms=%.6f"):format(matcher_native_topk_per_query_ms),
      "matches=" .. matcher_native_topk.total_matches,
      "score_sum=" .. matcher_native_topk.total_score,
    }, " ")
  )

  print(
    table.concat({
      "chart",
      scenario.name .. "_matcher_all",
      ("matcher_lua_all |%s| %.6f ms/query"):format(
        bar(matcher_lua_all_per_query_ms, math.max(matcher_lua_all_per_query_ms, matcher_native_all_per_query_ms), 32),
        matcher_lua_all_per_query_ms
      ),
      ("matcher_native  |%s| %.6f ms/query"):format(
        bar(matcher_native_all_per_query_ms, math.max(matcher_lua_all_per_query_ms, matcher_native_all_per_query_ms), 32),
        matcher_native_all_per_query_ms
      ),
      ("speedup=%.2fx"):format(matcher_lua_all_per_query_ms / matcher_native_all_per_query_ms),
    }, "\n")
  )

  print(
    table.concat({
      "chart",
      scenario.name .. "_matcher_topk",
      ("matcher_lua_topk |%s| %.6f ms/query"):format(
        bar(matcher_lua_topk_per_query_ms, math.max(matcher_lua_topk_per_query_ms, matcher_native_topk_per_query_ms), 32),
        matcher_lua_topk_per_query_ms
      ),
      ("matcher_native  |%s| %.6f ms/query"):format(
        bar(matcher_native_topk_per_query_ms, math.max(matcher_lua_topk_per_query_ms, matcher_native_topk_per_query_ms), 32),
        matcher_native_topk_per_query_ms
      ),
      ("speedup=%.2fx"):format(matcher_lua_topk_per_query_ms / matcher_native_topk_per_query_ms),
    }, "\n")
  )

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=native_highlights_runtime",
      ("total_ms=%.3f"):format(native_highlight_result.total_ms),
      ("per_query_ms=%.6f"):format(native_highlight_per_query_ms),
      "matches=" .. native_highlight_result.total_matches,
      "spans=" .. native_highlight_result.total_spans,
      "span_bytes=" .. native_highlight_result.total_span_bytes,
    }, " ")
  )

  print(
    table.concat({
      "scenario=" .. scenario.name,
      "size=" .. scenario.size,
      "backend=lua_highlights_baseline_runtime",
      ("total_ms=%.3f"):format(lua_baseline_highlight_result.total_ms),
      ("per_query_ms=%.6f"):format(lua_baseline_highlight_per_query_ms),
      "matches=" .. lua_baseline_highlight_result.total_matches,
      "spans=" .. lua_baseline_highlight_result.total_spans,
      "span_bytes=" .. lua_baseline_highlight_result.total_span_bytes,
    }, " ")
  )

  print(
    table.concat({
      "chart",
      scenario.name .. "_highlights",
      ("native_highlights     |%s| %.6f ms/query"):format(
        bar(native_highlight_per_query_ms, highlight_max_per_query_ms, 32),
        native_highlight_per_query_ms
      ),
      ("lua_highlights_baseline|%s| %.6f ms/query"):format(
        bar(lua_baseline_highlight_per_query_ms, highlight_max_per_query_ms, 32),
        lua_baseline_highlight_per_query_ms
      ),
      ("speedup=%.2fx"):format(lua_baseline_highlight_per_query_ms / native_highlight_per_query_ms),
    }, "\n")
  )
end

vim.cmd("qa!")
