vim.api.nvim_create_autocmd({"BufRead","BufNewFile"},{pattern="*.qf",callback=function(args) vim.bo[args.buf].filetype="qaf" end})
vim.api.nvim_create_autocmd("FileType",{pattern="qaf",callback=function()
  vim.cmd([[
    syntax case match
    syntax keyword qafKeyword fn let if else while for return break continue import from as
    syntax keyword qafType i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool char string
    syntax keyword qafBoolean true false
    syntax match qafNumber /\<\d\+\%(\.\d\+\)\?\>/
    syntax match qafFunction /\<[A-Za-z_][A-Za-z0-9_]*\ze\s*(/
    syntax match qafOperator /==\|!=\|<=\|>=\|&&\|||\|+\|-\|*\|\/\|%\|<\|>\|=\|!/
    syntax match qafComment /#.*/
    syntax region qafString start=/"/ skip=/\\./ end=/"/ contains=qafEscape
    syntax match qafEscape /\\./ contained
    highlight default link qafKeyword Keyword
    highlight default link qafType Type
    highlight default link qafBoolean Boolean
    highlight default link qafNumber Number
    highlight default link qafFunction Function
    highlight default link qafOperator Operator
    highlight default link qafComment Comment
    highlight default link qafString String
    highlight default link qafEscape SpecialChar
  ]])
end})
