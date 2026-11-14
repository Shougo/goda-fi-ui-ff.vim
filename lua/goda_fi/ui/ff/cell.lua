-- The size of a cell of the terminal in pixels, for the images of the
-- preview (Neovim: vim.ui.img takes cells, not pixels). The terminal says
-- it in the size of its window (TIOCGWINSZ, from /dev/tty), when it fills
-- the pixels in.
local M = {}

local ok, ffi = pcall(require, 'ffi')
if ok then
  ok = pcall(ffi.cdef, [[
    struct goda_fi_winsize {
      unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel;
    };
    int open(const char *path, int flags, ...);
    int close(int fd);
    int ioctl(int fd, unsigned long request, ...);
  ]])
end

-- {width, height}, or nil when it is not known.
function M.pixels()
  if not ok or vim.fn.has('unix') == 0 then
    return nil
  end
  local request = vim.fn.has('mac') == 1 and 0x40087468 or 0x5413
  local fd = ffi.C.open('/dev/tty', 0)
  if fd < 0 then
    return nil
  end
  local ws = ffi.new('struct goda_fi_winsize')
  local r = ffi.C.ioctl(fd, request, ws)
  ffi.C.close(fd)
  if r ~= 0 or ws.ws_xpixel == 0 or ws.ws_ypixel == 0 or ws.ws_col == 0 or ws.ws_row == 0 then
    return nil
  end
  return { math.floor(ws.ws_xpixel / ws.ws_col), math.floor(ws.ws_ypixel / ws.ws_row) }
end

return M
