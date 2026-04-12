local function repo_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fs.dirname(vim.fs.dirname(source))
end

local root = repo_root()

vim.opt.runtimepath:append(root)
vim.cmd.source(vim.fs.joinpath(root, "plugin", "penguin.lua"))

require("penguin").setup({
  native = {
    runtime_exact = true,
  },
})

vim.opt.termguicolors = true

vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    local seed_history = {
      "edit ~/.config/nvim/init.lua",
      "Lazy",
      "ls",
      "checkhealth",
      "vertical botright split",
      "bdelete",
      "write",
      "lua require('penguin').open()",
    }

    for _, command in ipairs(seed_history) do
      vim.fn.histadd(":", command)
    end

    vim.schedule(function()
      vim.notify(
        "penguin.nvim native fuzzy session ready. Run :Penguin",
        vim.log.levels.INFO
      )
    end)
  end,
})
