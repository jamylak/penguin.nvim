local M = {}

local highlight = require("penguin.highlight")
local namespace = vim.api.nvim_create_namespace("penguin.nvim")
local prompt_prefix = ": "
M.namespace = namespace

pcall(vim.api.nvim_set_hl, 0, "PenguinAccent", {
  fg = "#8ecae6",
  bold = true,
  nocombine = true,
})

pcall(vim.api.nvim_set_hl, 0, "PenguinMatch", {
  fg = "#1f2328",
  bg = "#ffd166",
  bold = true,
  nocombine = true,
})

local function set_window_options(window)
  local options = {
    cursorline = false,
    foldcolumn = "0",
    number = false,
    relativenumber = false,
    signcolumn = "no",
    spell = false,
    wrap = false,
  }

  for name, value in pairs(options) do
    vim.wo[window][name] = value
  end
end

local function dimensions(config)
  local width = math.min(config.ui.width, math.max(vim.o.columns - 4, 24))
  local results_height = math.min(config.ui.max_results, math.max(vim.o.lines - 8, 4))
  local total_height = results_height + 4
  local row = math.max(math.floor((vim.o.lines - total_height) / 2), 1)
  local col = math.max(math.floor((vim.o.columns - width) / 2), 0)

  return {
    col = col,
    prompt_row = row,
    results_height = results_height,
    results_row = row + 3,
    width = width,
  }
end

local function set_buffer_options(buffer, prompt)
  vim.bo[buffer].bufhidden = "wipe"
  vim.bo[buffer].buftype = prompt and "prompt" or "nofile"
  vim.bo[buffer].filetype = prompt and "penguin-prompt" or "penguin-results"
  vim.bo[buffer].modifiable = true
  vim.bo[buffer].swapfile = false
end

local function render_results(session)
  local lines = {}
  local line_meta = {}

  if #session.matches > 0 then
    for index, match in ipairs(session.matches) do
      local marker = index == session.selection and ">" or " "
      lines[index] = string.format("%s %s", marker, match.item.text)
      line_meta[index] = {
        text = match.item.text,
        text_col = 2,
        match_ranges = match.match_ranges,
      }
    end
  elseif #session.entries == 0 then
    lines = { "  no command history yet" }
  else
    lines = { "  no matches" }
  end

  vim.bo[session.results_buf].modifiable = true
  vim.api.nvim_buf_set_lines(session.results_buf, 0, -1, false, lines)
  vim.bo[session.results_buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(session.results_buf, namespace, 0, -1)

  if session.config.ui.match_highlights and #line_meta > 0 then
    for index, meta in ipairs(line_meta) do
      local ranges = meta.match_ranges or highlight.find_match_ranges(meta.text, session.query)

      for _, range in ipairs(ranges) do
        vim.api.nvim_buf_add_highlight(
          session.results_buf,
          namespace,
          "PenguinMatch",
          index - 1,
          meta.text_col + range[1],
          meta.text_col + range[2]
        )
      end
    end
  end

  if session.selection > 0 then
    vim.api.nvim_buf_add_highlight(
      session.results_buf,
      namespace,
      "Visual",
      session.selection - 1,
      0,
      -1
    )
  end
end

function M.open(session)
  session.origin_win = vim.api.nvim_get_current_win()

  local prompt_buf = vim.api.nvim_create_buf(false, true)
  local results_buf = vim.api.nvim_create_buf(false, true)
  local size = dimensions(session.config)

  session.prompt_buf = prompt_buf
  session.results_buf = results_buf

  set_buffer_options(prompt_buf, true)
  set_buffer_options(results_buf, false)

  vim.fn.prompt_setprompt(prompt_buf, prompt_prefix)
  vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { prompt_prefix })

  session.prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
    border = session.config.ui.border,
    col = size.col,
    focusable = true,
    height = 1,
    relative = "editor",
    row = size.prompt_row,
    style = "minimal",
    title = " 🐧 Penguin ",
    title_pos = "center",
    width = size.width,
  })

  session.results_win = vim.api.nvim_open_win(results_buf, false, {
    border = session.config.ui.border,
    col = size.col,
    focusable = false,
    height = size.results_height,
    relative = "editor",
    row = size.results_row,
    style = "minimal",
    title = " 🐧 History ",
    title_pos = "center",
    width = size.width,
  })

  set_window_options(session.prompt_win)
  set_window_options(session.results_win)
  vim.wo[session.prompt_win].winhighlight =
    "FloatBorder:PenguinAccent,FloatTitle:PenguinAccent"
  vim.wo[session.results_win].winhighlight =
    "FloatBorder:PenguinAccent,FloatTitle:PenguinAccent"

  vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
    buffer = prompt_buf,
    callback = function()
      if session.closed or not vim.api.nvim_buf_is_valid(prompt_buf) then
        return
      end

      local line = vim.api.nvim_buf_get_lines(prompt_buf, 0, 1, false)[1] or ""

      if line:sub(1, #prompt_prefix) == prompt_prefix then
        line = line:sub(#prompt_prefix + 1)
      end

      session:set_query(line)
    end,
  })

  local map_options = {
    buffer = prompt_buf,
    nowait = true,
    silent = true,
  }

  vim.keymap.set({ "i", "n" }, "<Esc>", function()
    session:close()
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<C-c>", function()
    session:close()
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<Down>", function()
    session:move_selection(1)
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<Up>", function()
    session:move_selection(-1)
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<C-j>", function()
    session:move_selection(1)
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<C-k>", function()
    session:move_selection(-1)
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<C-n>", function()
    session:move_selection(1)
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<C-p>", function()
    session:move_selection(-1)
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<C-w>", function()
    session:delete_word_backward()
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<CR>", function()
    session:confirm()
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<S-CR>", function()
    session:submit_query()
  end, map_options)

  vim.keymap.set({ "i", "n" }, "<C-e>", function()
    session:complete_selection()
  end, map_options)

  M.focus_prompt(session)
end

function M.render(session)
  if not session.results_buf or not vim.api.nvim_buf_is_valid(session.results_buf) then
    return
  end

  render_results(session)
end

function M.set_prompt_text(session, text)
  if not session.prompt_buf or not vim.api.nvim_buf_is_valid(session.prompt_buf) then
    return
  end

  vim.api.nvim_buf_set_lines(session.prompt_buf, 0, -1, false, { prompt_prefix .. (text or "") })
end

function M.focus_prompt(session)
  if not session.prompt_win or not vim.api.nvim_win_is_valid(session.prompt_win) then
    return
  end

  vim.api.nvim_set_current_win(session.prompt_win)
  vim.api.nvim_win_set_cursor(session.prompt_win, { 1, #prompt_prefix + #session.query })
  vim.cmd("startinsert")
end

function M.close(session)
  pcall(vim.cmd, "stopinsert")

  if session.origin_win and vim.api.nvim_win_is_valid(session.origin_win) then
    vim.api.nvim_set_current_win(session.origin_win)
  end

  for _, window in ipairs({ session.prompt_win, session.results_win }) do
    if window and vim.api.nvim_win_is_valid(window) then
      vim.api.nvim_win_close(window, true)
    end
  end
end

return M
