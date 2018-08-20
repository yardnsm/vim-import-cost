let s:plug = expand("<sfile>:p:h:h")
let s:script_path = s:plug . '/src/index.js'

let s:scratch_buffer_name = '__Import_Cost__'

" Keeping the previous state of these options for resetting the buffer syncing
let s:cursorbind_backup = 0
let s:scrollbind_backup = 0

" Outputs of the import cost script
let s:import_cost_stdout = ''
let s:import_cost_stderr = ''

" Current running async job
let s:import_cost_job_id = 0

" The staring line of a range
let s:range_start_line = 0

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
  let l:pretty_size = a:size / 1000.0
  let l:unit = 'KB'

  if l:pretty_size >= 1000
    let l:pretty_size = l:pretty_size / 1000
    let l:unit = 'MB'
  endif

  return printf('%.0f', l:pretty_size) . l:unit
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

  " Fast quitting
  nnoremap <buffer> <silent> q :<C-U>bdelete<CR>

  " Show total size
  nnoremap <buffer> <silent> s :<C-U>echom b:total_size_string<CR>
endfunction

" Fill the scratch buffer with imports
" Asumming we're in the scratch buffer...
function! s:FillScratchBuffer(imports, start_line, num_lines)

  " Appending empty lines to the buffer
  call append(0, map(range(a:num_lines), '""'))

  " Appending the imports
  for import in a:imports
    call append(import['line'] + a:start_line - 1, s:CreateImportString(import))
  endfor

  " Clear extra blank lines
  silent! %substitute#\($\n\)\+\%$##

  " 'Lock' the buffer
  set readonly
  set nomodifiable
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

  let l:str = a:import['name'] . ': ' . l:raw_size

  if g:import_cost_show_gzipped == 1
    let l:str .= ' (gzipped: ' . l:gzipped_size . ')'
  endif

  return l:str
endfunction

" This function takes the imports data and returns a string containing data
" about the total size
function! s:CreateTotalSizeString(imports)
  let l:size = 0
  let l:gzip = 0

  for import in a:imports
    let l:size = l:size + import['size']
    let l:gzip = l:gzip + import['gzip']
  endfor

  return s:CreateImportString({
        \ 'name': 'Total size',
        \ 'size': l:size,
        \ 'gzip': l:gzip,
        \ })
endfunction

function! s:OnScriptFinish()

  " Check for errors
  if len(s:import_cost_stderr)
    call s:EchoError(s:import_cost_stderr)
    return
  endif

  " If we got nothing, do nothing
  if !len(s:import_cost_stdout)
    return
  endif

  let l:imports = map(split(s:import_cost_stdout, '\n'), function('s:ParseSingleImport'))
  call filter(l:imports, 'len(v:val)')

  let l:imports_length = len(l:imports)
  let l:result_message = 'Got ' . l:imports_length . ' results.'

  " If we've got a single import, echo it instead of creating a new scratch
  " buffer (if needed)
  if l:imports_length == 1 && g:import_cost_always_open_split != 1
    echom s:CreateImportString(l:imports[0])
    return
  endif

  " Create a new scratch buffer and fill it
  " Keep the focus on the currently opened buffer
  if l:imports_length > 0
    let l:current_buffer_name = bufname('.')
    normal m'

    call s:CreateScratchBuffer()
    call s:FillScratchBuffer(l:imports, s:range_start_line, s:buffer_lines)

    " We'll keep the total size string within the scratch buffer
    let b:total_size_string = s:CreateTotalSizeString(l:imports)
    let l:result_message .= ' ' . b:total_size_string

    execute bufwinnr(l:current_buffer_name) . 'wincmd w'
    normal ''
  endif

  echom l:result_message
endfunction

" }}}
" Main functionality {{{

" Async job callback
function! s:AsyncJobCallback(data, event)
  if a:event ==# 'stdout'
    let s:import_cost_stdout .= a:data
  elseif a:event ==# 'stderr' && a:data =~# '\v^\[error\]'
    let s:import_cost_stderr .= a:data
  elseif a:event ==# 'exit'
    call s:OnScriptFinish()
  endif
endfunction

" Execute the script asynchronously
function! s:ExecuteImportCostAsync(file_type, file_path, file_contents)
  let l:command = ['node', s:script_path, a:file_type, a:file_path]

  " Kill last job
  silent! call import_cost#async#job_stop(s:import_cost_job_id)

  " Start the job
  let s:import_cost_job_id = import_cost#async#job_start(l:command,
        \ function('s:AsyncJobCallback'))

  " Send the file contents and close the stdin channel
  call import_cost#async#job_send(s:import_cost_job_id, a:file_contents)
  call import_cost#async#job_close(s:import_cost_job_id)
endfunction

" Execute the script synchronously
function! s:ExecuteImportCostSync(file_type, file_path, file_contents)

  echo 'Calculating... (press ^C to terminate)'

  let l:command = join(['node', s:script_path, a:file_type, a:file_path], ' ')
  let l:result = system(l:command, a:file_contents)

  " Check for errors
  if l:result =~ '\v^\[error\]'
    let s:import_cost_stderr = l:result
  else
    let s:import_cost_stdout = l:result
  endif

  " Clear last message
  redraw

  call s:OnScriptFinish()
endfunction

function! import_cost#ImportCost(ranged, line_1, line_2)
  let l:file_type = &filetype
  let l:file_path = expand("%:p")

  let l:buffer_content = ''
  let s:buffer_lines = line('$')

  " Reset previous results
  let s:import_cost_stdout = ''
  let s:import_cost_stderr = ''
  let s:range_start_line = 0

  if a:ranged

    " Get selected lines
    let l:buffer_content = join(getline(a:line_1, a:line_2), "\n")
    let s:range_start_line = a:line_1 - 1
  else
    let l:buffer_content = join(getline(1, '$'), "\n")
  endif

  if import_cost#async#is_supported() && !g:import_cost_disable_async
    call s:ExecuteImportCostAsync(l:file_type, l:file_path, l:buffer_content)
  else
    call s:ExecuteImportCostSync(l:file_type, l:file_path, l:buffer_content)
  endif
endfunction

" }}}
