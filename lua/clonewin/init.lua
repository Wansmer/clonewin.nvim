local cfg = require("clonewin.config")
local w = require("clonewin.win")
local log = require("clonewin.logger")

local M = {}

---Setup clonewin.nvim
---@param opts CloneWinCfg?
function M.setup(opts)
  cfg.merge_config(opts)
  log.trace("Setup clonewin.nvim ==================================")

  vim.api.nvim_create_autocmd({ "BufEnter" }, {
    callback = vim.schedule_wrap(function(e)
      if not vim.api.nvim_buf_is_valid(e.buf) then
        return
      end
      local ft = vim.bo[e.buf].ft
      if vim.tbl_contains(cfg.config.ft, ft) then
        local win = vim.api.nvim_get_current_win()
        local win_cfg = vim.api.nvim_win_get_config(win)

        log.debug("%s event. Win: %s, Buf: %s, FT: %s", e.event, win, e.buf, ft)

        if win_cfg.relative == "" then
          w.new(win, e.buf, cfg.config.override_ft[ft] or cfg.config)
        end
      end
    end),
  })
end

return M
