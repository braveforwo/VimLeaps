if(exists("g:COOPER_API"))
	finish
endif

" The path head for this script is needed for working with other modules.
let s:SCRIPT_ROOT = expand("<sfile>:p:h") . "/"

" Apply object-oriented technique in our framework.
exe "so ".s:SCRIPT_ROOT."ObjectBuilder.vim"

" Apply codepoint arrays using the ES6triple dot operator.
exe "so ".s:SCRIPT_ROOT."CooperStr.vim"

" An object designed to keep track of the inbound.
exe "so ".s:SCRIPT_ROOT."CooperModel.vim"

" LeapClient is the main tool provided to allow an easy and stable 
" interface for connecting to a coopers server.
exe "so ".s:SCRIPT_ROOT."CooperClient.vim"

" LeapClient and uses it to wrap a vim
exe "so ".s:SCRIPT_ROOT."CooperBindVim.vim"

" LeapClient and uses it to wrap a vim
exe "so ".s:SCRIPT_ROOT."PopupUser.vim"

let g:COOPER_API=expand("<sfile>:p")
call DefineClass(g:COOPER_API,{},[])

" any buffer BindVim Object
let g:COOPERsVim = []
autocmd FileChangedShell * let v:fcs_choice="reload"

" Initiate collaborative editing file
" param#file : absolute file path
" param#root : root path
" @accessible
function! s:StartCollaborative(file, root, username, projectid)
	let oldbufnr = bufnr(bufname("%"))
	set autoread
	"set termguicolors
	let vim = #{}
	if (bufexists(a:file) != 0)
		let vim = #{bufnr:bufnr(a:file)}
	else
		let bufnr = bufadd(a:file)
		exe "buffer! " . bufnr
		let vim = #{bufnr:bufnr}
	endif

	exe "buffer! " . bufnr(a:file)
	
	if(exists("b:cooperBindVim"))
		return
	endif
	let b:cooperClient = CreateInstance(g:COOPER_CLIENT,{}).New()
	let b:cooperBindVim = CreateInstance(g:COOPER_BIND_VIM,{}).New(b:cooperClient, vim)
	call b:cooperBindVim.InitEvent()

	call add(g:COOPERsVim, b:cooperBindVim)
	let a =  b:cooperBindVim.cooperClient.Connect("localhost:8332")
	let bufname = substitute(a:file, a:root, "", "")
	
	" first connect socket
	if(a == 1 && !exists("g:OnceConnect"))
		call b:cooperBindVim.cooperClient.OnNext("global_metadata", function("s:GlobalMetadata",[bufname,b:cooperBindVim]))
		let username = a:username
		let path = a:root
		call b:cooperBindVim.cooperClient.Send(#{projectid:a:projectid,username:username,path:path})
		let g:OnceConnect = 1
	else
		call b:cooperBindVim.cooperClient.Subscribe(bufname)
	endif
	exe "buffer! " . oldbufnr
	return "success"
endfun

" @accessible
function! s:Unsubscribe(documentId,root)
	let bufname = substitute(a:documentId, a:root, "", "")
	call b:cooperBindVim.cooperClient.Unsubscribe(bufname)
endfun


function! UnsubscribeTest()
	call s:Unsubscribe("/home/clouder/project/test123/te.vim", "/home/clouder/project/test123/")
endfun

" User join in collaborative edit
function! JoinCollaborative(file, root, username, projectid)
	"let b:cooperClient = CreateInstance(g:COOPER_CLIENT,{}).New()
	"let vim = #{bufnr:bufnr(bufname("%"))}
	"let b:cooperBindVim = CreateInstance(g:COOPER_BIND_VIM,{}).New(b:cooperClient, vim)
	"call b:cooperBindVim.InitEvent()
	
	"call add(g:COOPERsVim, b:cooperBindVim)
	"let a =  b:cooperBindVim.cooperClient.Connect("localhost:8332")
	"let bufname = substitute(a:file, a:root, "", "")
	"if(a == 1)
	"	call b:cooperBindVim.cooperClient.OnNext("global_metadata", function("s:GlobalMetadata",[bufname, b:cooperBindVim]))
	"	let username = a:username
	"	let path = a:root
	"	call b:cooperBindVim.cooperClient.Send(#{projectid:a:projectid, username:username, path:path})
	"endif
	set noswapfile
	set autoread
	call s:StartCollaborative(a:file, a:root, a:username,a:projectid)
	
endfun

function! s:GlobalMetadata(filename, cooperBindVim, body)
	call a:cooperBindVim.cooperClient.Subscribe(a:filename)
endfun

function! StartTest()

	call s:StartCollaborative("/home/clouder/project/test123/te.vim", "/home/clouder/project/test123/", "username1","51988002")
endfun

function! JoinTest()
	set noswapfile
	call s:StartCollaborative("/home/clouder/project/test123/te.vim", "/home/clouder/project/test123/", "username2","51988002")
endfun

function! JoinTest2()
	set noswapfile
	call s:StartCollaborative("/home/clouder/project/test123/te.vim", "/home/clouder/project/test123/", "username3","51988002")
endfun

function! TwoBufFile()
	set noswapfile
	call s:StartCollaborative("/home/clouder/project/test123/te.vim", "/home/clouder/project/test123/", "username1","51988002")
endfun
function! TwoBufFile2()
	set noswapfile
	call s:StartCollaborative("/home/clouder/project/test123/te.vim", "/home/clouder/project/test123/", "username2", "51988002")
endfun

