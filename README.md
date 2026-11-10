# goda-fi-ui-ff.vim

The UI `ff` of [goda-fi.vim](https://github.com/Shougo/goda-fi.vim), as
ddu-ui-ff: the items in a buffer of a split window, filtered from the command
line.

## Requirements

- [goda-fi.vim](https://github.com/Shougo/goda-fi.vim)

## Usage

Add it in the configuration of goda-fi.vim:

```go
import "github.com/Shougo/goda-fi-ui-ff.vim/ui/ff"

b.AddUI(ff.New())
```

Then:

```vim
call goda_fi#start(#{ui: 'ff', sources: ['filerec']})
```

See `:help goda-fi-ui-ff`.

[goda-fi-ui-filer.vim](https://github.com/Shougo/goda-fi-ui-filer.vim) is made
of it (`ff.NewUI()`).
