local M = {
  available = false,
  load_error = nil,
}

local ok, ffi = pcall(require, "ffi")

if not ok then
  M.load_error = "ffi unavailable"
  return M
end

ffi.cdef([[
int penguin_stub_version(void);
typedef struct {
  int index;
  int score;
} penguin_result;
typedef struct {
  int count;
  const penguin_result *results;
} penguin_query_result;
typedef struct penguin_exact_matcher penguin_exact_matcher;
typedef struct {
  const char *text;
  int length;
} penguin_exact_matcher_text;
penguin_exact_matcher *penguin_exact_matcher_new(const penguin_exact_matcher_text *texts, int text_count, int text_bytes);
int penguin_exact_matcher_result_capacity(const penguin_exact_matcher *matcher);
const penguin_query_result *penguin_exact_matcher_find_exact(penguin_exact_matcher *matcher, const char *query, int query_length);
const penguin_query_result *penguin_exact_matcher_find_fuzzy(penguin_exact_matcher *matcher, const char *query, int query_length);
const char *penguin_exact_matcher_lower_text_at(const penguin_exact_matcher *matcher, int index);
int penguin_exact_matcher_text_length_at(const penguin_exact_matcher *matcher, int index);
void penguin_exact_matcher_free(penguin_exact_matcher *matcher);
]])

local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  local root = vim.fs.dirname(source)

  return vim.fs.dirname(vim.fs.dirname(root))
end

local function library_path()
  local ext = jit.os == "OSX" and "dylib" or "so"
  return vim.fs.joinpath(repo_root(), "build", ("penguin_filter.%s"):format(ext))
end

local load_ok, lib = pcall(ffi.load, library_path())

if not load_ok then
  M.load_error = lib
  return M
end

M.available = true
M.library = lib

function M.version()
  return lib.penguin_stub_version()
end

function M.probe()
  return M.version()
end

function M.find_exact(matcher, items, query, limit)
  local normalized_query = (query or ""):lower()
  local query_result
  local result_count
  local results = {}

  if not matcher or matcher.handle == nil or normalized_query == "" then
    return results
  end

  query_result = lib.penguin_exact_matcher_find_exact(
    matcher.handle,
    normalized_query,
    #normalized_query
  )

  if query_result == nil then
    return results
  end

  result_count = query_result.count

  if limit then
    result_count = math.min(result_count, limit)
  end

  for index = 0, result_count - 1 do
    local item = items[query_result.results[index].index + 1]

    if item then
      results[index + 1] = {
        item = item,
        score = query_result.results[index].score,
      }
    end
  end

  return results
end

function M.find_fuzzy(matcher, items, query, limit)
  -- Temporary boundary normalization: the current native fuzzy entrypoint
  -- matches against the matcher's compact corpus text, so Lua still lowercases
  -- and strips separators before handing one query token to C. Remove this
  -- once full query preprocessing/token handling moves into native code.
  local normalized_query = (query or ""):lower():gsub("[^%w]+", "")
  local query_result
  local result_count
  local results = {}

  if not matcher or matcher.handle == nil or normalized_query == "" then
    return results
  end

  query_result = lib.penguin_exact_matcher_find_fuzzy(
    matcher.handle,
    normalized_query,
    #normalized_query
  )

  if query_result == nil then
    return results
  end

  result_count = query_result.count

  if limit then
    result_count = math.min(result_count, limit)
  end

  for index = 0, result_count - 1 do
    local item = items[query_result.results[index].index + 1]

    if item then
      results[index + 1] = {
        item = item,
        score = query_result.results[index].score,
      }
    end
  end

  return results
end

-- Native corpus-ownership slice.
-- Build one long-lived matcher object from the candidate list, copy the
-- candidate bytes into native-owned storage once, and keep that matcher across
-- queries until Lua drops the handle.
function M.new_exact_matcher(items)
  local text_count = #items
  local text_bytes = 0
  local handle
  local texts

  if text_count == 0 then
    return {
      handle = nil,
      text_count = 0,
    }
  end

  texts = ffi.new("penguin_exact_matcher_text[?]", text_count)

  for index = 1, text_count do
    local text = items[index].text
    local length = #text

    text_bytes = text_bytes + length
    texts[index - 1].text = text
    texts[index - 1].length = length
  end

  handle = lib.penguin_exact_matcher_new(texts, text_count, text_bytes)

  if handle == nil then
    error("failed to build native exact matcher")
  end

  return {
    handle = ffi.gc(handle, lib.penguin_exact_matcher_free),
    result_capacity = lib.penguin_exact_matcher_result_capacity(handle),
    text_count = text_count,
    text_bytes = text_bytes,
  }
end

return M
