if exists("g:draftin_loaded")
    finish
endif
let g:draftin_loaded = 1
let g:draftin_enabled = 1

let s:draftin_doc_create_endpoint = "https://draftin.com/api/v1/documents.json"
let s:draftin_doc_update_endpoint = "https://draftin.com/api/v1/documents/"

command -nargs=? Draft call <SID>Draft(<f-args>)

function! s:CheckDependencies()
    if !exists("g:loaded_jsoncodecs")
        echo "vim-draftin depends on jsoncodecs.vim for escaping"
        echo "https://github.com/vim-scripts/jsoncodecs.vim"
        return 0
    endif

    if !exists('g:loaded_parsejson') 
        echo "vim-draftin depends on ParseJSON for reply parsing"
        echo "https://github.com/vim-scripts/ParseJSON"
        return 0
    endif

    return 1
endfunction

function! s:MetadataFilename()
    return expand('%:h') . "/." . expand('%:t') . ".meta"
endfunction

function! s:ReadDocMetadata()
    let l:mdfilename = s:MetadataFilename() 
    if (filereadable(l:mdfilename))
        execute "source"  fnameescape(l:mdfilename)
    endif
endfunction

function! s:WriteDocMetadata(metadata)
    let l:mdfilename = s:MetadataFilename() 
    let l:mdlines = []
    let l:relevantKeys = ['id']
    for key in relevantKeys 
        call add(l:mdlines, "let b:draftin_" . key . " = '" . a:metadata[key] . "'")
    endfor
    call writefile(l:mdlines, l:mdfilename)
endfunction

" Upload the current buffer to draftin.com
function! s:Draft(...)
    if !exists("g:draftin_vim_auth")
        echo "Ensure draftin_auth is set in .vimrc as username:password or better,"
        echo "put it in a different file that is source by your vimrc"
        return
    endif

    if !g:draftin_enabled
        return
    endif

    if !s:CheckDependencies()
        return
    endif

    if !exists("b:autodraftin")
        call s:SetupDraftinBuffer()
    endif

    if !b:autodraftin
        let b:notautodraftin = 1
        let b:modified = &l:modified
        " Make sure the file is saved
        update
    endif

    let l:curl_method = "POST"

    let l:name = ""
    if len(a:000) == 1
        let l:name = a:1
    else
        let l:name = getline(1)
        " Use filename if there's no first line.
        if strlen(l:name) < 1
            let l:name = shellescape(expand('%:t')) 
        endif
    endif

    call s:ReadDocMetadata()
    let l:creating = 1
    if exists("b:draftin_id")
        if !b:modified
            echo "Buffer not modified, not sending update to draftin.com"
            return
        endif

        let l:creating = 0
        let l:curl_method = "PUT"
    endif

    " Escaping the content is rather messy, since 
    " 1) some characters must be escaped to be correct JSON
    " 2) the shell used for the system call to curl have different
    "    requirements
    " The current solution is to first do the JSON escaping and then get rid
    " of the quotes it adds since that interferes with the next step.
    " The pure, JSON escaped content is then shellescaped, and then the quotes
    " it add removed since that interferes with JSON formatting again. 
    " The last step is to put together the complete, properly escaped JSON
    " with content.
    let l:content = b:json_dump_string(getline(1, line("$")))[1:-2]
    let l:content = shellescape(l:content)[1:-2]
    let l:json = '{"content": "'. l:content.'", "name": "'.l:name.'"}'

    let l:curlCmd = "curl -s -u ". g:draftin_vim_auth . " -X " . curl_method
    let l:curlCmd .= " -H 'Content-Type: application/json'"
    let l:curlCmd .= " -d '".l:json."' "
    if l:creating
        let l:curlCmd .= s:draftin_doc_create_endpoint
    else
        let l:curlCmd .= s:draftin_doc_update_endpoint . b:draftin_id . ".json"
    endif

    let l:rawres = system(l:curlCmd)
    if l:creating
        let l:res = ParseJSON(l:rawres)
        call s:WriteDocMetadata(l:res)
        " Read it back so the stored variables can be used
        call s:ReadDocMetadata()
    endif

    if l:creating
        echo "Document " . l:name . " created and uploaded at https://draftin.com/documents/" . b:draftin_id
    else
        echo "Document " . l:name . " updated, see https://draftin.com/documents/" . b:draftin_id
    endif

    let b:modified = 0
endfunction

function! s:AutoDraft()
    if b:notautodraftin
        let b:notautodraftin = 0
        return
    endif
    let b:autodraftin = 1
    call s:Draft()
    let b:autodraftin = 0
endfunction

function! s:AddDraftinSaveHandlers()
    autocmd BufWritePre <buffer> let b:modified = &l:modified 
    autocmd BufWritePost <buffer> call s:AutoDraft()
endfunction

function! s:CheckSetupDraftinBuffer()
    call s:ReadDocMetadata()
    if exists("b:draftin_id")
        call s:SetupDraftinBuffer()
    endif
endfunction

function! s:SetupDraftinBuffer()
    call s:AddDraftinSaveHandlers()    
    let b:autodraftin = 0
    let b:notautodraftin = 0
    let b:modified = 0
endfunction

augroup draftin
    autocmd!

    autocmd  BufEnter  *  :call s:CheckSetupDraftinBuffer()
augroup END
