if exists("b:current_syntax") | finish | endif
syn case match
syn keyword qafKeyword fn let if else while for return break continue import from as
syn keyword qafType i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool char string
syn keyword qafBoolean true false
syn match qafNumber '\<\d\+\%(\.\d\+\)\?\>'
syn match qafFunction '\<[A-Za-z_][A-Za-z0-9_]*\ze\s*('
syn match qafOperator '==\|!=\|<=\|>=\|&&\|||\|+\|-\|*\|/\|%\|<\|>\|=\|!'
syn match qafComment '#.*$'
syn region qafString start='"' skip='\\.' end='"' contains=qafEscape
syn match qafEscape '\\.' contained
hi def link qafKeyword Keyword
hi def link qafType Type
hi def link qafBoolean Boolean
hi def link qafNumber Number
hi def link qafFunction Function
hi def link qafOperator Operator
hi def link qafComment Comment
hi def link qafString String
hi def link qafEscape SpecialChar
let b:current_syntax = "qaf"
