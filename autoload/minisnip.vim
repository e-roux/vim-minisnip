let s:placeholder_texts = {}
let s:placeholder_text_previous = ''
let s:minisnip_dir = g:minisnip_dir

let s:cmp = 'stridx(v:val, l:pat) >= 0'

function! minisnip#init() abort
  " Add the all directory for eacht path and a filetype specific path
  for l:dir in split(g:minisnip_dir, s:pathsep())
    let l:new_dir = trim(":" . l:dir . "/all" . ":" . l:dir . "/" . &filetype)
    let s:minisnip_dir .= l:new_dir
  endfor

  echom s:minisnip_dir
endfunction

function! minisnip#ShouldTrigger() abort
  silent! unlet! s:snippetfile

  " include cursor character in select mode
  let l:col = mode() == "s" ? col('.') + 1 : col('.')

  let s:cword = matchstr(getline('.'), '\v\f+%' . l:col . 'c')
  let s:begcol = mode() == "s" ? virtcol('.') + 1 : virtcol('.')

  " look for a snippet by that name
  for l:dir in split(s:minisnip_dir, s:pathsep())
    let l:dir = fnamemodify(l:dir, ':p')
    let l:snippetfile = l:dir . '/' . &filetype . "/" . s:cword . ".snip"

    " filetype snippets override general snippets
    for l:filetype in split(&filetype, '\.')
      let l:ft_snippetfile = l:dir . '/_' . l:filetype . '_' . s:cword . ".snip"
      if filereadable(l:ft_snippetfile)
        let l:snippetfile = l:ft_snippetfile
        break
      endif
    endfor

    " make sure the snippet exists
    if filereadable(l:snippetfile)
      let s:snippetfile = l:snippetfile
      return 1
    endif
  endfor

  return search(g:minisnip_delimpat . '\|' . g:minisnip_finaldelimpat, 'e')
endfunction

" main function, called on press of Tab (or whatever key Minisnip is bound to)
function! minisnip#Minisnip() abort
  if exists('s:snippetfile')
    " reset placeholder text history (for backrefs) if it grows too much
    let s:placeholder_texts = {}
    let s:placeholder_content = ''
    let s:placeholder_text_previous = ''
    " adjust the indentation, use the current line as reference
    let l:ws = matchstr(getline(line('.')), '^\s\+')
    let l:lns = map(readfile(s:snippetfile), 'empty(v:val)? v:val : l:ws.v:val')
    let l:nlines = len(l:lns)

    " remove the snippet keyword
    " go to the position at the beginning of the snippet
    execute ':normal! '.(s:begcol - strchars(s:cword)).'|'
    " delete the snippet
    execute ':normal! '.strchars(s:cword).'"_x'

    if virtcol('.') >= (s:begcol - strchars(s:cword))
      " there is something following the snippet
      let l:keepEndOfLine = 1
      let l:endOfLine = strpart(getline(line('.')), (col('.') - 1))
      normal! "_D
    else
      let l:keepEndOfLine = 0
    endif

    " insert the snippet
    call append(line('.'), l:lns)

    if l:keepEndOfLine == 1
      " add the end of the line after the snippet
      execute ':normal! ' . len(l:lns) . 'j'
      call append((line('.')), l:endOfLine)
      join!
      execute ':normal! ' . len(l:lns) . 'k'
    endif

    if strchars(l:ws) > 0
      " remove the padding of the first line of the snippet
      execute ':normal! j0' . strchars(l:ws) . '"_xk$'
    endif
    join!

    " go to the beginning of the snippet
    execute ':normal! '.(s:begcol - strchars(s:cword)).'|'

    " TODO: add to help file ../doc/minisnip.txt <30-04-20 Gavin Jaeger-Freeborn>
    " auto indent
    if exists('g:minisnip_autoindent') && g:minisnip_autoindent
      execute ':silent normal! =' . l:nlines . 'j'
    endif

    " select the first placeholder
    call s:SelectPlaceholder()
  else
    " Make sure '< mark is set so the normal command won't error out.
    if getpos("'<") == [0, 0, 0, 0]
      call setpos("'<", getpos('.'))
    endif

    " save the current placeholder's text so we can backref it
    let l:old_s = @s
    normal! ms"syv`<`s
    let s:placeholder_content = @s
    let @s = l:old_s
    " jump to the next placeholder
    call s:SelectPlaceholder()
  endif
endfunction

" this is the function that finds and selects the next placeholder
function! s:SelectPlaceholder() abort
  " don't clobber s register
  let l:old_s = @s

  " get the contents of the placeholder
  " we use /e here in case the cursor is already on it (which occurs ex.
  "   when a snippet begins with a placeholder)
  " we also use keeppatterns to avoid clobbering the search history /
  "   highlighting all the other placeholders
  try
    " gn misbehaves when 'wrapscan' isn't set (see vim's #1683)
    let [l:ws, &wrapscan] = [&wrapscan, 1]
    silent keeppatterns execute 'normal! /' . g:minisnip_delimpat . "/e\<cr>gn\"sy"
    " save length of entire placeholder for reference later
    let l:slen = len(@s)
    " remove the start and end delimiters
    let @s=substitute(@s, '\V' . g:minisnip_startdelim, '', '')
    let @s=substitute(@s, '\V' . g:minisnip_enddelim, '', '')
  catch /E486:/
    " There's no normal placeholder at all
    try
      silent keeppatterns execute 'normal! /' . g:minisnip_finaldelimpat . "/e\<cr>gn\"sy"
      " save length of entire placeholder for reference later
      let l:slen = len(@s)
      " remove the start and end delimiters
      let @s=substitute(@s, '\V' . g:minisnip_finalstartdelim, '', '')
      let @s=substitute(@s, '\V' . g:minisnip_finalenddelim, '', '')
    catch /E486:/
      " There's no placeholder at all, enter insert mode
      call feedkeys('i', 'n')
      return
    finally
      let &wrapscan = l:ws
    endtry
  finally
    let &wrapscan = l:ws
  endtry

  if @s =~ '\V\^' . g:minisnip_donotskipmarker
    let @s=substitute(@s, '\V\^' . g:minisnip_donotskipmarker , '', '')
    let l:skip = 0
  elseif @s =~ '\V\^' . g:minisnip_evalmarker
    let l:skip = 1
  elseif @s =~ '\V\^' . g:minisnip_backrefmarker
    let l:skip = 1
  else
    let l:skip = 0
  endif

  " Add it to backrefs
  if s:placeholder_text_previous !=# ''
    let s:placeholder_texts[s:placeholder_text_previous] = s:placeholder_content
  endif
  let s:placeholder_text_previous = @s

  if @s =~ '\V\^' . g:minisnip_backrefmarker
    let @s=substitute(@s, '\V\^' . g:minisnip_backrefmarker, '', '')

    " We have seen this placeholder before.
    if has_key(s:placeholder_texts, @s)
      let @s=get(s:placeholder_texts, @s)
    else
      " Add it to backrefs
      if s:placeholder_text_previous !=# ''
        let s:placeholder_texts[s:placeholder_text_previous] = s:placeholder_content
      endif
      let s:placeholder_text_previous = @s

      " if not seen. Ask again. (happend when using snippets in snippets)
      let l:skip = 0
    endif
  endif

  " is this placeholder marked as 'evaluate'?
  if @s =~ '\V\^' . g:minisnip_evalmarker
    " remove the marker
    let @s=substitute(@s, '\V\^' . g:minisnip_evalmarker, '', '')
    " evaluate what's left
    let @s=eval(@s)

    " Add it to backrefs
    let s:placeholder_texts[s:placeholder_text_previous] = @s
    let s:placeholder_text_previous = @s
  endif

  if empty(@s)
    " the placeholder was empty, so just enter insert mode directly
    normal! gv"_d
    call feedkeys(col("'>") - l:slen >= col('$') - 1 ? 'a' : 'i', 'n')
  elseif l:skip == 1
    normal! gv"sp
    let @s = l:old_s
    call s:SelectPlaceholder()
  else
    " paste the placeholder's default value in and enter select mode on it
    execute "normal! gv\"spgv\<C-g>"
  endif

  " restore old value of s register
  let @s = l:old_s
endfunction

function! minisnip#candidates() abort
  if !exists("g:pathsep")
    let g:pathsep = s:pathsep()
  endif
  let l:global_snippets = []
  let l:filetype_snippets = []

  for l:dir in split(s:minisnip_dir, g:pathsep)
    let l:global_snippets = l:global_snippets +
          \ map(glob(l:dir . '/all/*', v:false, v:true),
          \ {key, val -> fnamemodify(val, ':t')})
    let l:filetype_snippets = l:filetype_snippets +
          \ map(glob(l:dir . '/' . &filetype . '/*', v:false, v:true),
          \ {key, val -> fnamemodify(val, ':t')})
  endfor
  return l:global_snippets + l:filetype_snippets
endfunction

function! minisnip#complete() abort
  let l:pat = matchstr(getline('.'), '\S\+\%' . col('.') . 'c')
  if len(l:pat) < 1
    return ''
  endif
  if !exists('b:snippet_candidates')
    let b:snippet_candidates = minisnip#candidates()
  endif

  let l:candidates = map(filter(copy(b:snippet_candidates), s:cmp),
        \ '{
        \      "word": fnamemodify(v:val, ":r"),
        \      "menu": " [Snippet]",
        \      "dup": 1,
        \      "user_data": "all"
        \ }')
  if !empty(l:candidates)
    call complete(col('.') - len(l:pat), l:candidates)
  endif
  return ''
endfunction

" Get the path separator for this platform.
function! s:pathsep()
  if has("win64")
    return ';'
  endif
  return ':'
endfunction
