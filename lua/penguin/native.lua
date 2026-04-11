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
typedef struct penguin_exact_matcher penguin_exact_matcher;
penguin_exact_matcher *penguin_exact_matcher_new(const char *const *texts, const int *text_lengths, int text_count, int text_bytes);
int penguin_exact_matcher_result_capacity(const penguin_exact_matcher *matcher);
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

-- First native-state slice only.
-- Create one long-lived native matcher object from the real candidate list,
-- keep it across queries, and let C free it later when Lua drops the handle.
-- The native side still only receives aggregate sizing numbers for now.
function M.new_exact_matcher(items)
  local text_count = #items
  local text_bytes = 0
  local handle
  local texts
  local text_lengths

  if text_count == 0 then
    return {
      handle = nil,
      text_count = 0,
    }
  end

  texts = ffi.new("const char *[?]", text_count)
  text_lengths = ffi.new("int[?]", text_count)

  for index = 1, text_count do
    local text = items[index].text
    local length = #text

    text_bytes = text_bytes + length
    texts[index - 1] = text
    text_lengths[index - 1] = length
  end

  handle = lib.penguin_exact_matcher_new(texts, text_lengths, text_count, text_bytes)

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
