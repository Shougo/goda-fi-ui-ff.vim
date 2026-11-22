" The ff UI: a buffer of items in a split window (ui/ff/ff.go makes what it
" shows). The UIs made of it (ff.NewUI) are this UI too, with a buffer of
" their own: every redraw says which (its "ui").
"
" Every redraw comes as one call, goda_fi#ui#ff#_redraw(), with a version:
" one older than what is shown is dropped, and once the window is closed only
" one that opens it again is applied. The cursor stays on its item: the IDs of
" the lines come with them.

let s:ns = has('nvim') ? nvim_create_namespace('goda-fi-ff') : 0
let s:state = {}

function! s:st(name) abort
  if !has_key(s:state, a:name)
    let s:state[a:name] = {
          \ 'version': 0,
          \ 'ui': 'ff',
          \ 'levels': [],
          \ 'opened_split': '',
          \ 'reopening': 0,
          \ 'closed': 1,
          \ 'bufnr': -1,
          \ 'ids': [],
          \ 'input': '',
          \ 'done': 1,
          \ 'prev_winid': 0,
          \ 'prev_bufnr': -1,
          \ 'params': {},
          \ 'preview_winid': -1,
          \ 'preview_bufnr': -1,
          \ 'preview_id': 0,
          \ 'image_id': -1,
          \ 'image_path': '',
          \ 'image_zindex': 0,
          \ 'image_area': [],
          \ 'image_size': [],
          \ 'image_fit': v:null,
          \ 'sent': v:null,
          \ 'keep_row': 0,
          \ 'auto_enabled': v:false,
          \ 'auto_id': 0,
          \ 'auto_timer': -1,
          \ }
  endif
  return s:state[a:name]
endfunction

" A size: a number, or an expression of Vim (uiParams are the params).
function! s:eval(v, uiParams = {}) abort
  let uiParams = a:uiParams
  return type(a:v) == v:t_string ? eval(a:v) : a:v
endfunction

" ---------------------------------------------------------------------------
" Drawing

function! goda_fi#ui#ff#_redraw(name, r) abort
  try
    call s:redraw(a:name, a:r)
  finally
    " The next one is sent once this one is done (fi.UIAcker).
    if goda#is_running('fi')
      call goda#notify('fi', 'event', a:name, 'drawn', a:r.version)
    endif
  endtry
endfunction

function! s:redraw(name, r) abort
  let st = s:st(a:name)
  if a:r.version <= st.version || (st.closed && !a:r.open)
    return
  endif
  let st.version = a:r.version
  let st.params = a:r.params
  let st.ui = get(a:r, 'ui', 'ff')
  call goda_fi#ui#_register(a:name, st.ui)

  let bufnr = s:buffer(a:name)
  let winid = bufwinid(bufnr)
  let opened = 0
  if winid > 0 && !st.closed && st.opened_split !=# ''
        \ && s:split(a:r.params) !=# st.opened_split && winnr('$') > 1
    " The split changed (updateOptions): opened again.
    let st.reopening = 1
    try
      call win_execute(winid, 'close')
    finally
      let st.reopening = 0
    endtry
    let winid = s:open_window(a:name, bufnr, a:r.params)
    let opened = 1
  endif
  if a:r.open
    let st.closed = 0
    if a:r.prevWinid > 0 && a:r.prevWinid != winid
      let st.prev_winid = s:prev_window(a:name, a:r.prevWinid, s:split(a:r.params))
    endif
    if winid < 0
      let winid = s:open_window(a:name, bufnr, a:r.params)
      let opened = 1
    else
      call win_gotoid(winid)
    endif
  endif

  let old_row = winid > 0 ? line('.', winid) : 0
  let old_id = get(st.ids, old_row - 1, 0)
  call s:set_lines(bufnr, a:r.lines)
  let st.ids = a:r.ids
  let st.levels = get(a:r, 'levels', [])
  let st.input = a:r.input
  let vars = get(a:r, 'vars', {})
  if !empty(vars)
    " The variables of the UI (ff.Options.Vars), in the buffer and its tab
    " page.
    let tab = winid > 0 ? win_id2tabwin(winid)[0] : tabpagenr()
    for [name, val] in items(vars)
      call setbufvar(bufnr, name, val)
      call settabvar(tab, name, val)
    endfor
  endif
  call setbufvar(bufnr, 'goda_fi_version', a:r.version)
  call s:highlight(bufnr, a:r)

  if winid > 0
    let n = len(a:r.lines)
    if a:r.params.autoResize
      call s:auto_resize(winid, a:r.lines, a:r.params)
    endif
    if a:r.cursor > 0
      let row = a:r.cursor
    elseif a:r.reset && st.keep_row > 0
      " The cursor was moved while the filter was typed, before its items
      " came: it stays where it was moved.
      let row = st.keep_row
    elseif a:r.reset
      let row = a:r.params.reversed ? n : 1
    else
      let i = old_id == 0 ? -1 : index(a:r.ids, old_id)
      let row = i >= 0 ? i + 1 : old_row
    endif
    let row = max([1, min([row, n])])
    call win_execute(winid, 'call cursor(' . row . ', 1)')
    if type(st.sent) == v:t_string && a:r.input ==# st.sent
      " What was typed is shown.
      let st.sent = v:null
      let st.keep_row = 0
    endif
    if a:r.params.reversed && (a:r.reset || opened)
      call win_execute(winid, 'normal! zb')
    endif
    if a:r.params.overwriteStatusline
      " Not "[async]" in the command line, where every key gathers a volatile
      " source again (as ddu-ui-ff).
      let foot = mode() ==# 'c' ? substitute(a:r.status[1], ' \[async\]$', '', '') : a:r.status[1]
      let line = s:escape(a:r.status[0]) . ' %#LineNr#%{line(".")}/%{line("$")}%*' . s:escape(foot)
      if getwinvar(winid, '&statusline') !=# line
        call setwinvar(winid, '&statusline', line)
      endif
    endif
  endif

  if a:r.open
    call s:set_auto_action(a:name, bufnr, a:r.params)
  endif
  if opened
    call goda_fi#util#doautocmd('GodaFi:uiReady')
  endif
  if a:r.done && !st.done
    call goda_fi#util#doautocmd('GodaFi:uiDone')
  endif
  let st.done = a:r.done
  call goda_fi#util#doautocmd('GodaFi:uiRedraw')
  " Needed while the filter is typed (and harmless otherwise).
  redraw
  " The item under the cursor may be another one.
  call s:auto_action(a:name, 0)
endfunction

" The window the actions of the session name go to, for a start from winid.
" Not the window of another UI of ff (a start from it: the filer too): the
" actions would go there, and it would stay. That of its start instead; and
" a float of it (that would cover them) is closed, as its session quit, the
" window opening from that one. With split "no", the window of a split UI
" stays: it takes its place.
function! s:prev_window(name, winid, split) abort
  let winid = a:winid
  let seen = {}
  let closed = 0
  while !has_key(seen, winid)
    let seen[winid] = 1
    let other = s:ui_of_window(winid)
    if other ==# '' || other ==# a:name
      break
    endif
    let ost = s:st(other)
    if has('nvim') && nvim_win_get_config(winid).relative !=# ''
      call s:close_preview(ost)
      call nvim_win_close(winid, v:true)
      let closed = 1
    elseif a:split ==# 'no'
      break
    endif
    if ost.prev_winid <= 0 || win_id2win(ost.prev_winid) <= 0
      return win_id2win(winid) > 0 ? winid : 0
    endif
    let winid = ost.prev_winid
  endwhile
  if closed
    call win_gotoid(winid)
  endif
  return winid
endfunction

" The session of the ff UI shown in the window winid ('' if none).
function! s:ui_of_window(winid) abort
  let bufnr = winbufnr(a:winid)
  if bufnr <= 0
    return ''
  endif
  for [name, st] in items(s:state)
    if st.bufnr == bufnr && !st.closed
      return name
    endif
  endfor
  return ''
endfunction

function! s:escape(s) abort
  return substitute(a:s, '%', '%%', 'g')
endfunction

function! s:buffer(name) abort
  let st = s:st(a:name)
  if st.bufnr > 0 && bufexists(st.bufnr)
        \ && getbufvar(st.bufnr, 'goda_fi_ui', 'ff') ==# st.ui
    return st.bufnr
  endif
  let bufnr = bufadd('goda-fi-' . st.ui . '-' . a:name)
  " Before loading: the name is not a file.
  call setbufvar(bufnr, '&buftype', 'nofile')
  call bufload(bufnr)
  call setbufvar(bufnr, '&bufhidden', 'hide')
  call setbufvar(bufnr, '&swapfile', 0)
  call setbufvar(bufnr, '&buflisted', 0)
  call setbufvar(bufnr, '&undolevels', -1)
  call setbufvar(bufnr, '&modifiable', 0)
  call setbufvar(bufnr, 'goda_fi_name', a:name)
  call setbufvar(bufnr, 'goda_fi_ui', st.ui)
  execute 'augroup goda-fi-ff-' . bufnr
    autocmd!
    execute 'autocmd BufWinLeave <buffer=' . bufnr . '> call s:on_close(' . string(a:name) . ')'
    execute 'autocmd BufWipeout <buffer=' . bufnr . '> call s:on_wipe(' . string(a:name) . ')'
  augroup END
  let st.bufnr = bufnr
  return bufnr
endfunction

" The split of the params: "floating" is for Neovim (Vim splits
" horizontally, as ddu-ui-ff).
function! s:split(p) abort
  return a:p.split ==# 'floating' && !has('nvim') ? 'horizontal' : a:p.split
endfunction

function! s:open_window(name, bufnr, p) abort
  let st = s:st(a:name)
  let split = s:split(a:p)
  let st.opened_split = split
  if split ==# 'tab'
    tabnew
    let st.prev_bufnr = bufnr('%')
    execute 'silent keepalt buffer' a:bufnr
  elseif split ==# 'no'
    let st.prev_bufnr = bufnr('%')
    execute 'silent keepalt buffer' a:bufnr
  elseif split ==# 'floating'
    call s:open_float(a:bufnr, a:p)
  elseif split ==# 'vertical'
    execute 'silent' a:p.splitDirection 'vertical split'
    execute 'silent keepalt buffer' a:bufnr
    execute 'vertical resize' s:eval(a:p.winWidth, a:p)
    setlocal winfixwidth
  else
    execute 'silent' a:p.splitDirection 'split'
    execute 'silent keepalt buffer' a:bufnr
    execute 'resize' s:eval(a:p.winHeight, a:p)
    setlocal winfixheight
  endif
  setlocal nowrap nolist nonumber norelativenumber nospell
  setlocal nofoldenable foldcolumn=0 signcolumn=no cursorline
  let ft = 'goda-fi-' . st.ui
  if &filetype !=# ft
    " Your mappings: autocmd FileType goda-fi-ff (goda-fi-{ui})
    execute 'setlocal filetype=' . ft
  endif
  return win_getid()
endfunction

" The window of the items as a float of Neovim, entered.
function! s:open_float(bufnr, p) abort
  let opts = {
        \ 'relative': 'editor',
        \ 'row': s:eval(a:p.winRow, a:p),
        \ 'col': s:eval(a:p.winCol, a:p),
        \ 'width': max([1, s:eval(a:p.winWidth, a:p)]),
        \ 'height': max([1, s:eval(a:p.winHeight, a:p)]),
        \ 'border': a:p.floatingBorder,
        \ }
  if !empty(a:p.floatingTitle)
    let opts.title = a:p.floatingTitle
    let opts.title_pos = a:p.floatingTitlePos
  endif
  call nvim_open_win(a:bufnr, v:true, opts)
  let &l:winblend = a:p.floatingBlend
  let hl = get(a:p, 'highlights', {})
  let &l:winhighlight = join([
        \ 'Normal:' . get(hl, 'floating', 'NormalFloat'),
        \ 'FloatBorder:' . get(hl, 'floatingBorder', 'FloatBorder'),
        \ 'CursorLine:' . get(hl, 'floatingCursorLine', 'CursorLine'),
        \ ], ',')
endfunction

" No higher than the items (autoResize).
" The window as high as its lines (horizontal, floating), or as wide
" (vertical), within winHeight and winWidth.
function! s:auto_resize(winid, lines, p) abort
  let height = max([1, min([len(a:lines), s:eval(a:p.winHeight, a:p)])])
  let split = s:split(a:p)
  if split ==# 'floating'
    call nvim_win_set_config(a:winid, {'height': height})
  elseif split ==# 'horizontal'
    call win_execute(a:winid, 'resize ' . height)
  elseif split ==# 'vertical'
    let width = max([1] + map(copy(a:lines), 'strdisplaywidth(substitute(v:val, " *$", "", ""))'))
    let width = min([width + 1, s:eval(a:p.winWidth, a:p)])
    call win_execute(a:winid, 'vertical resize ' . width)
  endif
endfunction

function! s:set_lines(bufnr, lines) abort
  call setbufvar(a:bufnr, '&modifiable', 1)
  try
    if empty(a:lines)
      silent call deletebufline(a:bufnr, 1, '$')
    else
      call setbufline(a:bufnr, 1, a:lines)
      let total = get(get(getbufinfo(a:bufnr), 0, {}), 'linecount', 0)
      if total > len(a:lines)
        silent call deletebufline(a:bufnr, len(a:lines) + 1, '$')
      endif
    endif
  finally
    call setbufvar(a:bufnr, '&modifiable', 0)
    call setbufvar(a:bufnr, '&modified', 0)
  endtry
endfunction

" (Vim only.)
function! s:prop_type(group, priority) abort
  return goda_fi#ui#ff#highlight#PropType(a:group, a:priority)
endfunction

function! s:highlight(bufnr, r) abort
  if has('nvim')
    call nvim_buf_clear_namespace(a:bufnr, s:ns, 0, -1)
  else
    call prop_clear(1, max([1, len(a:r.lines)]), {'bufnr': a:bufnr})
  endif
  " (In Lua or Vim9 script: hundreds of them.)
  if !empty(a:r.highlights)
    if has('nvim')
      call luaeval("require('goda_fi.ui.ff.highlight').add(_A[1],_A[2],_A[3],_A[4])",
            \ [a:bufnr, s:ns, a:r.lines, a:r.highlights])
    else
      call goda_fi#ui#ff#highlight#Add(a:bufnr, a:r.lines, a:r.highlights)
    endif
  endif
  for info in a:r.info
    if has('nvim')
      call nvim_buf_set_extmark(a:bufnr, s:ns, info.row - 1, 0, {
            \ 'virt_lines': map(copy(info.lines),
            \   {_, l -> l[1] ==# '' ? [[l[0]]] : [[l[0], l[1]]]})})
    else
      for [text, group] in info.lines
        call prop_add(info.row, 0, {'type': s:prop_type(hlexists(group) ? group : '', 50),
              \ 'text': text, 'text_align': 'below', 'bufnr': a:bufnr})
      endfor
    endif
  endfor
endfunction

" ---------------------------------------------------------------------------
" Closing

function! goda_fi#ui#ff#_quit(name, version) abort
  let st = s:st(a:name)
  let st.closed = 1
  call s:close_preview(st)
  let winid = bufwinid(st.bufnr)
  if winid > 0
    let split = get(st.params, 'split', 'horizontal')
    call win_gotoid(winid)
    if split ==# 'no' || winnr('$') == 1 && tabpagenr('$') == 1
      if bufexists(st.prev_bufnr) && st.prev_bufnr != st.bufnr
        execute 'silent keepalt buffer' st.prev_bufnr
      else
        enew
      endif
    else
      silent! close!
    endif
  endif
  if win_id2win(st.prev_winid) > 0
    call win_gotoid(st.prev_winid)
  endif
  call goda_fi#util#doautocmd('GodaFi:uiQuit')
endfunction

" The window was closed (or shows another buffer).
function! s:on_close(name) abort
  let st = s:st(a:name)
  if st.reopening
    return
  endif
  if !st.closed
    let st.closed = 1
    if goda#is_running('fi')
      call goda#notify('fi', 'event', a:name, 'close', st.version)
    endif
  endif
  " Not while the window closes.
  call timer_start(0, {-> s:close_preview(st)})
endfunction

function! s:on_wipe(name) abort
  call s:on_close(a:name)
  let st = s:st(a:name)
  let st.bufnr = -1
  let st.ids = []
endfunction

function! goda_fi#ui#ff#_visible(name) abort
  let st = s:st(a:name)
  return !st.closed && bufwinid(st.bufnr) > 0
endfunction

" ---------------------------------------------------------------------------
" Actions

" Where the cursor is, for an action: {version, cursor, id}.
function! goda_fi#ui#ff#_pos(name) abort
  let st = s:st(a:name)
  let winid = bufwinid(st.bufnr)
  let row = winid > 0 ? line('.', winid) : 0
  return {'version': st.version, 'cursor': row, 'id': get(st.ids, row - 1, 0)}
endfunction

" The actions done here: 1 if it was one.
function! goda_fi#ui#ff#_local_action(name, action, params) abort
  if a:action ==# 'cursorNext'
    call s:move(a:name, get(a:params, 'count', 1), get(a:params, 'loop', v:false))
  elseif a:action ==# 'cursorPrevious'
    call s:move(a:name, -get(a:params, 'count', 1), get(a:params, 'loop', v:false))
  elseif a:action ==# 'inputAction'
    call goda_fi#util#request_wait('fi', 'uiAction', a:name, 'inputActionNames', a:params,
          \ goda_fi#ui#ff#_pos(a:name))
  elseif a:action ==# 'cursorTreeTop'
    call s:tree_move(a:name, -1)
  elseif a:action ==# 'cursorTreeBottom'
    call s:tree_move(a:name, 1)
  elseif a:action ==# 'openFilterWindow'
    call s:open_filter(a:name, a:params)
  elseif a:action ==# 'toggleAutoAction'
    let st = s:st(a:name)
    let st.auto_enabled = !st.auto_enabled
    let st.auto_id = 0
    if st.auto_enabled
      call s:auto_action(a:name, 1)
    else
      call s:close_preview(st)
    endif
  else
    return 0
  endif
  return 1
endfunction

" inputAction: the binary gives the names of the actions (in a request: the
" action is asked for, and run, once it is done).
function! goda_fi#ui#ff#_input_action(name, names) abort
  let s:action_names = a:names
  call timer_start(0, {-> s:input_action(a:name)})
endfunction

function! s:input_action(name) abort
  try
    let action = input('Action: ', '', 'customlist,goda_fi#ui#ff#_complete_action')
  catch /^Vim:Interrupt/
    return
  endtry
  redraw
  if action !=# ''
    call goda_fi#ui#do_action('itemAction', {'name': action}, a:name)
  endif
endfunction

function! goda_fi#ui#ff#_complete_action(arglead, cmdline, cursorpos) abort
  return filter(copy(get(s:, 'action_names', [])), 'stridx(v:val, a:arglead) == 0')
endfunction

" cursorTreeTop (dir -1) and cursorTreeBottom (1): the cursor to the first
" or the last item of the tree it is in (its level).
function! s:tree_move(name, dir) abort
  let st = s:st(a:name)
  let winid = bufwinid(st.bufnr)
  if winid < 0 || empty(st.levels)
    return
  endif
  let row = line('.', winid)
  let level = get(st.levels, row - 1, 0)
  let target = row
  let i = row - 1 + a:dir
  while i >= 0 && i < len(st.levels) && st.levels[i] >= level
    if st.levels[i] == level
      let target = i + 1
    endif
    let i += a:dir
  endwhile
  call win_execute(winid, 'call cursor(' . target . ', 1)')
  call s:auto_action(a:name, 1)
endfunction

function! s:move(name, count, loop) abort
  let st = s:st(a:name)
  let winid = bufwinid(st.bufnr)
  if winid < 0
    return
  endif
  let last = line('$', winid)
  let row = line('.', winid) + a:count
  if row > last
    let row = a:loop ? 1 : last
  elseif row < 1
    let row = a:loop ? last : 1
  endif
  call win_execute(winid, 'call cursor(' . row . ', 1)')
  if type(st.sent) == v:t_string && st.sent !=# st.input
    " The items of what was typed are still to come.
    let st.keep_row = row
  endif
  " The cursor of another window moved, or the screen of the filter.
  redraw
  " CursorMoved is not for another window, or in the command line.
  call s:auto_action(a:name, 1)
endfunction

" The filter: input() in the command line, every change filtering (unless
" the items are more than filterUpdateMax: then when it is done).
function! s:open_filter(name, params) abort
  let st = s:st(a:name)
  let s:filter_name = a:name
  let s:filter_prev = st.input
  let max = get(st.params, 'filterUpdateMax', 0)
  augroup goda-fi-filter
    autocmd!
    if max <= 0 || get(st.params, 'itemCount', 0) <= max
      autocmd CmdlineChanged * call s:filter_update(getcmdline())
    endif
  augroup END
  call goda_fi#util#doautocmd('GodaFi:uiOpenFilterWindow')
  redraw
  let prompt = get(a:params, 'prompt', get(st.params, 'filterPrompt', ''))
  let s:filter_callback = get(st.params, 'filterUpdateCallback', '')
  let func = get(st.params, 'filterInputFunc', '')
  let opts_func = get(st.params, 'filterInputOptsFunc', '')
  try
    " The functions are given a completion, as ddu.vim's: input() with ""
    " for it fails (E180), and cmdline#input() then gives "".
    let completion = 'custom,goda_fi#ui#ff#_complete_input'
    if has('nvim') && opts_func !=# ''
      let input = call(opts_func, [{'prompt': prompt, 'default': st.input,
            \ 'completion': completion, 'cancelreturn': st.input}])
    elseif func !=# '' && func !=# 'input'
      let input = call(func, [prompt, st.input, completion])
    elseif has('nvim')
      let input = input({'prompt': prompt, 'default': st.input,
            \ 'completion': completion, 'cancelreturn': st.input})
    else
      let input = input(prompt, st.input, completion)
    endif
  finally
    augroup goda-fi-filter
      autocmd!
    augroup END
    call goda_fi#util#doautocmd('GodaFi:uiCloseFilterWindow')
  endtry
  call s:filter_update(input)
endfunction

" The completion of the filter: nothing (the input of the session is not a
" command).
function! goda_fi#ui#ff#_complete_input(arglead, cmdline, cursorpos) abort
  return ''
endfunction

function! s:filter_update(input) abort
  let input = get(s:, 'filter_callback', '') ==# '' ? a:input
        \ : call(s:filter_callback, [a:input])
  if input ==# s:filter_prev
    return
  endif
  let s:filter_prev = input
  let st = s:st(s:filter_name)
  let st.sent = input
  let st.keep_row = 0
  call goda_fi#redraw(s:filter_name, {'input': input})
endfunction

" ---------------------------------------------------------------------------
" autoAction: a UI action run when the cursor is on another item (the
" preview, say), once enabled by startAutoAction or toggleAutoAction.

function! s:set_auto_action(name, bufnr, p) abort
  let st = s:st(a:name)
  " Every time the window opens, as ddu-ui-ff at a start.
  let st.auto_enabled = a:p.startAutoAction ? v:true : v:false
  let st.auto_id = 0
  execute 'augroup goda-fi-ff-auto-' . a:bufnr
    autocmd!
    if get(a:p.autoAction, 'name', '') !=# ''
      execute 'autocmd CursorMoved <buffer=' . a:bufnr . '> call s:auto_action('
            \ . string(a:name) . ', 0)'
    endif
  augroup END
endfunction

" Run the autoAction after its delay (now: in the command line, where
" timers wait).
function! s:auto_action(name, now) abort
  let st = s:st(a:name)
  let aa = get(st.params, 'autoAction', {})
  if !st.auto_enabled || get(aa, 'name', '') ==# '' || st.closed
    return
  endif
  call timer_stop(st.auto_timer)
  if a:now || mode() ==# 'c' || aa.delay <= 0
    call s:do_auto_action(a:name)
  else
    let st.auto_timer = timer_start(aa.delay, {-> s:do_auto_action(a:name)})
  endif
endfunction

function! s:do_auto_action(name) abort
  let st = s:st(a:name)
  let pos = goda_fi#ui#ff#_pos(a:name)
  if pos.id == 0 || pos.id == st.auto_id || st.closed
    return
  endif
  let st.auto_id = pos.id
  let aa = st.params.autoAction
  call goda_fi#ui#do_action(aa.name, get(aa, 'params', {}), a:name)
endfunction

" ---------------------------------------------------------------------------
" Preview

function! goda_fi#ui#ff#_close_preview(name) abort
  call s:close_preview(s:st(a:name))
endfunction

" Is the preview window (a window, a float, a popup) there?
function! s:preview_valid(winid) abort
  if a:winid <= 0
    return 0
  endif
  if has('nvim')
    return nvim_win_is_valid(a:winid)
  endif
  return win_id2win(a:winid) > 0 || !empty(popup_getpos(a:winid))
endfunction

function! s:close_preview(st) abort
  let winid = a:st.preview_winid
  if s:preview_valid(winid)
    if !has('nvim') && win_id2win(winid) <= 0
      call popup_close(winid)
    elseif has('nvim') && nvim_win_get_config(winid).relative !=# ''
      call nvim_win_close(winid, v:true)
    elseif winnr('$') > 1
      execute 'silent!' win_id2win(winid) . 'close!'
    endif
  endif
  let a:st.preview_winid = -1
  let a:st.preview_id = 0
  call s:clear_image(a:st)
endfunction

function! s:preview_buffer(name) abort
  let st = s:st(a:name)
  if !bufexists(st.preview_bufnr)
    let st.preview_bufnr = bufadd('goda-fi-preview-' . a:name)
    call setbufvar(st.preview_bufnr, '&buftype', 'nofile')
    call bufload(st.preview_bufnr)
    call setbufvar(st.preview_bufnr, '&bufhidden', 'hide')
    call setbufvar(st.preview_bufnr, '&swapfile', 0)
    call setbufvar(st.preview_bufnr, '&buflisted', 0)
    call setbufvar(st.preview_bufnr, '&undolevels', -1)
  endif
  return st.preview_bufnr
endfunction

" Show the previewer pv of the item id.
function! goda_fi#ui#ff#_preview(name, id, pv, p) abort
  let st = s:st(a:name)
  if a:p.toggle && st.preview_id == a:id && s:preview_valid(st.preview_winid)
    call s:close_preview(st)
    return
  endif
  let ffwin = bufwinid(st.bufnr)
  if a:p.previewSplit ==# 'no' || ffwin < 0
    return
  endif
  " An image (imageExts): over the preview window, which is empty.
  let image = s:image_path(a:pv, a:p)
  let [lines, path] = image !=# '' ? [[], ''] : s:preview_lines(a:pv, a:p)
  let bufnr = s:preview_buffer(a:name)
  call setbufvar(bufnr, '&modifiable', 1)
  silent call deletebufline(bufnr, 1, '$')
  call setbufline(bufnr, 1, empty(lines) ? [''] : lines)
  call setbufvar(bufnr, '&modifiable', 0)
  call setbufvar(bufnr, '&modified', 0)

  let height = s:eval(a:p.previewHeight, a:p)
  let floating = get(a:p, 'previewFloating', v:false)
  if !s:preview_valid(st.preview_winid)
    let st.preview_winid = floating
          \ ? s:open_preview_float(ffwin, bufnr, a:p)
          \ : s:open_preview_split(ffwin, bufnr, a:p)
  elseif !has('nvim') && win_id2win(st.preview_winid) <= 0
    " A popup of Vim shows its buffer already.
  else
    call win_execute(st.preview_winid, 'silent keepalt buffer ' . bufnr)
  endif
  let winid = st.preview_winid
  let st.preview_id = a:id

  for opt in ['nowrap', 'nonumber', 'norelativenumber', 'nolist',
        \ 'nofoldenable', 'signcolumn=no', 'foldcolumn=0', 'nocursorline']
    call win_execute(winid, 'silent! setlocal ' . opt)
  endfor
  if win_id2win(winid) > 0 && !(has('nvim') && nvim_win_get_config(winid).relative !=# '')
    call win_execute(winid, 'setlocal previewwindow')
  endif
  " Highlighted as what it shows.
  call setbufvar(bufnr, '&syntax', get(a:pv, 'syntax', ''))
  if get(a:pv, 'filetype', '') !=# ''
    call setbufvar(bufnr, '&filetype', a:pv.filetype)
  elseif path !=# ''
    call setbufvar(bufnr, '&filetype', '')
    call win_execute(winid, 'silent! doautocmd filetypedetect BufRead ' . fnameescape(path))
  else
    call setbufvar(bufnr, '&filetype', '')
  endif

  let lnum = get(a:pv, 'lineNr', 0)
  if lnum <= 0 && get(a:pv, 'pattern', '') !=# ''
    let lnum = max([1, match(lines, a:pv.pattern) + 1])
  endif
  let lnum = max([1, lnum])
  if !has('nvim') && win_id2win(winid) <= 0
    call popup_setoptions(winid, {'firstline': max([1, lnum - height / 2])})
  else
    call win_execute(winid, 'call cursor(' . lnum . ', 1)')
    if lnum > 1
      call win_execute(winid, 'normal! zz')
    endif
  endif
  if get(a:p, 'onPreview', '') !=# ''
    call call(a:p.onPreview, [{'previewWinId': winid, 'lineNr': lnum}])
  endif
  redraw
  if image !=# ''
    call s:show_image(st, image, get(a:p, 'previewFloatingZindex', 100) + 1)
  else
    call s:clear_image(st)
  endif
endfunction

" The image to preview (p.imagePath: an extension of imageExts), when
" images can be shown; '' if not (the previewer pv instead).
function! s:image_path(pv, p) abort
  let path = get(a:p, 'imagePath', '')
  if path ==# '' || !filereadable(path) || !s:image_supported()
        \ || empty(s:image_size(path))
    return ''
  endif
  return path
endfunction

" Neovim: vim.ui.img (Neovim 0.13, or a replacement of it); Vim: a popup
" of an image, from what ImageMagick gives.
function! s:image_supported() abort
  if has('nvim')
    return luaeval('type(vim.ui) == "table" and type(vim.ui.img) == "table"')
  endif
  return has('patch-9.2.0612') && has('image')
        \ && executable('convert') && executable('identify')
endfunction

" The size of the image path in pixels: [width, height], or [] when it is
" not one that can be shown. vim.ui.img shows PNG (its header says it);
" ImageMagick reads the others.
function! s:image_size(path) abort
  if has('nvim')
    let head = readblob(a:path, 0, 24)
    if len(head) < 24 || head[1 : 3] != 0z504E47
      return []
    endif
    let Int = {i -> ((head[i] * 256 + head[i + 1]) * 256 + head[i + 2]) * 256 + head[i + 3]}
    let size = [Int(16), Int(20)]
  else
    let out = systemlist('identify -format "%w %h" ' . shellescape(a:path . '[0]'))
    let size = v:shell_error != 0 ? [] : map(split(get(out, 0, '')), 'str2nr(v:val)')
  endif
  return len(size) == 2 && size[0] > 0 && size[1] > 0 ? size : []
endfunction

" The size of a cell in pixels: [width, height]. Vim: getcellpixels();
" Neovim: what the terminal says (lua/goda_fi/ui/ff/cell.lua). Asked every
" time (a font may change). When they do not know: 10x20 (the ratio of
" most fonts).
let s:cell = []
function! s:cell_pixels() abort
  if !empty(s:cell)
    return s:cell
  endif
  let cell = exists('*getcellpixels') ? getcellpixels()
        \ : has('nvim') ? luaeval('require("goda_fi.ui.ff.cell").pixels()')
        \ : v:null
  return type(cell) == v:t_list && len(cell) == 2 && cell[0] > 0 && cell[1] > 0
        \ ? cell : [10, 20]
endfunction

" The size of a cell in pixels as {width} and {height} (0: as the
" terminal says): for a test.
function! goda_fi#ui#ff#_cell_pixels(width, height) abort
  let s:cell = a:width > 0 && a:height > 0 ? [a:width, a:height] : []
  call s:place_images()
endfunction

" The size of the image of st in the area [row, col, width, height] of
" cells: as large as it is, or smaller to fit in, never stretched.
" Neovim: {'width': cells} or {'height': cells} (the terminal keeps the
" ratio of the other), {} as it is; Vim: [width, height] in pixels.
function! s:image_fit(st, area) abort
  let [cw, ch] = s:cell_pixels()
  let [iw, ih] = a:st.image_size
  let [aw, ah] = [a:area[2] * cw, a:area[3] * ch]
  " (min() is not of Floats.)
  let scale = 1.0
  for f in [aw * 1.0 / iw, ah * 1.0 / ih]
    let scale = f < scale ? f : scale
  endfor
  if !has('nvim')
    return [max([1, float2nr(iw * scale)]), max([1, float2nr(ih * scale)])]
  endif
  if scale >= 1.0
    " (As large as it is: the terminal places its pixels.)
    return {}
  endif
  " The side that limits it, in cells (not rounded up: out of the window).
  return aw * ih <= ah * iw
        \ ? {'width': max([1, float2nr(iw * scale / cw)])}
        \ : {'height': max([1, float2nr(ih * scale / ch)])}
endfunction

" Shows the image path over the preview window of st.
function! s:show_image(st, path, zindex) abort
  call s:clear_image(a:st)
  let a:st.image_path = a:path
  let a:st.image_size = s:image_size(a:path)
  let a:st.image_zindex = a:zindex
  call s:place_image(a:st)
  augroup goda-fi-ff-image
    autocmd!
    " An image is where it was put on the screen, not in a window: it goes
    " with the window when that moves (scrolled, resized, ...).
    autocmd WinScrolled,WinResized,VimResized,TabEnter * call s:place_images()
  augroup END
endfunction

" The text area of the preview window of st on the screen: [row, col,
" width, height] (1-based), or [] when it is not shown.
function! s:image_area(st) abort
  let winid = a:st.preview_winid
  if !s:preview_valid(winid)
    return []
  endif
  if !has('nvim') && win_id2win(winid) <= 0
    let pos = popup_getpos(winid)
    return empty(pos) || !pos.visible ? []
          \ : [pos.core_line, pos.core_col, pos.core_width, pos.core_height]
  endif
  let [row, col] = win_screenpos(winid)
  if row <= 0 || win_id2tabwin(winid)[0] != tabpagenr()
    " (In another tab page.)
    return []
  endif
  if has('nvim')
    " (win_screenpos() is that of its border.)
    let border = get(nvim_win_get_config(winid), 'border', [])
    if type(border) == v:t_list && !empty(border) && border != repeat([''], len(border))
      let [row, col] = [row + 1, col + 1]
    endif
  endif
  return [row, col, winwidth(winid), winheight(winid)]
endfunction

" Puts the image of st where its preview window is now, the size fitting
" in it (or hides it).
function! s:place_image(st) abort
  let area = s:image_area(a:st)
  if empty(area)
    call s:delete_image(a:st)
    return
  endif
  let fit = s:image_fit(a:st, area)
  if a:st.image_id > 0 && area == a:st.image_area && fit == a:st.image_fit
    " (Where it is: nothing sent to the terminal.)
    return
  endif
  if a:st.image_id > 0 && (has('nvim') ? keys(fit) != keys(a:st.image_fit)
        \ : fit != a:st.image_fit)
    " (Another side limits it: the size given is not that one. Vim: the
    " image is another.)
    call s:delete_image(a:st)
  endif
  let a:st.image_area = area
  let a:st.image_fit = fit
  let [row, col] = area[: 1]
  if has('nvim')
    let opts = extend({'row': row, 'col': col, 'zindex': a:st.image_zindex}, fit)
    try
      if a:st.image_id > 0
        call luaeval('vim.ui.img.set(_A[1], _A[2])', [a:st.image_id, opts])
      else
        let a:st.image_id = luaeval(
              \ 'vim.ui.img.set(vim.fn.readblob(_A[1]), _A[2])',
              \ [a:st.image_path, opts])
      endif
    catch
      call goda_fi#util#print_error(v:exception)
      call s:clear_image(a:st)
    endtry
    return
  endif
  if a:st.image_id > 0
    call popup_move(a:st.image_id, {'line': row, 'col': col})
    return
  endif
  " (Not again when it failed: s:place_images() would.)
  let rgb = tempname()
  let out = systemlist(printf('convert %s -resize %dx%d! -depth 8 rgb:%s',
        \ shellescape(a:st.image_path . '[0]'), fit[0], fit[1], shellescape(rgb)))
  if v:shell_error != 0
    call goda_fi#util#print_error(join(out, "\n"))
    call s:clear_image(a:st)
    return
  endif
  let a:st.image_id = popup_create('', {
        \ 'image': {'data': readblob(rgb), 'width': fit[0], 'height': fit[1]},
        \ 'line': row, 'col': col, 'padding': [0, 0, 0, 0],
        \ 'zindex': a:st.image_zindex})
  call delete(rgb)
endfunction

" The images of the sessions go with their preview windows.
function! s:place_images() abort
  let shown = 0
  for st in values(s:state)
    if st.image_path !=# ''
      call s:place_image(st)
      let shown = 1
    endif
  endfor
  if !shown && exists('#goda-fi-ff-image')
    autocmd! goda-fi-ff-image
  endif
endfunction

" Hides the image of st (it comes back with s:place_image()).
function! s:delete_image(st) abort
  if a:st.image_id <= 0
    return
  endif
  if has('nvim')
    call luaeval('vim.ui.img.del(_A)', a:st.image_id)
  else
    call popup_close(a:st.image_id)
  endif
  let a:st.image_id = -1
endfunction

" Removes the image of st.
function! s:clear_image(st) abort
  call s:delete_image(a:st)
  let a:st.image_path = ''
endfunction

function! s:open_preview_split(ffwin, bufnr, p) abort
  let cur = win_getid()
  call win_gotoid(a:ffwin)
  if a:p.previewSplit ==# 'vertical'
    execute 'silent rightbelow vertical sbuffer' a:bufnr
    setlocal winfixwidth
    execute 'vertical resize' s:eval(a:p.previewWidth, a:p)
  else
    " No more than 4/10 of the screen.
    let height = min([s:eval(a:p.previewHeight, a:p), &lines * 4 / 10])
    execute 'silent aboveleft sbuffer' a:bufnr
    setlocal winfixheight
    execute 'resize' height
  endif
  let winid = win_getid()
  call win_gotoid(cur)
  return winid
endfunction

" A floating window (Neovim) or a popup (Vim) beside the window of the
" items, as ddu-ui-ff's previewFloating.
function! s:open_preview_float(ffwin, bufnr, p) abort
  let width = s:eval(a:p.previewWidth, a:p)
  let height = s:eval(a:p.previewHeight, a:p)
  let row_param = s:eval(get(a:p, 'previewRow', 0), a:p)
  let col_param = s:eval(get(a:p, 'previewCol', 0), a:p)
  let border = get(a:p, 'previewFloatingBorder', 'none')
  let [row, col] = win_screenpos(a:ffwin)
  let row = row_param > 0 ? row_param : row - 1
  let col = col_param > 0 ? col_param : col - 1
  let anchor = 'NW'
  if a:p.previewSplit ==# 'vertical'
    if row_param <= 0 && row <= height
      let col += winwidth(a:ffwin)
      if col + width > &columns
        let col -= width
      endif
    endif
    if col_param <= 0 && border isnot# 'none'
      let width -= 1
    endif
  else
    if row_param <= 0 && border isnot# 'none'
      let height -= 1
    endif
    if row_param <= 0 && row <= height
      let row += winheight(a:ffwin) + 1
    elseif has('nvim')
      let anchor = 'SW'
    else
      let row -= height + 2
    endif
  endif
  let width = max([1, width])
  let height = max([1, height])
  let title = get(a:p, 'previewFloatingTitle', '')
  if has('nvim')
    let opts = {'relative': 'editor', 'anchor': anchor, 'row': row, 'col': col,
          \ 'width': width, 'height': height, 'border': border,
          \ 'zindex': get(a:p, 'previewFloatingZindex', 100)}
    if !empty(title)
      let opts.title = title
      let opts.title_pos = get(a:p, 'previewFloatingTitlePos', 'left')
    endif
    let winid = nvim_open_win(a:bufnr, v:false, opts)
    call setwinvar(winid, '&winblend', get(a:p, 'floatingBlend', 0))
    return winid
  endif
  let opts = {'pos': 'topleft', 'posinvert': v:false,
        \ 'line': max([1, row + 1]), 'col': max([1, col + 1]),
        \ 'minwidth': width, 'maxwidth': width,
        \ 'minheight': height, 'maxheight': height,
        \ 'highlight': 'Normal', 'scrollbar': 0, 'wrap': 0,
        \ 'zindex': get(a:p, 'previewFloatingZindex', 100)}
  if border isnot# 'none' && !empty(border)
    let opts.border = []
  endif
  if type(title) == v:t_string && title !=# ''
    let opts.title = title
  endif
  return popup_create(a:bufnr, opts)
endfunction

" The lines of a previewer, and the path they are of.
function! s:preview_lines(pv, p) abort
  if a:pv.kind ==# 'nofile'
    return [get(a:pv, 'contents', []), '']
  endif
  if a:pv.kind !=# 'buffer'
    return [['(no preview of ' . a:pv.kind . ')'], '']
  endif
  let expr = get(a:pv, 'expr', v:null)
  if expr isnot v:null && bufexists(expr)
    let bufnr = type(expr) == v:t_number ? expr : bufnr(expr)
    call bufload(bufnr)
    return [getbufline(bufnr, 1, '$'), bufname(bufnr)]
  endif
  let path = get(a:pv, 'path', '')
  if bufloaded(path)
    return [getbufline(bufnr(path), 1, '$'), path]
  endif
  if isdirectory(path)
    return [readdir(path), '']
  endif
  if !filereadable(path)
    return [['(cannot read ' . path . ')'], '']
  endif
  if getfsize(path) > a:p.maxSize
    return [['(too large: ' . path . ')'], '']
  endif
  let lines = readfile(path, '', 10000)
  " A NUL is a newline in what readfile() reads.
  if match(lines[: 100], "\n") >= 0
    return [['(binary: ' . path . ')'], '']
  endif
  return [lines, path]
endfunction
