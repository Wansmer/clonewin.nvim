local w = require("clonewin.win")
local M = {}

function M.setup()
  vim.api.nvim_create_autocmd("BufEnter", {
    callback = function(e)
      if vim.tbl_contains({ "markdown", "quarto" }, vim.bo[e.buf].filetype) then
        local win = vim.api.nvim_get_current_win()
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative == "" then
          vim.schedule(function()
            w.new(win, e.buf)
          end)
        end
      end
    end,
  })
end

return M
