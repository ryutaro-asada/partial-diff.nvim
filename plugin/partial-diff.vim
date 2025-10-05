" Prevent loading the plugin multiple times
if exists('g:loaded_partial_diff')
  finish
endif
let g:loaded_partial_diff = 1

" New recommended commands (From/To)
command! -range PartialDiffFrom lua require('partial-diff').partial_diff_from(<line1>, <line2>)
command! -range PartialDiffTo lua require('partial-diff').partial_diff_to(<line1>, <line2>)

" Backward compatibility commands (A/B)
command! -range PartialDiffA lua require('partial-diff').partial_diff_from(<line1>, <line2>)
command! -range PartialDiffB lua require('partial-diff').partial_diff_to(<line1>, <line2>)

" Other commands
command! PartialDiffDelete lua require('partial-diff').partial_diff_delete()
command! PartialDiffInstallVSCode lua require('partial-diff').install_vscode_diff()

" Debug commands
command! PartialDiffShowLog lua require('partial-diff').show_log()
command! PartialDiffClearLog lua require('partial-diff').clear_log()
