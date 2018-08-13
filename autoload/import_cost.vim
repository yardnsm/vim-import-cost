let s:plug = expand("<sfile>:p:h:h")
let s:script_path = s:plug . '/src/index.js'

let s:scratch_buffer_name = '__Import_Cost__'

" Echo an error message
function! import_cost#EchoError(msg)
  echohl Error
  echo 'vim-import-cost: ' . a:msg
  echohl None
endfunction

" Pretty format a size in bytes
"   1024 --> '1 KB'
function! import_cost#PrettyFormatSize(size)
  return string(a:size / 1024) . ' KB'
endfunction

" Parse a single import:
"   'react,3,500,200' --> {name: 'react', line: '3', size: '500', gzip: '200'}
function! import_cost#ParseSingleImport(key, val)
  let l:parts = split(a:val, ',')

  if len(l:parts) != 4
    return ''
  endif

  let l:name = l:parts[0]
  let l:line = l:parts[1]
  let l:size = l:parts[2]
  let l:gzip = l:parts[3]

  return {
    \ 'name': l:name,
    \ 'line': l:line,
    \ 'size': l:size,
    \ 'gzip': l:gzip,
    \ }
endfunction

" Create an import string from an import data
function! import_cost#CreateImportString(import)
  let l:raw_size = import_cost#PrettyFormatSize(a:import['size'])
  let l:gzipped_size = import_cost#PrettyFormatSize(a:import['gzip'])

  let l:str = ':' . a:import['name'] . ': ' . l:raw_size

  if g:import_cost_show_gzipped == 1
    let l:str .= ' (gzipped: ' . l:gzipped_size . ')'
  endif

  return l:str
endfunction

" Execute the import-cost script on a given content
function! import_cost#ExecuteImportCost(file_type, file_path, file_contents)
  let l:command = join(['node', s:script_path, a:file_type, a:file_path], ' ')
  let l:result = system(l:command, a:file_contents)

  " Check for errors
  if l:result =~ '\v^\[error\]'
    return l:result
  endif

  let l:imports = map(split(l:result, '\n'), function('import_cost#ParseSingleImport'))

  return l:imports
endfunction

" Create a new empty scratch buffer, or focus on the currently opened one
function! import_cost#CreateScratchBuffer()

  " Bind cursor and scrolling
  " TODO: reset after closing
  set cursorbind
  set scrollbind

  " Check if the split is already open
  let win = bufwinnr('^' . s:scratch_buffer_name . '$')
  if win >= 0
    execute win . "wincmd w"
  else

    " Create the split
    let l:split_command = g:import_cost_split_pos ==# 'right' ? 'botright' : 'topleft'
    execute 'silent! ' . l:split_command . ' vsplit ' . s:scratch_buffer_name

    " Resize split
    if g:import_cost_split_size != 0
      execute 'vertical resize ' . g:import_cost_split_size
    endif
  end

  " Clear contents
  normal! ggdG

  setlocal filetype=importcost
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nowrap

  " Fast quitting
  nnoremap <buffer> <silent> q :<C-U>bdelete<CR>
endfunction

" Fill the scratch buffer with imports
" Asumming we're in the scratch buffer...
function! import_cost#FillScratchBuffer(imports)
  " Appending empty lines to the buffer
  call append(0, map(range(line('$')), '""'))

  " Appending the imports
  for import in a:imports
    call append(import['line'] - 1, import_cost#CreateImportString(import))
  endfor

  " Clear extra blank lines
  silent! %substitute#\($\n\)\+\%$##
endfunction

function! import_cost#ShowImportCostForCurrentBuffer()
  let l:file_type = &filetype
  let l:file_path = expand("%:p")
  let l:buffer_number = bufnr('%')

  echo 'Calculating...'

  let l:imports = import_cost#ExecuteImportCost(l:file_type, l:file_path, l:buffer_number)

  " If we got a string, it should be an error
  if type(l:imports) == 1
    call import_cost#EchoError(l:imports)
    return
  endif

  " If we've got a single import, echo it instead of creating a new scratch
  " buffer
  if len(l:imports) == 1 && g:import_cost_always_open_split != 1
    echo import_cost#CreateImportString(l:imports[0])
    return
  endif

  " Create a new scratch buffer and fill it
  call import_cost#CreateScratchBuffer()
  call import_cost#FillScratchBuffer(l:imports)
endfunction
