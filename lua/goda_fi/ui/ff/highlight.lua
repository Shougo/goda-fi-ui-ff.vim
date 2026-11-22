-- The highlights of the items on Neovim, for s:highlight() of
-- autoload/goda_fi/ui/ff.vim: the loop over them in Lua (Vim has
-- autoload/goda_fi/ui/ff/highlight.vim).

local M = {}

--- Add the highlights {row, col, length, group, priority} of the lines. A
-- group that does not exist and a column past the end of its line are
-- skipped; a length of 0 or past the end goes to the end.
function M.add(bufnr, ns, lines, highlights)
  local valid = {}
  local set_extmark = vim.api.nvim_buf_set_extmark
  for _, h in ipairs(highlights) do
    local row, col, length, group, priority = h[1], h[2], h[3], h[4], h[5]
    local ok = valid[group]
    if ok == nil then
      ok = vim.fn.hlexists(group) == 1
      valid[group] = ok
    end
    local text = lines[row] or ''
    if ok and col <= #text then
      if length <= 0 or col + length - 1 > #text then
        length = #text - col + 1
      end
      set_extmark(bufnr, ns, row - 1, col - 1, {
        end_col  = col - 1 + length,
        hl_group = group,
        priority = priority,
      })
    end
  end
end

return M
