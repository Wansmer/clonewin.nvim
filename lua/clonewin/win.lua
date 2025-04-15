local cfg = require("clonewin.config")
local GROUP_PREFIX = "__virtwin__"

---"observed" - original window with scratch buffer
---"clone" - float front window with original buffer
---@alias WinType "observed"|"clone"

---@class WinData
---@field win integer
---@field buf integer

---@class CloneWin
---@field origin_win integer Original plain neovim window for cloning
---@field origin_buf integer Original buffer with window content
---@field wins table<WinType, WinData>
---@field group integer Augroup for current instance
---@field opts CloneWinCfg
---@field _mapping boolean For avoid WinEnter when mappings is fire
local CloneWin = {}
CloneWin.__index = CloneWin

---@param win integer
---@return boolean
local function safe_win_close(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local ok, err = pcall(vim.api.nvim_win_close, win, true)
  if not ok and err then
    vim.notify(err, vim.log.levels.ERROR)
  end
  return ok
end

---Call fn with temporary current win and buf
---@param win integer
---@param buf integer
---@param fn fun()
local function call_for_win_buf(win, buf, fn)
  vim.api.nvim_win_call(win, function()
    vim.api.nvim_buf_call(buf, fn)
  end)
end

---Create new virtwin instance
---@param win integer?
---@param buf integer?
---@param opts CloneWinCfg?
---@return CloneWin?, string?
function CloneWin.new(win, buf, opts)
  win = win or vim.api.nvim_get_current_win()
  buf = buf or vim.api.nvim_get_current_buf()

  local w = setmetatable({
    origin_win = win,
    origin_buf = buf,
    wins = {},
    group = vim.api.nvim_create_augroup(("%s%s"):format(GROUP_PREFIX, win), {}),
    opts = vim.tbl_deep_extend("force", cfg.config, opts or {}),
    _mapping = false,
  }, CloneWin)

  local ok, err = pcall(function()
    w:_setup_clone_win()
    w:_setup_observed_win()
    w:_set_autocmds()
    w:_clone_set_keymaps()
  end)

  if not ok then
    vim.notify(
      ("Failed to create CloneWin: %s"):format(err),
      vim.log.levels.ERROR
    )
    return nil, err
  end

  return w, nil
end

function CloneWin:_setup_observed_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(self.origin_win, buf)
  local count = math.min(
    vim.api.nvim_buf_line_count(self.origin_buf),
    vim.api.nvim_win_get_height(self.origin_win)
  )
  local lines = vim.split((" \n"):rep(count), "\n")

  self.wins.observed = { win = self.origin_win, buf = buf }

  call_for_win_buf(self.origin_win, buf, function()
    for key, value in pairs(self.opts.origin_win_opts) do
      vim.opt_local[key] = value
    end
  end)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

function CloneWin:_setup_clone_win()
  local info = vim.fn.getwininfo(self.origin_win)[1]
  local win = vim.api.nvim_open_win(self.origin_buf, true, {
    relative = "win",
    win = self.origin_win,
    row = 0,
    col = 0,
    focusable = false,
    noautocmd = true,
    width = self:_calc_clone_width(info),
    height = info.height,
  })

  self.wins.clone = { win = win, buf = self.origin_buf }

  call_for_win_buf(win, self.origin_buf, function()
    for key, value in pairs(self.opts.clone_win_opts) do
      vim.opt_local[key] = value
    end
  end)

  return win
end

---Max width of the clone window is filetype's textwidth + text offset (statuscolumn width)
---@param info vim.fn.getwininfo.ret.item
---@return integer
function CloneWin:_calc_clone_width(info)
  local tw = self.opts.max_width
  if not tw then
    local ok, res = pcall(
      vim.filetype.get_option,
      vim.bo[self.origin_buf].filetype,
      "textwidth"
    )
    tw = ok and tonumber(res) or 100
  end

  local desired_ww = tw + info.textoff
  return math.min(desired_ww, info.width)
end

---Adjust clone window size if the original window resized
function CloneWin:_adjust_size()
  local info = vim.fn.getwininfo(self.origin_win)[1]
  vim.api.nvim_win_set_config(self.wins.clone.win, {
    width = self:_calc_clone_width(info),
    height = info.height,
  })
end

---Close clone window
---@param restore_origin boolean? If true, set origin buffer to origin window
---@return boolean
function CloneWin:close_clone(restore_origin)
  if restore_origin then
    vim.api.nvim_win_set_buf(self.origin_win, self.wins.clone.buf)
  end

  return safe_win_close(self.wins.clone.win)
end

---Close original window
---@return boolean
function CloneWin:close_origin()
  vim.api.nvim_buf_delete(self.wins.observed.buf, { force = true })
  return safe_win_close(self.origin_win)
end

function CloneWin:_set_autocmds()
  local on_event = vim.api.nvim_create_autocmd

  -- Close all windows if any of them is closed
  on_event("WinClosed", {
    group = self.group,
    pattern = {
      tostring(self.wins.observed.win),
      tostring(self.wins.clone.win),
    },
    callback = function()
      self:close_clone()
      self:close_origin()
      self:_clear_autocmds()
    end,
  })

  -- Adjust window size if the original window resized
  on_event("WinResized", {
    group = self.group,
    callback = function()
      if vim.tbl_contains(vim.v.event.windows, self.origin_win) then
        vim.schedule(function()
          if not vim.api.nvim_win_is_valid(self.wins.clone.win) then
            return
          end

          self:_adjust_size()
        end)
      end
    end,
  })

  -- Set clone window current, if the cursor jumps to the original window
  on_event("WinEnter", {
    group = self.group,
    callback = function()
      if vim.api.nvim_get_current_win() == self.wins.observed.win then
        if self:_is_mapping() then
          return
        end
        vim.api.nvim_set_current_win(self.wins.clone.win)
      end
    end,
  })

  -- Close clone window and redirect other buffer to original window if it trying to take over clone window
  on_event("BufWinEnter", {
    group = self.group,
    callback = function(e)
      local cwin = vim.api.nvim_get_current_win()
      if cwin == self.wins.clone.win then
        -- If reopen same buffer, do nothing
        if e.buf == self.origin_buf then
          return
        end

        vim.api.nvim_win_set_buf(self.wins.observed.win, e.buf)
        vim.api.nvim_buf_delete(self.wins.observed.buf, { force = true })
        self:close_clone()
        self:_clear_autocmds()
      end
    end,
  })
end

function CloneWin:_clear_autocmds()
  local ok, err = pcall(vim.api.nvim_del_augroup_by_id, self.group)
  if not ok then
    vim.notify(
      string.format("Failed to delete CloneWin augroup: %s", err),
      vim.log.levels.WARN
    )
  end
  return ok
end

function CloneWin:_is_mapping()
  return self._mapping
end

function CloneWin:_mapping_start()
  self._mapping = true
end

function CloneWin:_mapping_end()
  self._mapping = false
end

---Execute mapping from origin window from same position as in clone window
---@param mapping string|fun()
function CloneWin:_exec_origin_map(mapping)
  return function()
    self:_mapping_start()
    local ok, err = pcall(function()
      local win_row = vim.fn.winline()
      vim.api.nvim_set_current_win(self.origin_win)

      -- Save cursor position to imitate cursor movement behaviour
      pcall(vim.api.nvim_win_set_cursor, self.origin_win, { win_row, 0 })

      if type(mapping) == "function" then
        mapping()
      else
        vim.api.nvim_feedkeys(vim.keycode(mapping), "mix", true)
      end
    end)

    if not ok then
      vim.notify(
        ("Failed to execute mapping: %s"):format(err),
        vim.log.levels.WARN
      )
    end

    self:_mapping_end()
  end
end

function CloneWin:_clone_set_keymaps()
  local map = vim.keymap.set

  for lhs, rhs in pairs(self.opts.mappings) do
    map("n", lhs, self:_exec_origin_map(rhs), { buffer = self.origin_buf })
  end
end

return CloneWin
