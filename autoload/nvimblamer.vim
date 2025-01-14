
function! nvimblamer#auto() abort
  augroup BlamerLua
    autocmd CursorHold   * lua require'nvim-blamer'.show()
    autocmd CursorMoved  * lua require'nvim-blamer'.clear()
    autocmd CursorMovedI * lua require'nvim-blamer'.clear()
    autocmd BufWritePost * lua require'nvim-blamer'.update()
  augroup end
endfunction

function! nvimblamer#toggle() abort
  lua require'nvim-blamer'.toggle()
endfunction
