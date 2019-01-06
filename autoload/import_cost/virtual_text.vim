let s:virtual_text_namespace = nvim_create_namespace('import_cost')

function! import_cost#virtual_text#Render(imports, start_line, num_lines)

  " Clear!
  call import_cost#virtual_text#Clear()

  " Render it!
  call s:SetVirtualText(a:imports, a:start_line, a:num_lines)
endfunction

" Clear the virtual text
function! import_cost#virtual_text#Clear()
  let l:buffer = bufnr('')
  call nvim_buf_clear_namespace(l:buffer, s:virtual_text_namespace, 0, -1)
endfunction

" Feature support {{{

" Check if virtualtext is supported
function! import_cost#virtual_text#IsSupported()
    return has('nvim-0.3.2')
endfunction

" }}}
" Virtual text {{{

function! s:SetVirtualText(imports, range_start_line, buffer_lines) abort
  let l:hl_group = 'ImportCostVirtualText'
  let l:prefix = g:import_cost_virtualtext_prefix

  let l:buffer = bufnr('')

  for import in a:imports
    let l:message = l:prefix . import_cost#utils#CreateImportString(import, 0)
    let l:line = import['line'] + a:range_start_line - 1

    call nvim_buf_set_virtual_text(l:buffer,
          \ s:virtual_text_namespace,
          \ l:line,
          \ [[ l:message, l:hl_group ]],
          \ {})
  endfor
endfunction

" }}}