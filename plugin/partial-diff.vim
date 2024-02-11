command! -range PartialDiffA lua require('partial-diff').partial_diff_a(<line1>, <line2>)
command! -range PartialDiffB lua require('partial-diff').partial_diff_b(<line1>, <line2>)
command! PartialDiffDelete lua require('partial-diff').partial_diff_delete()

