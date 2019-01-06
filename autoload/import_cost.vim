let s:plug = expand("<sfile>:p:h:h")
let s:script_path = s:plug . '/src/index.js'

" Outputs of the import cost script
let s:import_cost_stdout = ''
let s:import_cost_stderr = ''

" Current running async job
let s:import_cost_job_id = 0

" The staring line of a range
let s:range_start_line = 0

" Utility functions {{{

" Echo an error message
function! s:EchoError(msg)
  echohl Error
  echom 'vim-import-cost: ' . a:msg
  echohl None
endfunction

" What renderer to use?
function! s:GetRendererName()
  if g:import_cost_virtualtext && import_cost#virtual_text#IsSupported()
    return 'virtual_text'
  endif

  return 'scratch_buffer'
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

function! s:OnScriptFinish()

  " Clear if needed
  if s:GetRendererName() ==# 'virtual_text'
    call import_cost#virtual_text#Clear()
  endif

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
    echom import_cost#utils#CreateImportString(l:imports[0], 1)
    return
  endif

  if l:imports_length > 0

    if s:GetRendererName() ==# 'virtual_text'

      " Use the virtual_text renderer
      call import_cost#virtual_text#Render(l:imports, s:range_start_line, s:buffer_lines)
    else

      " Use a scratch buffer and echo the result message
      call import_cost#scratch_buffer#Render(l:imports, s:range_start_line, s:buffer_lines)
      echom l:result_message
    endif
  endif
endfunction

" }}}
" Async functionality {{{

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

" }}}
" Sync functionality {{{

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

" }}}
" Main functionality {{{

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

function! import_cost#ImportCostClear(ranged, line_1, line_2)
  if s:GetRendererName() !=# 'virtual_text'
    return
  endif

  if a:ranged
    call import_cost#virtual_text#ClearRange(a:line_1 - 1, a:line_2)
  else
    call import_cost#virtual_text#Clear()
  endif
endfunction

" }}}
