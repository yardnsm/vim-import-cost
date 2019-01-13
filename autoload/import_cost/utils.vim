" Utils {{{

" Pretty format a size in bytes
function! import_cost#utils#PrettyFormatSize(size)
  let l:pretty_size = a:size / 1000.0
  let l:unit = 'KB'

  if l:pretty_size >= 1000
    let l:pretty_size = l:pretty_size / 1000
    let l:unit = 'MB'
  endif

  return printf('%.0f', l:pretty_size) . l:unit
endfunction

" Create an import string from an import data
function! import_cost#utils#CreateImportString(import, show_name)
  if a:import['size'] == -1
    return 'Calculating...'
  endif

  let l:raw_size = import_cost#utils#PrettyFormatSize(a:import['size'])
  let l:gzipped_size = import_cost#utils#PrettyFormatSize(a:import['gzip'])

  if a:show_name
    let l:str = a:import['name'] . ': ' . l:raw_size
  else
    let l:str = l:raw_size
  endif

  if g:import_cost_show_gzipped == 1
    let l:str .= ' (gzipped: ' . l:gzipped_size . ')'
  endif

  return l:str
endfunction

" }}}
