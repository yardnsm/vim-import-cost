let s:plug = expand("<sfile>:p:h:h")
let s:script_path = s:plug . '/src/index.js'

let s:scratch_buffer_name = '__Import_Cost__'

" Keeping the previous state of these options for resetting the buffer syncing
let s:cursorbind_backup = 0
let s:scrollbind_backup = 0

" Outputs of the import cost script
let s:import_cost_stdout = ''
let s:import_cost_stderr = ''

let s:import_cost_job_id = 0

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

" Async job callback
function! s:OnEvent(job_id, data, event) dict
  if a:event == 'stdout'
    let s:import_cost_stdout .= join(a:data)
  elseif a:event == 'stderr'
    if join(a:data) =~ '\v^\[error\]'
      let s:import_cost_stderr .= join(a:data)
    endif
  else
    call s:OnScriptFinish()
  endif
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

  let l:imports = map(split(s:import_cost_stdout, ' '), function('s:ParseSingleImport'))
  call filter(l:imports, 'len(v:val)')

  let l:imports_length = len(l:imports)

  " If we've got a single import, echo it instead of creating a new scratch
  " buffer (if needed)
  if l:imports_length == 1 && g:import_cost_always_open_split != 1
    echom s:CreateImportString(l:imports[0])
    return
  endif

  echo 'Got ' . l:imports_length . ' results.'

  " Create a new scratch buffer and fill it
  " Keep the focus on the currently opened buffer
  if l:imports_length > 0
    let l:current_buffer_name = bufname('.')
    normal m'

    call s:CreateScratchBuffer()
    call s:FillScratchBuffer(l:imports, s:range_start_line, s:buffer_lines)

    execute bufwinnr(l:current_buffer_name) . 'wincmd w'
    normal ''
  endif
endfunction

let s:callbacks = {
      \ 'on_stdout': function('s:OnEvent'),
      \ 'on_stderr': function('s:OnEvent'),
      \ 'on_exit': function('s:OnEvent')
      \ }

function! s:ExecuteImportCostAsync(file_type, file_path, file_contents)
  let l:command_args = ['node', s:script_path, a:file_type, a:file_path]

  " Kill last job
  silent! call jobstop(s:import_cost_job_id)

  " Start the job
  let s:import_cost_job_id = jobstart(l:command_args, extend({'shell': 'import_cost_shell'}, s:callbacks))

  " Send the file contents and close the stdin channel
  call chansend(s:import_cost_job_id, a:file_contents)
  call chanclose(s:import_cost_job_id, 'stdin')
endfunction

function! s:ExecuteImportCostSync(file_type, file_path, file_contents)

  echo 'Calculating... (press ^C to terminate)'

  let l:command = join(['node', s:script_path, a:file_type, a:file_path], ' ')
  let l:result = system(l:command, a:file_contents)

  " Check for errors
  if l:result =~ '\v^\[error\]'
    let s:import_cost_stderr = l:result
  else
    let s:import_cost_stdout = join(split(l:result, '\n'), ' ')
  endif

  " Clear last message
  redraw

  call s:OnScriptFinish()
endfunction

" }}}
" Main functionality {{{

function! import_cost#ImportCost(ranged, line_1, line_2)
  let l:file_type = &filetype
  let l:file_path = expand("%:p")

  let l:buffer_content = bufnr('%')
  let s:buffer_lines = line('$')

  let s:range_start_line = 0

  " Reset previous results
  let s:import_cost_stdout = ''
  let s:import_cost_stderr = ''

  if a:ranged

    " Get selected lines
    let l:buffer_content = join(getline(a:line_1, a:line_2), "\n")
    let s:range_start_line = a:line_1 - 1
  endif

  call s:ExecuteImportCostAsync(l:file_type, l:file_path, l:buffer_content)
  return
endfunction

" }}}
