let s:plug = expand("<sfile>:p:h:h")
let s:script_path = s:plug . '/src/index.js'

" Current running async job
let s:import_cost_job_id = 0

" The staring line of a range
let s:range_start_line = 0

" Utility functions {{{

" Echo an error message
function! s:EchoError(msg)
  if g:import_cost_silent
    return
  endif

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
" Events handling {{{

function! s:OnEvent(buffer, type, payload)

  " Got an error
  if a:type ==# 'error'
    if s:GetRendererName() ==# 'virtual_text'
      call import_cost#virtual_text#Clear(a:buffer)
    endif

    call s:EchoError(a:payload)
    return
  endif

  " Got a list of imports, no sizes yet. Just show a message next to each import.
  " Only for the virtual_text renderer
  if a:type ==# 'start'
    if s:GetRendererName() ==# 'virtual_text'
      let l:imports = a:payload

      " Clear previous virtualtext and set imports
      call import_cost#virtual_text#Clear(a:buffer)
      call import_cost#virtual_text#Render(a:buffer, l:imports, s:range_start_line, s:buffer_lines)
    endif

    return
  endif

  " Got a single import data
  " Only for the virtual_text renderer
  if a:type ==# 'calculated'
    if s:GetRendererName() ==# 'virtual_text'
      let l:imports = a:payload

      " Set new import
      call import_cost#virtual_text#Render(a:buffer, l:imports, s:range_start_line, s:buffer_lines)
    endif

    return
  endif

  " Got all imports
  if a:type ==# 'done'

    let l:imports = a:payload

    let l:imports_length = len(l:imports)
    let l:result_message = 'Got ' . l:imports_length . ' results.'

    if l:imports_length > 0

      if s:GetRendererName() ==# 'virtual_text'

        " Use the virtual_text renderer
        call import_cost#virtual_text#Clear(a:buffer)
        call import_cost#virtual_text#Render(a:buffer, l:imports, s:range_start_line, s:buffer_lines)
      else

        " If we've got a single import, echo it instead of creating a new scratch
        " buffer (if needed)
        if l:imports_length == 1 && g:import_cost_always_open_split != 1
          echom import_cost#utils#CreateImportString(l:imports[0], 1)
        else

          " Use a scratch buffer and echo the result message
          call import_cost#scratch_buffer#Render(a:buffer, l:imports, s:range_start_line, s:buffer_lines)
          echom l:result_message
        endif
      endif
    endif
  endif
endfunction

" }}}
" Async functionality {{{

" Execute the script asynchronously
function! s:ExecuteImportCostAsync(file_type, file_path, file_contents)
  let l:command = ['node', s:script_path, a:file_type, a:file_path]
  let l:buffer = bufnr('')

  " Async job callback
  function! s:AsyncJobCallback(data, event) closure
    if a:event ==# 'stdout'
      let l:json = json_decode(a:data)
      call s:OnEvent(l:buffer, l:json['type'], l:json['payload'])
    endif
  endfunction


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
  let buffer = bufnr('')

  echo 'Calculating... (press ^C to terminate)'

  let l:command = join(['node', s:script_path, a:file_type, a:file_path], ' ')
  let l:result = system(l:command, a:file_contents)

  " We'll only care for the last result
  let l:json = json_decode(split(l:result, "\n")[-1])

  " Clear last message
  redraw

  call s:OnEvent(l:buffer, l:json['type'], l:json['payload'])
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
  let buffer = bufnr('')
  if s:GetRendererName() !=# 'virtual_text'
    return
  endif

  if a:ranged
    call import_cost#virtual_text#ClearRange(a:buffer, a:line_1 - 1, a:line_2)
  else
    call import_cost#virtual_text#Clear(a:buffer)
  endif
endfunction

" }}}
