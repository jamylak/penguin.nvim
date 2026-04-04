if vim.g.loaded_penguin then
  return
end

vim.g.loaded_penguin = 1

vim.api.nvim_create_user_command("Penguin", function()
  require("penguin").open()
end, {
  desc = "Open penguin.nvim",
})
