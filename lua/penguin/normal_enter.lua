local M = {}

local group = vim.api.nvim_create_augroup("penguin.nvim.enter", { clear = true })
local enabled = false
local ignore_next_enter = false
local excluded_filetypes = {
  help = true,
  netrw = true,
  qf = true,
}

local function open_penguin()
  require("penguin").open()
end

local function should_map_buffer(buf)
  local filetype = vim.bo[buf].filetype
  return vim.bo[buf].buftype == "" and not excluded_filetypes[filetype]
end

local function unmap_buffer_enter(buf)
  local maps = vim.api.nvim_buf_get_keymap(buf, "n")

  for _, map in ipairs(maps) do
    if map.lhs == "<CR>" and map.desc == "Open penguin.nvim on bare Enter" then
      vim.keymap.del("n", "<CR>", { buffer = buf })
      vim.b[buf].__penguin_enter_mapped = nil
      return
    end
  end
end

local consume_enter_action

local function map_buffer_enter(buf)
  if not should_map_buffer(buf) then
    unmap_buffer_enter(buf)
    return
  end

  if vim.b[buf].__penguin_enter_mapped then
    return
  end

  vim.b[buf].__penguin_enter_mapped = true

  vim.keymap.set("n", "<CR>", function()
    local action = consume_enter_action(buf)

    if action == "ignore" then
      return
    end

    if action == "fallback" then
      vim.api.nvim_feedkeys(vim.keycode("<CR>"), "n", false)
      return
    end

    open_penguin()
  end, {
    buffer = buf,
    desc = "Open penguin.nvim on bare Enter",
    noremap = true,
    silent = true,
  })
end

consume_enter_action = function(buf)
  if ignore_next_enter then
    ignore_next_enter = false
    return "ignore"
  end

  if vim.fn.getcmdwintype() ~= "" or not should_map_buffer(buf) then
    return "fallback"
  end

  return "open"
end

function M.handle_expr()
  local action = consume_enter_action(vim.api.nvim_get_current_buf())

  if action == "fallback" then
    return "<CR>"
  end

  if action == "open" then
    vim.schedule(open_penguin)
  end

  return ""
end

function M.enable()
  if enabled then
    return
  end

  enabled = true

  vim.api.nvim_create_autocmd("TermClose", {
    group = group,
    callback = function()
      ignore_next_enter = true
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = { "help", "netrw", "qf" },
    callback = function(args)
      unmap_buffer_enter(args.buf)
    end,
  })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      if vim.fn.getcmdwintype() ~= "" then
        return
      end

      map_buffer_enter(args.buf)
    end,
  })

  map_buffer_enter(vim.api.nvim_get_current_buf())
end

return M
