if exists('b:current_syntax')
    finish
endif

" Module name
syntax match importCostModule "\v^(.){-}\:"
highlight link importCostModule Statement

" Size
syntax match importCostSize "\v(\d)+(\a){2}"
highlight link importCostSize Label

" Gzipped size
syntax match importCostGzipped "\v\(.*\)"
highlight link importCostGzipped Boolean

let b:current_syntax = 'importcost'
