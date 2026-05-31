local cfg = require("clonewin.config")
local log = require("clonewin.logger")

local M = {}
local H = {} -- Helpers

---Setup clonewin.nvim
---@param opts CloneWinCfg?
function M.setup(opts)
  cfg.merge_config(opts)
  log.trace("Setup clonewin.nvim ==================================")
  M.on_open_filetype()
end

function M.on_open_filetype()
  local event = vim.api.nvim_create_autocmd

  event({
    -- "BufWinEnter",
    "BufEnter",
  }, {
    callback = function(e)
      if not vim.list_contains(cfg.config.ft, vim.bo[e.buf].ft) then
        return
      end

      local plain_win = vim.api.nvim_get_current_win()
      local plain_win_config = vim.api.nvim_win_get_config(plain_win)

      -- Ignore float windows
      if plain_win_config.relative ~= "" then
        return
      end

      vim.schedule(function()
        -- Order of setup windows matters: clone should be called first, as it uses the original
        -- window info inside
        local clone_win = M.setup_clone_win(plain_win, e.buf)
        local scratch_buf = M.setup_plain_win(plain_win, e.buf)

        local group = vim.api.nvim_create_augroup(("%s%s"):format("__clonewin__", tostring({})), {})
        local is_mapping = false

        local function execute_map(mapping)
          return function()
            is_mapping = true


            local ok, err = pcall(function()
              local win_row = vim.fn.winline()
              vim.api.nvim_set_current_win(plain_win)

              -- Save cursor position to imitate cursor movement behaviour
              pcall(vim.api.nvim_win_set_cursor, plain_win, { win_row, 0 })

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

            is_mapping = false
          end
        end

        H.set_keymaps(execute_map, e.buf)

        event("WinEnter", {
          group = group,
          callback = function(ev)
            local cw = vim.api.nvim_get_current_win()
            if cw ~= plain_win or is_mapping then
              return
            end

            pcall(vim.api.nvim_set_current_win, clone_win)
          end,
        })

        event("BufWinEnter", {
          group = group,
          callback = function(ev)
            -- If it not a clone window, do nothing
            local cw = vim.api.nvim_get_current_win()
            if cw ~= clone_win then
              return
            end

            -- If new buffer is the same as the original buffer, do nothing
            if ev.buf == e.buf then
              return
            end

            -- If new buffer is not in ft list or it in ft, but associated with another buffer, the
            -- clone window must be closed
            vim.schedule(function()
              vim.api.nvim_win_set_buf(plain_win, ev.buf)
              vim.api.nvim_buf_delete(scratch_buf, { force = true })
            end)
            vim.api.nvim_clear_autocmds({ group = group })
            H.safe_win_close(clone_win, false)
          end
        })

        event("WinResized", {
          group = group,
          -- TODO: debounce it
          callback = function(ev)
            if not vim.tbl_contains(vim.v.event.windows, plain_win) then
              return
            end

            local info = vim.fn.getwininfo(plain_win)[1]
            vim.api.nvim_win_set_config(clone_win, {
              width = H.calculate_clone_win_width(info, ev.buf),
              height = info.height,
            })
          end,
        })

        event("WinClosed", {
          group = group,
          pattern = {
            tostring(clone_win)
          },
          callback = function(ev)
            H.safe_win_close(plain_win, false)
            vim.api.nvim_clear_autocmds({ group = group })
          end,
        })
      end)
    end,
  })
end

function M.setup_clone_win(plain_win, buf)
  local plain_win_info = vim.fn.getwininfo(plain_win)[1]

  local clone_win = vim.api.nvim_open_win(buf, true, {
    relative = "win",
    win = plain_win,
    row = 0,
    col = 0,
    focusable = true,
    width = H.calculate_clone_win_width(plain_win_info, buf),
    height = plain_win_info.height,
  })

  H.call_for_win_buf(clone_win, buf, function()
    for key, value in pairs(cfg.config.clone_win_opts) do
      vim.opt_local[key] = value
    end
  end)


  return clone_win
end

function M.setup_plain_win(plain_win, buf)
  local scratch_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(plain_win, scratch_buf)
  local count = math.min(
    vim.api.nvim_buf_line_count(buf),
    vim.api.nvim_win_get_height(plain_win)
  )
  local lines = vim.split((" \n"):rep(count), "\n")
  H.call_for_win_buf(plain_win, scratch_buf, function()
    for key, value in pairs(cfg.config.origin_win_opts) do
      vim.opt_local[key] = value
    end
  end)

  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, lines)
  return scratch_buf
end

---Max width of the clone window is filetype's textwidth + text offset (statuscolumn width)
---@param info vim.fn.getwininfo.ret.item
---@param buf integer
---@return integer
function H.calculate_clone_win_width(info, buf)
  local tw = cfg.config.max_width
  if not tw then
    local ok, res = pcall(
      vim.filetype.get_option,
      vim.bo[buf].filetype,
      "textwidth"
    )
    tw = ok and tonumber(res) or 100
  end

  local desired_ww = tw + info.textoff
  return math.min(desired_ww, info.width)
end

---Call fn with temporary current win and buf
---@param win integer
---@param buf integer
---@param fn fun()
function H.call_for_win_buf(win, buf, fn)
  vim.api.nvim_win_call(win, function()
    vim.api.nvim_buf_call(buf, fn)
  end)
end

---@param win integer
---@param with_buffer boolean
---@return boolean
function H.safe_win_close(win, with_buffer)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local ok, err = pcall(vim.api.nvim_win_close, win, true)
  if not ok and err then
    vim.notify(err, vim.log.levels.ERROR)
  end
  if with_buffer then
    local b_ok, b_err = pcall(vim.api.nvim_buf_delete, 0, { force = true })
    if not b_ok and b_err then
      vim.notify(b_err, vim.log.levels.ERROR)
    end
  end
  return ok
end

function H.set_keymaps(cb, buf)
  local map = vim.keymap.set

  for lhs, rhs in pairs(cfg.config.mappings) do
    map("n", lhs, cb(rhs), { buffer = buf })
  end
end

return M
