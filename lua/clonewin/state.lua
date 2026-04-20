local M = {}

M.state = {
  ---@type table<integer, CloneWin>
  observed = {},
}

---Clear all clone windows
function M.clear()
  for win, clone in pairs(M.state.observed) do
    clone:close_clone(true)
    M.state.observed[win] = nil
  end
end

---Add observed and clone window to state
---@param win integer Observed (normal) window
---@param clone CloneWin
function M.add(win, clone)
  M.state.observed[win] = clone
end

---Get clone window for observed window
---@param win integer Observed (normal) window
---@return CloneWin
function M.get(win)
  return M.state.observed[win]
end

---Checks if clone window with same buffer exists
---@param win integer
---@param buf integer
---@return boolean, CloneWin?
function M.has(win, buf)
  local clone = M.state.observed[win]
  if not clone then
    return false, nil
  end

  return clone.wins.clone.buf == buf, clone
end

return M
