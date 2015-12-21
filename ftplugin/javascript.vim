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
let b:error_messages = []

"default hi-group for lint errors
highlight LintError      guibg=Red ctermbg=DarkRed guifg=NONE ctermfg=NONE

if !exists("g:nv_eslint_error_higroup")
    let g:nv_eslint_error_higroup = "LintError"
endif

setlocal errorformat=%f:%l:%c:%m  

"parse functions
function! s:Strip(input_string)
    return substitute(a:input_string, '^\s*\(.\{-}\)\s*$', '\1', '')
endfunction

function! s:GetPosFromOffset(offset)
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

function! ESLint_GetBufferText()

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
    if s:Strip(buftext) == ''
        return ""
    endif

    return buftext

endfunction
 
function! s:HighlightRegion(syn_group, hi_group, start_line, end_line, start_col, end_col)

    let cmd = "syn region " . a:syn_group . " start='\\%" . a:start_line ."l\\%". a:start_col .
                \"c' end='\\%" . a:end_line  . "l\\%" . a:end_col .
                \"c' containedin=ALL"
    "echom cmd
    exe cmd
    exe 'hi link ' . a:syn_group . ' ' . a:hi_group
    call add(b:lint_error_syn_groups, a:syn_group)

endfunction

function! s:HighlightError(errnum, line, col)
    "echom "HighlightError(" . a:errnum . "," . a:line . "," . a:col .")"
    
    let syn_group = "LintError_" . a:errnum . "_line"

    call s:HighlightRegion(syn_group, 'Error', a:line, a:line, a:col - 1, a:col)

    exe 'hi link ' . syn_group . ' ' . g:nv_eslint_error_higroup

endfunction


function! s:RemoveLintHighlighting()
    let b:lint_error_syn_groups = []
    "if jscc is installed, don't clear syntax, as it will be cleared by jscc
    "which takes longer and will 'render' after this plugin
    if !b:did_jscc_ftplugin
        syn clear
        setf javascript
    endif
endfunction

function! s:FixLintError(fix) 
    
    let range = a:fix.range
    let fixtext = a:fix.text
    let range_start = s:GetPosFromOffset(range[0])

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
        let range_end = s:GetPosFromOffset(range[1])
    endif

endfunction

function! s:FixLintErrors()

    "echom 'FixLintErrors'
    "jump back out of QuickFix window if in it
    if &ft == 'qf'
        lcl
    endif
    for msg in b:lint_errors
        if has_key(msg, 'fix')
            call s:FixLintError(msg.fix)
        endif
    endfor
    "run lint again
    call Eslint()

endfunction

"global --called by javascript-context-colors
function! ShowEslintErrorHighlighting()
    echom "ShowEslintErrorHighlighting()"

    let b:error_messages = []
    let errcount = 0

    for msg in b:lint_errors

        let errcount += 1
        call s:HighlightError(++errcount, msg.line, msg.column)

    endfor

    "ensure syntax highlighting is fully applied
    syntax sync fromstart
endfunction

"global function -- called by node host
function! ShowEslintOutput(result)
    let true = 1
    let false = 0
    let result = eval(a:result)
    let error_messages = []
    let filename = expand("%")

    if len(b:lint_error_syn_groups)
        call s:RemoveLintHighlighting()
    endif

    let b:lint_errors = result.messages

    for msg in b:lint_errors

        call add(error_messages, filename . ":" . msg.line . ":" . msg.column . ":" . msg.message)

    endfor

    call ShowEslintErrorHighlighting()

    "populate local list
    if len(error_messages)
        lex error_messages
        lop
    else
        lex ""
        lcl
    endif

endfunction


function! s:AddAutoCmds()
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

if !exists(":Eslint")
    command! Eslint :call Eslint()
endif

if !exists(":FixLint")
    command! FixLint :call s:FixLintErrors()
endif

call s:AddAutoCmds()

if !hasmapto('<Plug>FixLint')
    nnoremap <buffer> <silent> <localleader>f :FixLint<CR>
endif


