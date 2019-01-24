let s:scratch_buffer_name = '__Import_Cost__'

" Keeping the previous state of these options for resetting the buffer syncing
let s:cursorbind_backup = 0
let s:scrollbind_backup = 0

" Is the scratch buffer open?
let s:scratch_buffer_open = 0

let s:autocmds_set = 0

function! import_cost#scratch_buffer#Render(imports, range_start_line, buffer_lines)

  " Set autocmds
  call s:SetAutocommands()

  let l:current_buffer_name = bufname('%')
  normal m'

  call s:CreateScratchBuffer()
  call s:FillScratchBuffer(a:imports, a:range_start_line, a:buffer_lines)

  " We'll keep the total size string within the scratch buffer
  let b:total_size_string = s:CreateTotalSizeString(a:imports)

  execute bufwinnr(l:current_buffer_name) . 'wincmd w'
  normal ''
endfunction

" Autocommands {{{

function! s:SetAutocommands()
  if s:autocmds_set
    return
  endif

  augroup import_cost_scratch_buffer
    autocmd!

    " Reset buffer sync after quitting
    autocmd BufWinLeave __Import_Cost__ call s:ResetBufferSyncForAllBuffers()
    autocmd BufWinEnter *               call s:ResetBufferSyncForCurrentBuffer()

    " Set open state
    autocmd BufWinEnter __Import_Cost__ let s:scratch_buffer_open = 1
    autocmd BufWinLeave __Import_Cost__ let s:scratch_buffer_open = 0
  augroup END

  let s:autocmds_set = 1

endfunction

" }}}
" Mappings {{{

" Setup mappings for the scratch buffer
function! s:SetupScratchBufferMappings()

  " Fast quitting
  nnoremap <buffer> <silent> q :<C-U>bdelete<CR>

  " Show total size
  nnoremap <buffer> <silent> s :<C-U>echom b:total_size_string<CR>
endfunction

" }}}
" Imports parsing {{{

" This function takes the imports data and returns a string containing data
" about the total size
function! s:CreateTotalSizeString(imports)
  let l:size = 0
  let l:gzip = 0

  for import in a:imports
    let l:size = l:size + import['size']
    let l:gzip = l:gzip + import['gzip']
  endfor

  return import_cost#utils#CreateImportString({
        \ 'name': 'Total size',
        \ 'size': l:size,
        \ 'gzip': l:gzip,
        \ }, 1)
endfunction

" }}}
" Buffer syncing {{{

" Enable buffer sync (cursorbind and scrollbind essentially)
function! s:EnableBufferSyncForCurrentBuffer()
  let s:cursorbind_backup = &l:cursorbind
  let s:scrollbind_backup = &l:scrollbind

  let w:import_cost_buffer_sync = 1

  set cursorbind
  set scrollbind
endfunction

" Reset buffer sync for the current buffer
function! s:ResetBufferSyncForCurrentBuffer()
  if s:scratch_buffer_open
    let &l:cursorbind = s:cursorbind_backup
    let &l:scrollbind = s:scrollbind_backup
  endif
endfunction

" Reset buffer sync in all the matching buffers
function! s:ResetBufferSyncForAllBuffers()

  " Loop through all the windows and reset the settings if required
  let l:currwin = winnr()
  for nr in range(1, winnr('$'))
    if getwinvar(nr, 'import_cost_buffer_sync') && nr != winnr()
      execute nr . 'wincmd w'

      let &l:cursorbind = s:cursorbind_backup
      let &l:scrollbind = s:scrollbind_backup

      unlet w:import_cost_buffer_sync
    endif
  endfor
  execute l:currwin . 'wincmd w'
endfunction

" }}}
" Scratch buffer {{{

" Create a new empty scratch buffer, or focus on the currently opened one
function! s:CreateScratchBuffer()

  " Bind cursor and scrolling
  call s:EnableBufferSyncForCurrentBuffer()

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

  " 'Unlock' the buffer
  set noreadonly
  set modifiable

  " Clear contents
  normal! gg"_dG

  setlocal filetype=importcost
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nowrap

  " Setup mappings
  call s:SetupScratchBufferMappings()
endfunction

" Fill the scratch buffer with imports
" Asumming we're in the scratch buffer...
function! s:FillScratchBuffer(imports, range_start_line, buffer_lines)

  " Appending empty lines to the buffer
  call append(0, map(range(a:buffer_lines), '""'))

  " Appending the imports
  for import in a:imports
    call append(import['line'] + a:range_start_line - 1, import_cost#utils#CreateImportString(import, 1))
  endfor

  " Clear extra blank lines
  silent! %substitute#\($\n\)\+\%$##

  " 'Lock' the buffer
  set readonly
  set nomodifiable
endfunction

" }}}
