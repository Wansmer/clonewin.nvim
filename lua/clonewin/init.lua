local cfg = require("clonewin.config")
local w = require("clonewin.win")

local M = {}

---Setup clonewin.nvim
---@param opts CloneWinCfg?
function M.setup(opts)
  cfg.merge_config(opts)

  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(e)
      local ft = vim.bo[e.buf].ft
      if vim.tbl_contains(cfg.config.ft, ft) then
        local win = vim.api.nvim_get_current_win()
        local win_cfg = vim.api.nvim_win_get_config(win)

        if win_cfg.relative == "" then
          vim.schedule(function()
            w.new(win, e.buf, cfg.config.override_ft[ft] or cfg.config)
          end)
        end
      end
    end,
  })
end

return M
