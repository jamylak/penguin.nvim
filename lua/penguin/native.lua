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
  return tonumber(lib.penguin_stub_version())
end

function M.probe()
  return M.version()
end

return M
