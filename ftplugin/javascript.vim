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

highlight LintError      guibg=Red ctermbg=DarkRed guifg=NONE ctermfg=NONE

setlocal errorformat=%f:%l:%c:%m  

"parse functions
function! Strip(input_string)
    return substitute(a:input_string, '^\s*\(.\{-}\)\s*$', '\1', '')
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

function! ShowEslintOutput(result)
    "echo a:result
    let true = 1
    let false = 0
    let result = eval(a:result)
    let b:num_errors = 0
    let errors = []
    let filename = expand("%")

    if len(b:lint_error_syn_groups)
        call RemoveLintHighlighting()
    endif

    for msg in result.messages
        let b:num_errors = b:num_errors + 1
        "echom msg
        "if (msg.severity == 2) 
            call HighlightError(b:num_errors, msg.line, msg.column)
            
        "endif
        call add(errors, filename . ":" . msg.line . ":" . msg.column . ":" . msg.message)
    endfor

    "ensure syntax highlighting is fully applied
    syntax sync fromstart

    "populate local list
    if len(errors)
        lex errors
        lop
    else
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

call AddAutoCmds()
