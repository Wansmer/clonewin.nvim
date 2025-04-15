---@class CloneWinCfg
---@field ft string[] List of filetypes to replace window with clonewin
---@field max_width? integer Max width of the clone window (excluding statuscolumn width). By default equal to filetype textwidth or 100
---@field mappings table<string, string|fun()> Dict of mappings that must be executed from "normal" window to their correct work
---@field override_ft table<string, CloneWinCfg> Override default config per filetype
---@field clone_win_opts table<string, any> Local options for clone window and buffer
---@field origin_win_opts table<string, any> Local options for origin (normal) window and buffer
---@field hooks table<"on_open"|"on_close", fun()> TODO

local M = {}

---@type CloneWinCfg
M.DEFAULT_CONFIG = {
  ft = { "markdown", "quarto" },
  mappings = {
    ["<C-w>h"] = "<C-w>h",
    ["<C-w>j"] = "<C-w>j",
    ["<C-w>k"] = "<C-w>k",
    ["<C-w>l"] = "<C-w>l",
  },
  clone_win_opts = {
    linebreak = true,
    wrap = true,
    textwidth = 0, -- To disable hard wrap
    winhighlight = "NormalFloat:Normal,NormalNC:Normal",
  },
  origin_win_opts = {
    winhighlight = "CursorLine:Normal",
  },
  override_ft = {},
  hooks = {},
}

---@type CloneWinCfg
M.config = M.DEFAULT_CONFIG

---@param opts CloneWinCfg?
function M.merge_config(opts)
  M.config = vim.tbl_deep_extend("force", M.DEFAULT_CONFIG, opts or {})
end

return M
