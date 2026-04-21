local M = {
  available = false,
  build_attempted = false,
  library = nil,
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
  int match_span_count;
  int match_span_starts[24];
  int match_span_ends[24];
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
const penguin_query_result *penguin_exact_matcher_find_fuzzy(penguin_exact_matcher *matcher, const char *query, int query_length, int result_limit);
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

local function set_loaded(lib)
  M.available = true
  M.library = lib
  M.load_error = nil
end

local function reset_load_error(err)
  M.available = false
  M.library = nil
  M.load_error = err
end

local function try_load()
  local load_ok, lib = pcall(ffi.load, library_path())

  if not load_ok then
    reset_load_error(lib)
    return false
  end

  set_loaded(lib)
  return true
end

local function build_native_library()
  local result

  if M.build_attempted then
    return M.available
  end

  M.build_attempted = true

  if vim.fn.executable("make") ~= 1 then
    reset_load_error("native library missing and `make` is unavailable")
    return false
  end

  result = vim.system({ "make", "native" }, {
    cwd = repo_root(),
    text = true,
  }):wait()

  if result.code ~= 0 then
    local stderr = vim.trim(result.stderr or "")
    local stdout = vim.trim(result.stdout or "")
    local message = stderr ~= "" and stderr or stdout

    if message == "" then
      message = ("`make native` failed with exit code %d"):format(result.code)
    end

    reset_load_error(message)
    return false
  end

  return try_load()
end

function M.ensure_ready(opts)
  opts = opts or {}

  if M.available then
    return true
  end

  if try_load() then
    return true
  end

  if opts.auto_build then
    return build_native_library()
  end

  return false
end

M.ensure_ready()

function M.version()
  return M.library.penguin_stub_version()
end

function M.find_exact(matcher, items, query, limit)
  local normalized_query = (query or ""):lower()
  local query_result
  local result_count
  local results = {}

  if not matcher or matcher.handle == nil or normalized_query == "" then
    return results
  end

  query_result = M.library.penguin_exact_matcher_find_exact(
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
  local query_result
  local result_count
  local results = {}
  local raw_query = query or ""

  if not matcher or matcher.handle == nil or raw_query == "" then
    return results
  end

  query_result = M.library.penguin_exact_matcher_find_fuzzy(
    matcher.handle,
    raw_query,
    #raw_query,
    limit or 0
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
        match_ranges = (function()
          local ranges = {}
          local native_result = query_result.results[index]

          for span_index = 0, native_result.match_span_count - 1 do
            ranges[span_index + 1] = {
              native_result.match_span_starts[span_index],
              native_result.match_span_ends[span_index],
            }
          end

          return ranges
        end)(),
      }
    end
  end

  return results
end

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

  handle = M.library.penguin_exact_matcher_new(texts, text_count, text_bytes)

  if handle == nil then
    error("failed to build native exact matcher")
  end

  return {
    handle = ffi.gc(handle, M.library.penguin_exact_matcher_free),
    result_capacity = M.library.penguin_exact_matcher_result_capacity(handle),
    text_count = text_count,
    text_bytes = text_bytes,
  }
end

return M
