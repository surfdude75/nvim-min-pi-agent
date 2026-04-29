local M = {}

local defaults = {
  -- Keep the default broad so Pi can resolve the provider the user logged into.
  default_model = "openai-codex/gpt-5.5",
  default_thinking = "medium",
  pi_cmd = "pi",
  extra_args = {},
  keymap = nil,
  model_list_search = "gpt",
  strip_trailing_newline = true,
  prompt_window = {
    width = 0.72,
    height = 0.38,
    min_width = 56,
    min_height = 12,
  },
}

M.config = vim.deepcopy(defaults)

local thinking_levels = {
  off = true,
  minimal = true,
  low = true,
  medium = true,
  high = true,
  xhigh = true,
}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "min-pi-ai" })
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function trim_blank_lines(lines)
  while #lines > 0 and lines[1]:match("^%s*$") do
    table.remove(lines, 1)
  end

  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines, #lines)
  end

  return lines
end

local function executable_pi()
  if vim.fn.executable(M.config.pi_cmd) == 1 then
    return true
  end

  notify(
    "Pi was not found. Install it with `npm install -g @mariozechner/pi-coding-agent`.",
    vim.log.levels.ERROR
  )
  return false
end

local function get_changedtick(buf)
  if vim.api.nvim_buf_get_changedtick then
    return vim.api.nvim_buf_get_changedtick(buf)
  end

  return vim.b[buf].changedtick
end

local function charwise_end_col(buf, row, col1)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local col0 = math.max(col1 - 1, 0)

  if col0 >= #line then
    return #line
  end

  -- getpos() gives a byte column for the selected character. Neovim text
  -- APIs need an exclusive end byte, so include the whole character.
  local char_index = vim.fn.charidx(line, col0)
  local char = vim.fn.strcharpart(line, char_index, 1)

  return math.min(#line, col0 + #char)
end

local function get_selection()
  local buf = vim.api.nvim_get_current_buf()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  local mode = vim.fn.visualmode()

  if start_pos[2] == 0 or end_pos[2] == 0 then
    notify("Make a visual selection first.", vim.log.levels.WARN)
    return nil
  end

  if mode == "\022" then
    notify("Block selections are not supported yet.", vim.log.levels.WARN)
    return nil
  end

  local start_row = start_pos[2] - 1
  local start_col = start_pos[3] - 1
  local end_row = end_pos[2] - 1
  local end_col1 = end_pos[3]

  if start_row > end_row or (start_row == end_row and start_col > end_col1 - 1) then
    start_row, end_row = end_row, start_row
    start_col, end_col1 = end_col1 - 1, start_col + 1
  end

  local region = {
    buf = buf,
    mode = mode,
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    changedtick = get_changedtick(buf),
  }

  local lines
  if mode == "V" then
    region.start_col = 0
    lines = vim.api.nvim_buf_get_lines(buf, start_row, end_row + 1, false)
  else
    region.end_col = charwise_end_col(buf, end_row, end_col1)
    lines = vim.api.nvim_buf_get_text(
      buf,
      start_row,
      start_col,
      end_row,
      region.end_col,
      {}
    )
  end

  local text = table.concat(lines, "\n")
  if text == "" then
    notify("The selection is empty.", vim.log.levels.WARN)
    return nil
  end

  region.text = text
  region.filetype = vim.bo[buf].filetype
  region.filename = vim.api.nvim_buf_get_name(buf)

  return region
end

local function split_replacement(text)
  return vim.split(text, "\n", { plain = true })
end

local function replace_selection(region, replacement)
  if not vim.api.nvim_buf_is_valid(region.buf) then
    notify("The original buffer no longer exists.", vim.log.levels.ERROR)
    return
  end

  if get_changedtick(region.buf) ~= region.changedtick then
    notify(
      "The buffer changed while Pi was working. Replacement skipped.",
      vim.log.levels.WARN
    )
    return
  end

  local lines = split_replacement(replacement)

  if region.mode == "V" and replacement == "" then
    lines = {}
  end

  if region.mode == "V" then
    vim.api.nvim_buf_set_lines(
      region.buf,
      region.start_row,
      region.end_row + 1,
      false,
      lines
    )
  else
    vim.api.nvim_buf_set_text(
      region.buf,
      region.start_row,
      region.start_col,
      region.end_row,
      region.end_col,
      lines
    )
  end

  notify("Selection replaced by Pi.")
end

local function build_agent_prompt(region, request)
  local file = region.filename ~= "" and region.filename or "[No Name]"
  local filetype = region.filetype ~= "" and region.filetype or "text"
  local line_range = string.format("%d-%d", region.start_row + 1, region.end_row + 1)

  return table.concat({
    "You are rewriting one selected text fragment from Neovim.",
    "Return only the replacement text for the selection.",
    "Do not include explanations, Markdown fences, or surrounding file text.",
    "Keep the edit scoped to the selected text.",
    "",
    "User request:",
    request,
    "",
    "File: " .. file,
    "Filetype: " .. filetype,
    "Selected lines: " .. line_range,
    "",
    "<selection>",
    region.text,
    "</selection>",
  }, "\n")
end

local function clean_output(output)
  output = output:gsub("\r\n", "\n"):gsub("\r", "\n")

  if M.config.strip_trailing_newline and output:sub(-1) == "\n" then
    output = output:sub(1, -2)
  end

  return output
end

local function pi_command(model, thinking)
  local cmd = {
    M.config.pi_cmd,
    "--print",
    "--no-session",
    "--no-tools",
    "--no-context-files",
    "--no-extensions",
    "--no-skills",
    "--no-prompt-templates",
  }

  if model and model ~= "" then
    vim.list_extend(cmd, { "--model", model })
  end

  if thinking and thinking ~= "" then
    vim.list_extend(cmd, { "--thinking", thinking })
  end

  vim.list_extend(cmd, M.config.extra_args or {})
  return cmd
end

local function run_pi(region, request, model, thinking)
  if not executable_pi() then
    return
  end

  model = trim(model or "")
  thinking = trim(thinking or "")

  if thinking ~= "" and not thinking_levels[thinking] then
    notify("Unknown thinking level: " .. thinking, vim.log.levels.ERROR)
    return
  end

  local stdout = {}
  local stderr = {}
  local prompt = build_agent_prompt(region, request)
  local cmd = pi_command(model, thinking)

  notify("Sending selection to Pi...")

  local job = vim.fn.jobstart(cmd, {
    stdin = "pipe",
    stdout_buffered = true,
    stderr_buffered = true,
    env = { PI_SKIP_VERSION_CHECK = "1" },
    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(stderr, data)
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          local err = trim(table.concat(stderr, "\n"))
          notify("Pi failed" .. (err ~= "" and ": " .. err or "."), vim.log.levels.ERROR)
          return
        end

        local replacement = clean_output(table.concat(stdout, "\n"))
        if replacement == "" then
          local answer = vim.fn.confirm(
            "Pi returned empty text. Delete the selection?",
            "&Delete\n&Cancel",
            2
          )
          if answer ~= 1 then
            return
          end
        end

        replace_selection(region, replacement)
      end)
    end,
  })

  if job <= 0 then
    notify("Could not start Pi.", vim.log.levels.ERROR)
    return
  end

  vim.fn.chansend(job, prompt)
  vim.fn.chanclose(job, "stdin")
end

local function parse_prompt(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local body = {}
  local model = M.config.default_model
  local thinking = M.config.default_thinking
  local reading_body = false
  local saw_field = false

  for _, line in ipairs(lines) do
    if not line:match("^%s*#") then
      local key, value = line:match("^%s*([%w_-]+)%s*:%s*(.-)%s*$")

      if not reading_body and key then
        key = key:lower()
        if key == "model" then
          model = value
          saw_field = true
        elseif key == "thinking" then
          thinking = value
          saw_field = true
        else
          table.insert(body, line)
          reading_body = true
        end
      elseif not reading_body and saw_field and line:match("^%s*$") then
        reading_body = true
      elseif reading_body then
        table.insert(body, line)
      elseif not line:match("^%s*$") then
        table.insert(body, line)
        reading_body = true
      end
    end
  end

  body = trim_blank_lines(body)

  return {
    model = trim(model or ""),
    thinking = trim(thinking or ""),
    request = table.concat(body, "\n"),
  }
end

local function replace_field_line(buf, key, value)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local prefix = key .. ":"

  for index, line in ipairs(lines) do
    if line:lower():match("^%s*" .. key .. "%s*:") then
      vim.api.nvim_buf_set_lines(buf, index - 1, index, false, { prefix .. " " .. value })
      return
    end
  end

  vim.api.nvim_buf_set_lines(buf, 0, 0, false, { prefix .. " " .. value })
end

local function parse_models(output)
  local choices = {}

  for line in output:gmatch("[^\n]+") do
    local provider, model, _context, _max_out, thinking = line:match(
      "^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)"
    )
    if provider and model and (thinking == "yes" or thinking == "no") then
      table.insert(choices, provider .. "/" .. model)
    end
  end

  return choices
end

local function select_model(buf)
  if not executable_pi() then
    return
  end

  local output = {}
  local cmd = { M.config.pi_cmd, "--list-models" }
  if M.config.model_list_search and M.config.model_list_search ~= "" then
    table.insert(cmd, M.config.model_list_search)
  end

  local job = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    env = { PI_SKIP_VERSION_CHECK = "1" },
    on_stdout = function(_, data)
      if data then
        vim.list_extend(output, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(output, data)
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code ~= 0 then
          notify("Could not list Pi models.", vim.log.levels.ERROR)
          return
        end

        local choices = parse_models(table.concat(output, "\n"))
        if #choices == 0 then
          notify("No Pi models found.", vim.log.levels.WARN)
          return
        end

        vim.ui.select(choices, { prompt = "Pi model" }, function(choice)
          if choice and vim.api.nvim_buf_is_valid(buf) then
            replace_field_line(buf, "model", choice)
          end
        end)
      end)
    end,
  })

  if job <= 0 then
    notify("Could not start `pi --list-models`.", vim.log.levels.ERROR)
  end
end

local function window_size()
  local cfg = M.config.prompt_window
  local width = math.floor(vim.o.columns * cfg.width)
  local height = math.floor(vim.o.lines * cfg.height)

  width = math.max(cfg.min_width, width)
  height = math.max(cfg.min_height, height)
  width = math.min(width, vim.o.columns - 4)
  height = math.min(height, vim.o.lines - 4)

  return width, height
end

local function close_prompt(state)
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end

  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
end

local function submit_prompt(state)
  if state.submitted then
    return
  end

  local parsed = parse_prompt(state.buf)
  if parsed.request == "" then
    notify("Describe the change before submitting.", vim.log.levels.WARN)
    return
  end

  state.submitted = true
  close_prompt(state)
  run_pi(state.region, parsed.request, parsed.model, parsed.thinking)
end

local function open_prompt(region)
  local buf = vim.api.nvim_create_buf(false, true)
  local width, height = window_size()
  local row = math.floor((vim.o.lines - height) / 2) - 1
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(row, 0),
    col = math.max(col, 0),
    style = "minimal",
    border = "rounded",
    title = " Pi edit selection ",
    title_pos = "center",
  })

  local lines = {
    "# Describe how Pi should rewrite the selected text.",
    "# Lines beginning with # are ignored.",
    "# <C-s> submit | <C-l> choose model | normal <CR> submit | q cancel",
    "model: " .. M.config.default_model,
    "thinking: " .. M.config.default_thinking,
    "",
    "",
  }

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"

  local state = { buf = buf, win = win, region = region, submitted = false }
  local keymap_opts = { buffer = buf, silent = true, nowait = true }

  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    submit_prompt(state)
  end, keymap_opts)

  vim.keymap.set({ "n", "i" }, "<C-l>", function()
    select_model(buf)
  end, keymap_opts)

  vim.keymap.set("n", "<CR>", function()
    submit_prompt(state)
  end, keymap_opts)

  vim.keymap.set("n", "q", function()
    close_prompt(state)
  end, keymap_opts)

  vim.keymap.set("n", "<Esc>", function()
    close_prompt(state)
  end, keymap_opts)

  vim.api.nvim_win_set_cursor(win, { #lines, 0 })
  vim.cmd("startinsert")
end

function M.edit_selection()
  local region = get_selection()
  if region then
    open_prompt(region)
  end
end

function M.check()
  if not executable_pi() then
    return
  end

  local version = trim(vim.fn.system({ M.config.pi_cmd, "--version" }))
  if vim.v.shell_error ~= 0 then
    notify("Pi exists, but `pi --version` failed.", vim.log.levels.ERROR)
    return
  end

  notify("Found pi " .. version .. ". Run :MinPiAILogin if authentication is needed.")
end

function M.login()
  if not executable_pi() then
    return
  end

  vim.cmd("botright split")
  vim.cmd("resize 15")
  vim.fn.termopen({ M.config.pi_cmd })
  vim.cmd("startinsert")
  notify("In the Pi terminal, type /login and choose your provider.")
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

  vim.api.nvim_create_user_command("MinPiAIEditSelection", function()
    M.edit_selection()
  end, { desc = "Rewrite the visual selection with Pi", range = true, force = true })

  vim.api.nvim_create_user_command("MinPiAICheck", function()
    M.check()
  end, { desc = "Check that the Pi CLI is available", force = true })

  vim.api.nvim_create_user_command("MinPiAILogin", function()
    M.login()
  end, { desc = "Open Pi so you can run /login", force = true })

  if M.config.keymap then
    vim.keymap.set("v", M.config.keymap, function()
      M.edit_selection()
    end, { desc = "Pi edit selection" })
  end
end

return M
