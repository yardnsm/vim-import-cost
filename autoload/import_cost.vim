
let s:plug = expand("<sfile>:p:h:h")
let s:script_path = s:plug . '/src/index.js'

let s:scratch_buffer_name = '__Import_Cost__'

let s:cursorbind_backup = 0
let s:scrollbind_backup = 0

" Reset buffer sync after quitting
augroup import_cost_scratch_buffer
  autocmd!

  autocmd BufWinLeave __Import_Cost__ call s:ResetBufferSync()
augroup END

" Utility functions {{{

" Echo an error message
function! s:EchoError(msg)
  echohl Error
  echom 'vim-import-cost: ' . a:msg
  echohl None
endfunction

" Pretty format a size in bytes
function! s:PrettyFormatSize(size)
  return string(a:size / 1024) . ' KB'
endfunction

" }}}
" Buffer syncing {{{

" Enable buffer sync (cursorbind and scrollbind essentially)
function! s:EnableBufferSync()
  let s:cursorbind_backup = &l:cursorbind
  let s:scrollbind_backup = &l:scrollbind

  let w:import_cost_buffer_sync = 1

  set cursorbind
  set scrollbind
endfunction

" Reset buffer sync in all the matching buffers
function! s:ResetBufferSync()

  " Loop through all the windows and reset the settings if required
  let l:currwin = winnr()
  for nr in range(1, winnr('$'))
    if getwinvar(nr, 'import_cost_buffer_sync') && nr != winnr()
      execute nr . 'wincmd w'

      let &l:cursorbind = s:cursorbind_backup
      let &l:scrollbind = s:scrollbind_backup
    endif
  endfor
  execute l:currwin . 'wincmd w'
endfunction

" }}}
" Scratch buffer {{{

" Create a new empty scratch buffer, or focus on the currently opened one
function! s:CreateScratchBuffer()

  " Bind cursor and scrolling
  call s:EnableBufferSync()

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
function! s:FillScratchBuffer(imports, num_lines)
  " Appending empty lines to the buffer
  call append(0, map(range(a:num_lines), '""'))

  " Appending the imports
  for import in a:imports
    call append(import['line'] - 1, s:CreateImportString(import))
  endfor

  " Clear extra blank lines
  silent! %substitute#\($\n\)\+\%$##
endfunction

" }}}
" Imports parsing {{{

" Parse a single import
function! s:ParseSingleImport(key, val)
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
function! s:CreateImportString(import)
  let l:raw_size = s:PrettyFormatSize(a:import['size'])
  let l:gzipped_size = s:PrettyFormatSize(a:import['gzip'])

  let l:str = ':' . a:import['name'] . ': ' . l:raw_size

  if g:import_cost_show_gzipped == 1
    let l:str .= ' (gzipped: ' . l:gzipped_size . ')'
  endif

  return l:str
endfunction

" Execute the import-cost script on a given content
" Returns a list if the command was successful, and a string if there was an
" error
function! s:ExecuteImportCost(file_type, file_path, file_contents)
  let l:command = join(['node', s:script_path, a:file_type, a:file_path], ' ')
  let l:result = system(l:command, a:file_contents)

  " Check for errors
  if l:result =~ '\v^\[error\]'
    return l:result
  endif

  let l:imports = map(split(l:result, '\n'), function('s:ParseSingleImport'))

  return l:imports
endfunction

" }}}
" Main functionality {{{

" Execute the script for the enite buffer
function! import_cost#ShowImportCostForCurrentBuffer()
  let l:file_type = &filetype
  let l:file_path = expand("%:p")
  let l:buffer_number = bufnr('%')
  let l:buffer_lines = line('$')

  echo 'Calculating... (press ^C to terminate)'

  let l:imports = s:ExecuteImportCost(l:file_type, l:file_path, l:buffer_number)
  let l:imports_length = len(l:imports)

  " If we got a string, it should be an error
  if type(l:imports) == 1
    call s:EchoError(l:imports)
    return
  endif

  " If we've got a single import, echo it instead of creating a new scratch
  " buffer (if needed)
  if l:imports_length == 1 && g:import_cost_always_open_split != 1
    echo s:CreateImportString(l:imports[0])
    return
  endif

  redraw
  echo 'Got ' . len(l:imports) . ' results.'

  " Create a new scratch buffer and fill it
  if l:imports_length > 0
    call s:CreateScratchBuffer()
    call s:FillScratchBuffer(l:imports, l:buffer_lines)
  endif
endfunction

" }}}
