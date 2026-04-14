local M = {}

local group = vim.api.nvim_create_augroup("penguin.nvim.enter", { clear = true })
local enabled = false
local ignore_next_enter = false

local function open_penguin()
  require("penguin").open()
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

local function map_buffer_enter(buf)
  if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "qf" then
    return
  end

  if vim.b[buf].__penguin_enter_mapped then
    return
  end

  vim.b[buf].__penguin_enter_mapped = true

  vim.keymap.set("n", "<CR>", function()
    if ignore_next_enter then
      ignore_next_enter = false
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
end

return M
