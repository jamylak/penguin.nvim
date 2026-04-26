local M = {}

local namespace = vim.api.nvim_create_namespace("penguin.nvim")
local selection_highlight_priority = 100
local match_highlight_priority = 110
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

local function add_match_highlight(buffer, row, start_col, end_col, line_length)
  line_length = math.max(line_length or 0, 0)
  start_col = math.max(start_col or 0, 0)
  end_col = math.max(end_col or 0, 0)

  if start_col > line_length then
    return
  end

  end_col = math.min(end_col, line_length)

  if end_col <= start_col then
    return
  end

  vim.api.nvim_buf_set_extmark(buffer, namespace, row, start_col, {
    end_col = end_col,
    end_row = row,
    hl_group = "PenguinMatch",
    priority = match_highlight_priority,
  })
end

local function add_selection_highlight(buffer, row, id)
  return vim.api.nvim_buf_set_extmark(buffer, namespace, row, 0, {
    id = id,
    line_hl_group = "Visual",
    priority = selection_highlight_priority,
    virt_text = {
      { ">", "Visual" },
    },
    virt_text_pos = "overlay",
  })
end

local function match_ranges_for_render(session, match)
  if session.config.native and session.config.native.benchmark_only_lua then
    local highlight_baseline = require("penguin.highlight")
    return highlight_baseline.find_match_ranges(match.item.text, session.query)
  end

  return match.match_ranges or {}
end

local function render_results(session)
  local lines = {}

  if #session.matches > 0 then
    for index, match in ipairs(session.matches) do
      lines[index] = string.format("  %s", match.item.text)
    end
  elseif #session.entries == 0 then
    lines = { "  no command history yet" }
  else
    lines = { "  no matches" }
  end

  vim.bo[session.results_buf].modifiable = true
  vim.api.nvim_buf_set_lines(session.results_buf, 0, -1, false, lines)
  vim.bo[session.results_buf].modifiable = false
  session.results_line_count = #lines

  vim.api.nvim_buf_clear_namespace(session.results_buf, namespace, 0, -1)

  if session.config.ui.match_highlights and #session.matches > 0 then
    for index, match in ipairs(session.matches) do
      local line = lines[index] or ""
      local ranges = match_ranges_for_render(session, match)

      for _, range in ipairs(ranges) do
        add_match_highlight(session.results_buf, index - 1, 2 + range[1], 2 + range[2], #line)
      end
    end
  end

  if session.selection > 0 then
    session.selection_extmark_id = add_selection_highlight(session.results_buf, session.selection - 1)
  end
end

---Visual model:
---
---  viewport before:
---    top=41 bottom=52
---    41  "  alpha"
---    42  "  beta"
---    ...
---    52  "> omega"
---
---  after one more <Down>:
---    top=42 bottom=53
---    42  "  beta"
---    ...
---    52  "  omega"
---    53  "> zeta"
---
---This keeps the active result row on-screen while avoiding scroll work when
---the selection is already inside the current viewport. The hot path uses
---cached window geometry and cached topline state so ordinary in-viewport
---moves still pay only the incremental row-rewrite cost.
local function ensure_selection_visible(session)
  local window = session.results_win
  local selection = session.selection
  local total_lines = session.results_line_count or 0
  local height = session.results_height or 0

  if not window then
    return
  end

  if selection <= 0 or total_lines <= 0 or height <= 0 then
    return
  end

  if height >= total_lines then
    session.results_topline = 1
    return
  end

  -- Treat the results window as a simple cached viewport:
  --   `top`    = first visible 1-based result row
  --   `bottom` = last visible 1-based result row
  --   `max_top` prevents scrolling past the final page of results
  local max_top = math.max(total_lines - height + 1, 1)
  local top = math.max(math.min(session.results_topline or 1, max_top), 1)
  local bottom = math.min(top + height - 1, total_lines)

  selection = math.min(selection, total_lines)

  if selection >= top and selection <= bottom then
    return
  end

  if selection < top then
    top = selection
  else
    top = math.min(selection - height + 1, max_top)
  end

  session.results_topline = top

  -- Keep the hidden cursor aligned with the active row so Neovim performs the
  -- actual window scroll for us only when the active row would otherwise leave
  -- the viewport.
  vim.api.nvim_win_set_cursor(window, { selection, 0 })
end

local function update_selection_only(session, previous_selection)
  local buffer = session.results_buf

  if not buffer or not vim.api.nvim_buf_is_valid(buffer) then
    return false
  end

  if #session.matches == 0 then
    if session.selection_extmark_id then
      vim.api.nvim_buf_del_extmark(buffer, namespace, session.selection_extmark_id)
    end
    session.selection_extmark_id = nil
    return true
  end

  -- The rendered lines stay byte-for-byte stable as `"  text"`. Selection
  -- movement only repositions a single extmark that draws both the line
  -- highlight and the overlaid `>` marker, so match-highlight extmarks never
  -- need to be rebuilt on ordinary cursor motion. That is dramatically faster
  -- than rewriting two buffer rows on every keypress because the hot path no
  -- longer mutates buffer text or replays row-level match highlights.
  if previous_selection == session.selection and session.selection_extmark_id then
    return true
  end

  if session.selection > 0 and session.selection <= #session.matches then
    session.selection_extmark_id = add_selection_highlight(
      buffer,
      session.selection - 1,
      session.selection_extmark_id
    )
  elseif session.selection_extmark_id then
    vim.api.nvim_buf_del_extmark(buffer, namespace, session.selection_extmark_id)
    session.selection_extmark_id = nil
  else
    session.selection_extmark_id = nil
  end

  return true
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
    title = " 🕘 History ",
    title_pos = "center",
    width = size.width,
  })

  set_window_options(session.prompt_win)
  set_window_options(session.results_win)
  session.results_height = size.results_height
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
    session:confirm()
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

  vim.keymap.set({ "i", "n" }, "<Tab>", function()
    session:complete_selection()
  end, map_options)

  M.focus_prompt(session)
end

function M.render(session)
  local results_win = session.results_win

  if not session.results_buf or not vim.api.nvim_buf_is_valid(session.results_buf) then
    return
  end

  render_results(session)

  -- The floating results window height is mostly stable, but a full rerender is
  -- the right time to refresh the cached value in case editor geometry changed.
  if results_win and vim.api.nvim_win_is_valid(results_win) then
    session.results_height = vim.api.nvim_win_get_height(results_win)
  end

  session.results_topline = 1
  ensure_selection_visible(session)
end

function M.update_selection(session, previous_selection)
  local results_win = session.results_win

  -- Fall back to the full render path if the buffer is missing/invalid. The
  -- incremental path is an optimisation, not a separate source of truth.
  if not update_selection_only(session, previous_selection) then
    M.render(session)
    return
  end

  if not results_win or not vim.api.nvim_win_is_valid(results_win) then
    return
  end

  ensure_selection_visible(session)
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
