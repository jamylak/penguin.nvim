local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(source))
end

local root = repo_root()

vim.opt.runtimepath:append(root)
vim.cmd.source(vim.fs.joinpath(root, "plugin", "penguin.lua"))

require("penguin").setup({
  native = {
    enabled = true,
  },
  ui = {
    -- `make run` is for manual large-list UX checks, so show the bigger window
    -- there even though the plugin default remains smaller.
    max_results = 100,
  },
})

vim.opt.termguicolors = true

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local templates = {
      function(index)
        return ("edit ~/.config/nvim/init.lua -- run %03d"):format(index)
      end,
      function(index)
        return ("Lazy sync %03d"):format(index)
      end,
      function(index)
        return ("checkhealth provider%03d"):format(index)
      end,
      function(index)
        return ("vertical botright split +%d"):format((index % 80) + 1)
      end,
      function(index)
        return ("bdelete %d"):format((index % 120) + 1)
      end,
      function(index)
        return ("write ++p /tmp/penguin-run-%03d.log"):format(index)
      end,
      function(index)
        return ("lua require('penguin').open() -- run %03d"):format(index)
      end,
      function(index)
        return ("set number relativenumber winwidth=%d"):format((index % 40) + 40)
      end,
    }

    for index = 1, 140 do
      vim.fn.histadd(":", templates[((index - 1) % #templates) + 1](index))
    end

    vim.schedule(function()
      vim.notify(
        "penguin.nvim native fuzzy session ready with a 100-row manual test window. Run :Penguin",
        vim.log.levels.INFO
      )
    end)
  end,
})
