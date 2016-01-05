"plugin to run eslint on JavaScript
"Version: 0.0.1
"Author: David Wilhelm <dewilhelm@gmail.com>
"
" Only do this when not done yet for this buffer
if exists("b:did_eslint_ftplugin")
  finish
endif

let b:did_eslint_ftplugin = 1

let b:lint_errors = []
let b:error_messages = []
let b:matches = []

if !exists("g:nv_eslint_auto_open_location_list")
    let g:nv_eslint_auto_open_location_list = 0
endif

"default hi-group for lint errors
highlight LintError      guibg=Red ctermbg=160 guifg=NONE ctermfg=NONE

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
 
function! s:FixLintError(fix) 
    
    let range = a:fix.range
    let fixtext = a:fix.text
    let range_start = s:GetPosFromOffset(range[0])

    "if start and end are the same -- simply insert text
    if (range[1] == range[0]) 
        "insert text after range pos
        let range_end = range_start
        let linetext = getline(range_start[0])

        let newtext = strpart(linetext, 0, range_start[1]) . fixtext . strpart(linetext, range_start[1])
        call setline(range_start[0], newtext)
        "return offset as length of inserted text
        return len(fixtext)

    else
        let range_end = s:GetPosFromOffset(range[1])
        if range[1] > range[0]
            "if on same line
            if range_start[0] == range_end[0]
                let linetext = getline(range_start[0])
                let newtext = strpart(linetext, 0, range_start[1] - 1) . fixtext . strpart(linetext, range_end[1] - 1)
                call setline(range_start[0], newtext)
                "return offset as len(added_text) - len(removed_text)"
                return len(fixtext) - (range[1] - range[0])
            endif
            "else? multiline fixes"
        endif
    endif
    return 0

endfunction

function! s:FixLintErrors()

    "jump back out of QuickFix window if in it
    if &ft == 'qf'
        lcl
    endif
    let offset = 0

    for msg in b:lint_errors
        if has_key(msg, 'fix')
            if len(offset)
                let msg.fix.range[0] += offset
                let msg.fix.range[1] += offset
            endif
            let offset += s:FixLintError(msg.fix)
        endif
    endfor

    "run lint again
    call Eslint()

endfunction

"global function -- called by node host
function! ShowEslintOutput(result)
    let true = 1
    let false = 0
    let result = eval(a:result)
    let error_messages = []
    let filename = expand("%")

    let b:lint_errors = result.messages
    let num_errors = len(b:lint_errors)

    let match_positions = []

    for msg in b:lint_errors
        let line = msg.line
        let col = msg.column
        call add(match_positions, [line, col])
        call add(error_messages, filename . ":" . line . ":" . col . ":" . msg.message)
    endfor

    call clearmatches()

    "use matchaddpos() to highlight matches
    "this function can only take 8 positions,
    "so group the lint_errors into groups of 8
    let startIdx = 0
    let sublist = match_positions[0:7]
    while len(sublist) > 0
        call matchaddpos('LintError', sublist)
        let startIdx += 8
        let endIdx = startIdx + 8
        let sublist = match_positions[startIdx : endIdx]
    endwhile

    "populate local list
    if len(error_messages)
        lex! error_messages
        if g:nv_eslint_auto_open_location_list
            lop
        endif
    else
        lex ""
        lcl
    endif

endfunction


function! s:AddAutoCmds()
    try
        augroup EslintAug
            "remove if added previously, but only in this buffer
            "au! InsertLeave,TextChanged <buffer> 
            "au! InsertLeave,TextChanged <buffer> :Eslint
            au! BufEnter,BufWrite <buffer> 
            au! BufEnter,BufWrite <buffer> :Eslint
        augroup END

    "if < vim 7.4 TextChanged events are not
    "available and will result in error E216
    catch /^Vim\%((\a\+)\)\=:E216/

            "use different events to trigger update in Vim < 7.4
            augroup EslintAug
                "au! InsertLeave <buffer> 
                "au! InsertLeave <buffer> :Eslint
                au! BufEnter,BufWrite <buffer> 
                au! BufEnter,BufWrite <buffer> :Eslint
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


