"plugin to run eslint on JavaScript
"Version: 0.0.1
"Author: David Wilhelm <dewilhelm@gmail.com>
"
" Only do this when not done yet for this buffer
if exists("b:did_eslint_ftplugin")
  finish
endif
let b:did_eslint_ftplugin = 1

let b:lint_error_syn_groups = []

let b:lint_errors = []

highlight LintError      guibg=Red ctermbg=DarkRed guifg=NONE ctermfg=NONE

setlocal errorformat=%f:%l:%c:%m  

"parse functions
function! Strip(input_string)
    return substitute(a:input_string, '^\s*\(.\{-}\)\s*$', '\1', '')
endfunction

function! GetPosFromOffset(offset)
    "normalize byte count for Vim (first byte is 1 in Vim)
    let offset = a:offset + 1
    if offset < 0
        call Warn('offset cannot be less than 0: ' . string(offset))
    endif
    let line = byte2line(offset)
    let line_start_offset = line2byte(line)
    "first col is 1 in Vim
    let col = (offset - line_start_offset) + 1
    let pos = [line, col]
    "if !IsPos(pos)
    "Warn('invalid pos result in GetPosFromOffset()' . string(pos))
    "endif
    return pos
endfunction

function! GetBufferText()

    let buflines = getline(1, '$')
    let buftext = ""

    "replace hashbangs (in node CLI scripts)
    let linenum  = 0
    for bline in buflines
        if match(bline, '#!') == 0
            "replace #! with // to prevent parse errors
            "while not throwing off byte count
            let buflines[linenum] = '//' . strpart(bline, 2)
            break
        endif
        let linenum += 1
    endfor
    "fix offset errors caused by windows line endings
    "since 'buflines' does NOT return the line endings
    "we need to replace them for unix/mac file formats
    "and for windows we replace them with a space and \n
    "since \r does not work in node on linux, just replacing
    "with a space will at least correct the offsets
    if &ff == 'unix' || &ff == 'mac'
        let buftext = join(buflines, "\n")
    elseif &ff == 'dos'
        let buftext = join(buflines, " \n")
    endif

    "noop if empty string
    if Strip(buftext) == ''
        return ""
    endif

    return buftext

endfunction
 
function! HighlightRegion(syn_group, hi_group, start_line, end_line, start_col, end_col)

    let cmd = "syn region " . a:syn_group . " start='\\%" . a:start_line ."l\\%". a:start_col .
                \"c' end='\\%" . a:end_line  . "l\\%" . a:end_col .
                \"c' containedin=ALL"
    "echom cmd
    exe cmd
    exe 'hi link ' . a:syn_group . ' ' . a:hi_group
    call add(b:lint_error_syn_groups, a:syn_group)

endfunction

function! HighlightError(errnum, line, col)
    
    let syn_group = "LintError_" . a:errnum . "_line"

    call HighlightRegion(syn_group, 'Error', a:line, a:line, a:col - 1, a:col)

    exe 'hi link ' . syn_group . ' LintError'

endfunction

let b:num_errors = 0

function! RemoveLintHighlighting()
    let b:lint_error_syn_groups = []
    syn clear
    setf javascript
endfunction

function! FixLintError(fix) 
    
    let range = a:fix.range
    let fixtext = a:fix.text
    let range_start = GetPosFromOffset(range[0])

    "if start and end are the same -- simply insert text
    if (range[1] == range[0]) 
        "insert text after range pos
        let range_end = range_start
        let linetext = getline(range_start[0])
        "echom "linetext:" . linetext
        let newtext = strpart(linetext, 0, range_start[1]) . fixtext . strpart(linetext, range_start[1])
        call setline(range_start[0], newtext)
    else
        "TODO
        let range_end = GetPosFromOffset(range[1])
    endif

endfunction

function! FixLintErrors()

    "echom 'FixLintErrors'
    "jump back out of QuickFix window if in it
    if &ft == 'qf'
        lcl
    endif
    for msg in b:lint_errors
        if has_key(msg, 'fix')
            call FixLintError(msg.fix)
        endif
    endfor
    "run lint again
    call Eslint()

endfunction

function! ShowEslintOutput(result)
    "echom 'ShowEslintOutput'
    let true = 1
    let false = 0
    let result = eval(a:result)
    let b:num_errors = 0
    let errors = []
    let filename = expand("%")

    if len(b:lint_error_syn_groups)
        call RemoveLintHighlighting()
    endif

    let b:lint_errors = result.messages
    "echom 'b:lint_errors' . string(b:lint_errors)

    for msg in result.messages

        let b:num_errors = b:num_errors + 1

        call HighlightError(b:num_errors, msg.line, msg.column)

        call add(errors, filename . ":" . msg.line . ":" . msg.column . ":" . msg.message)

    endfor

    "ensure syntax highlighting is fully applied
    syntax sync fromstart

    "populate local list
    if len(errors)
        lex errors
        "lop
    else
        lex ""
        lcl
    endif

endfunction


function! AddAutoCmds()
    try
        augroup EslintAug
            "remove if added previously, but only in this buffer
            au! InsertLeave,TextChanged <buffer> 
            au! InsertLeave,TextChanged <buffer> :Eslint
        augroup END

    "if < vim 7.4 TextChanged events are not
    "available and will result in error E216
    catch /^Vim\%((\a\+)\)\=:E216/

            "use different events to trigger update in Vim < 7.4
            augroup EslintAug
                au! InsertLeave <buffer> 
                au! InsertLeave <buffer> :Eslint
            augroup END

    endtry
endfunction

function! Eslint() 
    doautocmd User eslint.lint
endfunction

command! Eslint call Eslint()
command! FixLint call FixLintErrors()

call AddAutoCmds()

if !hasmapto('<Plug>FixLint')
    nnoremap <buffer> <silent> <localleader>f :FixLint<CR>
endif


