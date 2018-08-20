" This script contains some higher-level support for async operation in both
" Neovim and Vim 8. Please nore that these implementations are *VERY* simple and
" targerting the use case of this specific plguin.

" Most of following functions assumes that the check for async support
" (`import_cost#async#IsAsyncSupported()`) was done before.

" Check wether the current version of the editor supports async jobs
function! import_cost#async#is_supported()
  return has('nvim') || v:version >= 800
endfunction

" Starts a new async job and returns the job id
" The callback function should have the following signature:
"
"     `function! JobCallback(data, event)`
"
" Where `data` is a string containing the data received, and `event` is the
" event type (can be one of `stdin`, `stderr`, `exit`). The `data` for the
" `exit` event is the exit code.
"
function! import_cost#async#job_start(command, callback)
  if has('nvim')

    " 'Converting' neovim's callback function to our 'basic' callback
    " signature
    let l:TransformedCallback = {job_id, data, event ->
          \ a:callback(type(data) == 3 ? join(data, "\n") : data, event)}

    let l:job_id = jobstart(a:command, {
          \ 'shell': 'import_cost_shell',
          \ 'on_stdout': l:TransformedCallback,
          \ 'on_stderr': l:TransformedCallback,
          \ 'on_exit': l:TransformedCallback,
          \ })
  else
    let l:job_id = job_start(a:command, {
          \ 'callback': {channel, data -> a:callback(data, 'stdout')},
          \ 'err_cb': {channel, data -> a:callback(data, 'stderr')},
          \ 'exit_cb': {job_id, exit_code -> a:callback(exit_code, 'exit')},
          \ 'mode': 'raw',
          \ })
  endif

  return l:job_id
endfunction

" Stops a job
function! import_cost#async#job_stop(job_id)
  if has('nvim')
    call jobstop(a:job_id)
  else
    call job_stop(a:job_id)
  endif
endfunction

" Send an input to a job via stdin
function! import_cost#async#job_send(job_id, data)
  if has('nvim')
    call jobsend(a:job_id, a:data)
  else
    call ch_sendraw(job_getchannel(a:job_id), a:data)
  endif
endfunction

" Close the stdin channel for a job
function! import_cost#async#job_close(job_id)
  if has('nvim')
    call jobclose(a:job_id, 'stdin')
  else
    call ch_close_in(job_getchannel(a:job_id))
  endif
endfunction
