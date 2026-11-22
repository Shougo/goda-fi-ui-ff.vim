vim9script

# The highlights of the items on Vim, for s:highlight() of
# autoload/goda_fi/ui/ff.vim: the loop over them in Vim9 script, the text
# properties of a type added together (Neovim has
# lua/goda_fi/ui/ff/highlight.lua).

# The prop types made: "goda_fi_{group}_{priority}".
var prop_types: dict<bool> = {}

# The prop type of the group and the priority (made the first time).
export def PropType(group: string, priority: number): string
  var name = 'goda_fi_' .. group .. '_' .. priority
  if !has_key(prop_types, name)
    if empty(prop_type_get(name))
      var opts: dict<any> = {priority: priority, override: true}
      if group !=# ''
        opts.highlight = group
      endif
      prop_type_add(name, opts)
    endif
    prop_types[name] = true
  endif
  return name
enddef

# Add the highlights [row, col, length, group, priority] of the lines to
# bufnr. A group that does not exist and a column past the end of its line
# are skipped; a length of 0 or past the end goes to the end.
export def Add(bufnr: number, lines: list<string>, highlights: list<any>)
  var valid: dict<bool> = {}
  var ranges: dict<list<any>> = {}
  for [row, col, length, group, priority] in highlights
    if !has_key(valid, group)
      valid[group] = hlexists(group) != 0
    endif
    var text: string = get(lines, row - 1, '')
    if !valid[group] || col > strlen(text)
      continue
    endif
    var size: number = length <= 0 || col + length - 1 > strlen(text)
      ? strlen(text) - col + 1 : length
    var type = PropType(group, priority)
    if !has_key(ranges, type)
      ranges[type] = []
    endif
    add(ranges[type], [row, col, row, col + size])
  endfor
  for [type, l] in items(ranges)
    prop_add_list({bufnr: bufnr, type: type}, l)
  endfor
enddef
