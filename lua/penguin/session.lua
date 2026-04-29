local completion = require("penguin.completion")
local history = require("penguin.history")
local matcher = require("penguin.matcher")
local native = require("penguin.native")
local ui = require("penguin.ui")

local Session = {}
Session.__index = Session
local empty_direct_submit_commands = {}

local function record_command_history(command)
	vim.fn.histadd(":", command)
end

---Return a 1-based line target when the typed command is only digits.
local function line_jump_target(command)
	if not command:match("^%d+$") then
		return nil
	end

	local target = tonumber(command)

	if not target then
		return nil
	end

	return math.max(target, 1)
end

---Move the current window cursor to the requested line, clamped to the buffer.
local function jump_to_line(target)
	local window = vim.api.nvim_get_current_win()
	local buffer = vim.api.nvim_win_get_buf(window)
	local last_line = vim.api.nvim_buf_line_count(buffer)
	local line = math.min(target, math.max(last_line, 1))

	vim.api.nvim_win_set_cursor(window, { line, 0 })
end

local function execute_command(text)
	local command = vim.trim(text or "")
	-- If the input happens to be a bare number like `33`, treat it as a line jump.
	local target = line_jump_target(command)

	if command == "" then
		return false
	end

	record_command_history(command)

	local ok, err

	if target then
		ok, err = pcall(jump_to_line, target)
	else
		ok, err = pcall(vim.cmd, command)
	end

	if not ok then
		vim.notify(("penguin.nvim: %s"):format(err), vim.log.levels.ERROR)
	end

	return ok
end

local function run_after_close(text)
	vim.schedule(function()
		execute_command(text)
	end)
end

local function build_native_matcher(entries)
	if not native.available then
		return nil
	end

	return native.new_exact_matcher(entries)
end

local function merge_matches(history_matches, completion_matches, limit)
	local merged = {}
	local positions = {}

	local function add(result)
		local key = result.item.text
		local index = positions[key]

		if not index then
			positions[key] = #merged + 1
			table.insert(merged, result)
			return
		end

		if matcher.compare_results(result, merged[index]) then
			merged[index] = result
		end
	end

	for _, result in ipairs(history_matches) do
		add(result)
	end

	for _, result in ipairs(completion_matches) do
		add(result)
	end

	return matcher.sort_results(merged, limit)
end

local function set_completion_items(session, items)
	session.completion_items = items or {}
	session.completion_native_matcher = build_native_matcher(session.completion_items)
end

function Session:new(config)
	local direct_submit_on_enter_commands = config.direct_submit_on_enter_commands

	-- Normalize this once per picker session so `confirm()` can stay on a plain
	-- table lookup instead of guarding the type on every Enter press.
	if type(direct_submit_on_enter_commands) ~= "table" then
		direct_submit_on_enter_commands = empty_direct_submit_commands
	end

	local session = setmetatable({
		closed = false,
		completion_cache = {},
		completion_generation = 0,
		completion_items = {},
		completion_native_matcher = nil,
		config = config,
		direct_numeric_line_jumps_on_enter = config.direct_numeric_line_jumps_on_enter,
		direct_submit_on_enter_commands = direct_submit_on_enter_commands,
		entries = history.collect(),
		matches = {},
		query = "",
		selection = 0,
	}, self)

	return session
end

function Session:update_matches()
	local limit = self.config.ui.max_results
	local history_matches = matcher.filter(self.entries, self.query, limit, {
		native_matcher = self.native_history_matcher,
	})
	local completion_matches = matcher.filter(self.completion_items, self.query, limit, {
		native_matcher = self.completion_native_matcher,
	})

	self.matches = merge_matches(history_matches, completion_matches, limit)

	if #self.matches == 0 then
		self.selection = 0
	else
		self.selection = math.min(math.max(self.selection, 1), #self.matches)
	end

	ui.render(self)
end

function Session:refresh()
	self.completion_generation = self.completion_generation + 1
	local plan = completion.plan(self.query, self.completion_cache)

	if plan.defer then
		local generation = self.completion_generation
		local debounce_ms = math.max((self.config.completion or {}).debounce_ms or 0, 0)

		-- Keep the prompt responsive for commands that opted into deferred
		-- argument completion. Live path-style commands stay synchronous because
		-- they never produce a deferred completion plan in the first place.
		set_completion_items(self, plan.immediate_items)
		self:update_matches()

		if not plan.needs_fetch then
			return
		end

		vim.defer_fn(function()
			-- Multiple timers may be queued while the user keeps typing. Only the
			-- newest generation is allowed to fetch/update, which prevents repeated
			-- work for stale deferred queries.
			if self.closed or generation ~= self.completion_generation then
				return
			end

			set_completion_items(self, completion.collect(self.query, self.completion_cache))

			if self.closed or generation ~= self.completion_generation then
				return
			end

			self:update_matches()
		end, debounce_ms)

		return
	end

	set_completion_items(self, completion.collect(self.query, self.completion_cache))
	self:update_matches()
end

function Session:apply_query(query)
	query = query or ""

	if query ~= self.query then
		self.query = query
		self.selection = 1
	end

	ui.set_prompt_text(self, query)
	self:refresh()
end

function Session:set_query(query)
	query = query or ""

	if query == self.query then
		return
	end

	self.query = query
	self.selection = 1
	self:refresh()
end

function Session:selected_text()
	local entry = self.matches[self.selection]

	if not entry then
		return nil
	end

	return entry.item.text
end

function Session:move_selection(delta)
	if #self.matches == 0 then
		return
	end

	local previous_selection = self.selection
	self.selection = ((self.selection - 1 + delta) % #self.matches) + 1
	-- Example:
	--   before: row 17 is `> set number`, row 18 is `  set relativenumber`
	--   after : row 17 is `  set number`, row 18 is `> set relativenumber`
	-- The match set stays the same; only the active marker moves by one row.
	-- Keep that path incremental so scrolling a long visible result window does
	-- not pay the cost of rebuilding every row and highlight on each move.
	ui.update_selection(self, previous_selection)
end

function Session:complete_selection()
	local text = self:selected_text()

	if not text then
		return
	end

	self:apply_query(text)
	ui.focus_prompt(self)
end

function Session:delete_word_backward()
	local text = self.query or ""
	local trimmed = text:gsub("%s+$", "")
	local next_query

	if trimmed == "" then
		next_query = ""
	else
		next_query = trimmed:gsub("%S+$", "")
	end

	next_query = next_query:gsub("%s+$", "")
	self:apply_query(next_query)
	ui.focus_prompt(self)
end

function Session:delete_after_cursor()
	local col = ui.get_prompt_cursor_col(self)
	local next_query = self.query:sub(1, col)
	self:apply_query(next_query)
	ui.focus_prompt(self)
end

function Session:delete_selected_history()
	local match = self.matches[self.selection]

	if not match or not match.item or match.item.source ~= "history" then
		return
	end

	local previous_selection = self.selection

	if not history.delete(match.item.text) then
		return
	end

	self.entries = history.collect()
	self.native_history_matcher = build_native_matcher(self.entries)
	self.selection = previous_selection
	self:refresh()
	ui.focus_prompt(self)
end

function Session:submit_query()
	local text = vim.trim(self.query or "")

	if text == "" then
		return
	end

	self:close()
	run_after_close(text)
end

function Session:confirm()
	local query = self.query or ""
	local direct_submit_on_enter_commands = self.direct_submit_on_enter_commands

	-- Fastest path for exact commands like `w` and `q`: do one hash lookup and
	-- execute the typed text directly, before looking at the selected row.
	if direct_submit_on_enter_commands[query] then
		self:close()
		run_after_close(query)
		return
	end

	-- Only trim after the raw lookup misses. That keeps the common exact-command
	-- case free of normalization while preserving tolerance for accidental
	-- surrounding whitespace.
	local command = vim.trim(query)

	-- If trimming changed the query into a configured direct command, keep the
	-- same bypass semantics and execute the cleaned command instead of whatever
	-- completion/history item is selected.
	if command ~= query and direct_submit_on_enter_commands[command] then
		self:close()
		run_after_close(command)
		return
	end

	-- Numeric queries are another intentional selection bypass: `30` should jump
	-- to line 30 even if the current match is a history entry like
	-- `30verbose set number`.
	if self.direct_numeric_line_jumps_on_enter and line_jump_target(command) ~= nil then
		self:close()
		run_after_close(command)
		return
	end

	-- Normal Enter behavior after the explicit bypasses: accept the active
	-- suggestion, or submit the typed query only when configured to do so and no
	-- suggestion is available.
	local text = self:selected_text()

	if not text then
		if self.config.submit_on_enter_if_no_matches then
			self:submit_query()
		end
		return
	end

	self:close()
	run_after_close(text)
end

function Session:close()
	if self.closed then
		return
	end

	self.closed = true
	ui.close(self)

	if self.on_close then
		self.on_close()
	end
end

local M = {}

function M.open(config, on_close)
	local session = Session:new(config)
	session.native_history_matcher = build_native_matcher(session.entries)
	session.on_close = on_close
	ui.open(session)
	session:refresh()
	return session
end

return M
