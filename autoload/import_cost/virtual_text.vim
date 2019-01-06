

function! import_cost#virtual_text:Render(imports, start_line, num_lines)

endfunction

" Clear the virtual text
function! import_cost#virtual_text:Clear(imports, start_line, num_lines)
  let l:buffer = bufnr('')
  call nvim_buf_clear_highlight(l:buffer, 1000, 0, -1)
endfunction

" Feature support {{{

" Check if virtualtext is supported
function! import_cost#virtual_text#IsSupported()
    return has('nvim-0.3.2')
endfunction

" }}}
" Virtual text {{{

function! s:ShowVirtualTextMessage(imports, range_start_line, buffer_lines) abort
  let l:hl_group =  get(g:, 'import_cost_virtualtext_hl_group', 'LineNr')
  let l:prefix = get(g:, 'import_cost_virtualtext_prefix', ' > ')

  " Clear!
  call import_cost#virtual_text#Clear()

  for import in a:imports
    let l:message = s:CreateImportString(import, 1)
    let l:line = import['line'] + a:range_start_line - 1
    call nvim_buf_set_virtual_text(l:buffer, 1000, l:line, [[l:prefix.l:message, l:hl_group]], {})
  endfor
endfunction

" }}}
