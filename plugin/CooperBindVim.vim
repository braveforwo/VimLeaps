if(exists("g:COOPER_BIND_VIM"))
	finish
endif

let s:cooperBindVim = {}
let g:COOPER_BIND_VIM = s:cooperBindVim

" leap_bind_vim takes an existing leap_client and uses it to wrap a textarea into an
" interactive editor for the leaps document the client connects to. Returns the bound object, and
" places any errors in the obj.error field to be checked after construction.
" vim is #{bufnr:5}
" @accessible
function! s:cooperBindVim.New(cooperClient, vim) dict
	let self.textArea = a:vim
	let self.cooperClient = a:cooperClient
	let self.documentId = ""
	let self.content = ""
	let self.ready = 0
	let self.textArea.disabled = 1
	let self.startSync = 0
	let self.cursors = {}
	let binder = self

	return deepcopy(self)
endfun

" load event
" @accessible
function! s:cooperBindVim.InitEvent() dict
	if(!has_key(self.textArea, "addEventListener"))
		let self.textArea.addEventListener = listener_add(self.TriggerDiffbak, self.textArea.bufnr)
	endif
	
	augroup CooperCursorEvent
		autocmd CursorMovedI <buffer> call SendCursor()
		autocmd CursorMoved <buffer> call SendCursor()
	augroup END

	call self.cooperClient.On("subscribe" , self.Subscribe)

	call self.cooperClient.On("global_metadata" , self.GlobalMata)	

	call self.cooperClient.On("metadata" , self.MetaData)	

	call self.cooperClient.On("transforms", self.Transforms)

	call self.cooperClient.On("unsubscribe", self.Unsubscribe)

	"call self.cooperClient.On("connect", self.Connect)
endfun

" apply_transform, applies a single transform to the textarea. 
" Also attempts to retain the original cursor position.
" @accessible
function! s:cooperBindVim.ApplyTransform(transform) dict
	let curpos = getcurpos()

	call setbufvar(self.textArea.bufnr, "&buflisted", 1)
	let content = join(getbufline(self.textArea.bufnr, 1, "$"),"\n")
	let pos = 0
	if(a:transform.position <= curpos[2])
		let pos = curpos[2] + (len(a:transform.insert)-a:transform.num_delete)
	endif
	
	let result = self.cooperClient.Apply(a:transform, content , self)
	let self.content = result[0]
	"let view = winsaveview()
	let self.startSync = 1	

	call setbufvar(self.textArea.bufnr, "&buflisted", 1)
	exe self.textArea.bufnr . 'bufdo! normal ggdG'

	let oldContent = @x
	let @x = self.content
	exe self.textArea.bufnr . 'bufdo! normal "xgP'
	let @x = oldContent
	
	let self.startSync = 0
	"exe self.textArea.bufnr . 'bufdo! normal gg'
	"call winrestview(view)

	
	call cursor(result[1], result[2])
	"call self.RestorePopup()
endfun


" updates any visual state of other users within the
" vim screen.
" @accessible
function! s:cooperBindVim.UpdateUserInfo(body) dict
	if(a:body.metadata.type == "cursor_update" && a:body.metadata.body.document.id == self.documentId)
		if(has_key(self.cursors, a:body.client.session_id))
			"if(self.cursors[a:body.client.session_id].position != a:body.metadata.body.position)
				let self.cursors[a:body.client.session_id].position = a:body.metadata.body.position
				let cursor = s:PosFromIndex(self.textArea.bufnr, a:body.metadata.body.position)
				if(has_key(self.cursors[a:body.client.session_id], "highlight"))
					"if(has_key(self.cursors[a:body.client.session_id], "timerid"))
					"	call timer_stop(self.cursors[a:body.client.session_id]["timerid"])
					"	call remove(self.cursors[a:body.client.session_id], "timerid")
					"endif

					if(has_key(self.cursors[a:body.client.session_id], "matchid"))
						call matchdelete(self.cursors[a:body.client.session_id]["matchid"])
						call remove(self.cursors[a:body.client.session_id], "matchid")
					endif

					if(has_key(self.cursors[a:body.client.session_id], "popup"))
						call self.cursors[a:body.client.session_id]["popup"].ClosePopup()
						call remove(self.cursors[a:body.client.session_id], "popup")
					endif
				else
					let hlGroup = "Cursor"
					while 1 
						let rand = rand(srand()) % 50
						if(!hlexists(hlGroup . rand))
							let hlGroup = hlGroup . rand
							exe "hi ".hlGroup. " ctermfg=NONE ctermbg=Blue guibg=".s:IdToColor(a:body.client.session_id)
							let self.cursors[a:body.client.session_id]["highlight"] = hlGroup
							break
						endif
					endwhile
				endif
				let self.cursors[a:body.client.session_id]["row"] = cursor[0]
				let self.cursors[a:body.client.session_id]["col"] = cursor[1]
				let self.cursors[a:body.client.session_id]["username"] = a:body.client.username
				let pattern = '\%'. cursor[0] . 'l' . '\%' . cursor[1] . 'c'
				let matchId = matchadd(self.cursors[a:body.client.session_id]["highlight"], pattern) 

				let self.cursors[a:body.client.session_id]["matchid"] = matchId
				let popupUser = g:POPUP_USER.New()
				call popupUser.SetOption(#{username: a:body.client.username, 
								\ propId: s:Hash(a:body.client.session_id),
								\ line: cursor[0], col: cursor[1], 
								\ highlight:self.cursors[a:body.client.session_id]["highlight"]})
				call popupUser.CreatePopup()
				let self.cursors[a:body.client.session_id]["popup"] = popupUser
				
				"call CooperCursor(cursor[0], cursor[1],a:body.client.username , s:IdToColor(a:body.client.session_id))
				"let timerId = timer_start(1000, function("s:CursorTimer", self.cursors[a:body.client.session_id]) ,{"repeat":-1})
				"let self.cursors[a:body.client.session_id]["timerid"] = timerId
			"endif
		else
			let self.cursors[a:body.client.session_id] = #{position:a:body.metadata.body.position}
			let cursor = s:PosFromIndex(self.textArea.bufnr, a:body.metadata.body.position)

			let hlGroup = "Cursor"
			let rand = rand(srand()) % 50
			let hlGroup = hlGroup . rand
			exe "hi ".hlGroup. " ctermfg=NONE ctermbg=Blue guibg=".s:IdToColor(a:body.client.session_id)
			
			let self.cursors[a:body.client.session_id]["highlight"] = hlGroup
			let self.cursors[a:body.client.session_id]["row"] = cursor[0]
			let self.cursors[a:body.client.session_id]["col"] = cursor[1]
			let self.cursors[a:body.client.session_id]["username"] = a:body.client.username
			let pattern = '\%'. cursor[0] . 'l' . '\%' . cursor[1] . 'c'
			let matchId = matchadd(self.cursors[a:body.client.session_id]["highlight"], pattern) 
			
			let self.cursors[a:body.client.session_id]["matchid"] = matchId
			let popupUser = g:POPUP_USER.New()
			call popupUser.SetOption(#{username: a:body.client.username, 
							\ propId: s:Hash(a:body.client.session_id),
							\ line: cursor[0], col: cursor[1], 
							\ highlight:hlGroup})
			call popupUser.CreatePopup()
			let self.cursors[a:body.client.session_id]["popup"] = popupUser

			"call CooperCursor(cursor[0], cursor[1],a:body.client.username ,s:IdToColor(a:body.client.session_id))
			"let timerId = timer_start(1000, function("s:CursorTimer", self.cursors[a:body.client.session_id]) ,{"repeat":-1})
			"let self.cursors[a:body.client.session_id]["timerid"] = timerId
		endif
	elseif(a:body.metadata.type == "user_unsubscribe" || a:body.metadata.type == "user_disconnect")
		if(has_key(self.cursors, a:body.client.session_id))
			if(has_key(self.cursors[a:body.client.session_id], "matchid"))
					call matchdelete(self.cursors[a:body.client.session_id]["matchid"])
					call remove(self.cursors[a:body.client.session_id], "matchid")
					call self.cursors[a:body.client.session_id]["popup"].ClosePopup()
					call remove(self.cursors[a:body.client.session_id], "popup")
					"call RemoveCursorPop(a:body.client.username)
				
			endif
		endif
	endif
endfun

" update cursor 
function! s:cooperBindVim.CursorTimer(timer) dict
	if(has_key(self, "isStay"))
		call matchdelete(self["matchid"])
		call remove(self, "matchid")
		call remove(self, "isStay")
	else
		let pattern = '\%'. self.row . 'l' . '\%' . self.col . 'c'
		let matchId = matchadd(self["highlight"], pattern) 
		let self.matchid = matchId
		let self.isStay = 1
	endif
endfun
 
" 
" @accessible
function! s:cooperBindVim.MetaData(body) dict
	if(a:body.document.id == self.documentId)
		if(self.ready)
			call self.UpdateUserInfo(a:body)
		endif
	endif
endfun

" @accessible
function! s:cooperBindVim.Connect(body) dict
	let username = "user" . rand(srand()) % 16
	let path = "/home/clouder/project/test123/"
	call self.cooperClient.OnNext("global_metadata", self.GlobalMata)
	call self.cooperClient.Send(#{projectid:"99351195",username:username,path:path})
endfun

" @accessible
function! s:cooperBindVim.Subscribe(body) dict
		let self.content = a:body.document.content
		
		"echom len(a:body.document.content)
		let lnum = 1
		let self.startSync = 1
		" bufadd添加的緩衝區如果沒有真實的文件則會被置位爲未加載,bufdo無法生效，需加載手動置位爲已加載，在切換buffer區後會被重新置位
		" 保險起見，每次執行bufdo前重新設置
		call setbufvar(self.textArea.bufnr, "&buflisted", 1)
		exe self.textArea.bufnr . 'bufdo! normal ggdG'
		let oldContent = @x
		let @x = a:body.document.content
		exe self.textArea.bufnr . 'bufdo! normal "xgP'
		let @x = oldContent

		let self.documentId = a:body.document.id
		let self.ready = 1
		let self.textArea.disabled = 0
		let self.startSync = 0
		call execute(1)
endfun

" trigger_diff triggers whenever a change may have occurred to the wrapped textarea element, and
" compares the old content with the new content. If a change has indeed occurred then a transform
" is generated from the comparison and dispatched via the leap_client.
" @accessible
" function! s:TriggerDiff(bufnr, start, end, added, changes) dict
" 	"echom b:cooperBindVim.startSync
" 	call SendDiff(self)
" endfun

" def! SendDiff(cooperBindVim: dict<any>)
" 	"echom cooperBindVim["startSync"]
" 	if cooperBindVim["startSync"] == 0
" 			call setbufvar(cooperBindVim.textArea.bufnr, "&buflisted", 1)
" 			let newContent = call(function(CreateInstance(g:COOPER_STR, {})["New"], CreateInstance(g:COOPER_STR, {})), [join(getbufline(cooperBindVim.textArea.bufnr, 1, "$"), "\n")])
			
" 			let oldContent = cooperBindVim["content"]
" 			if type(oldContent) == v:t_string
" 				oldContent = call(function(CreateInstance(g:COOPER_STR, {})["New"], CreateInstance(g:COOPER_STR, {})), [cooperBindVim["content"]])
" 			endif
" 			let newContentStr = call(function(newContent["Str"], newContent), [])
" 			let oldContentStr = call(function(oldContent["Str"], oldContent), [])
" 			let newContentUStr = call(function(newContent["UStr"], newContent), [])
" 			let oldContentUStr = call(function(oldContent["UStr"], oldContent), [])
" 			if !cooperBindVim.ready || newContentStr == oldContentStr
" 				return
" 			endif
			
" 			cooperBindVim["content"] = newContent
" 			let i = 0
" 			let j = 0
" 			while len(oldContentUStr) > i && len(newContentUStr) > i && newContentUStr[i] == oldContentUStr[i]
" 				 i = i + 1 
" 			endwhile

" 			while (newContentUStr[(len(newContentUStr) - 1 - j)] == oldContentUStr[(len(oldContentUStr) - 1 - j)]) 
" 					\ && ((i + j) < len(newContentUStr)) 
" 					\ && ((i + j) < len(oldContentUStr))
" 				j = j + 1
" 			endwhile
" 			let tform = #{position: i, num_delete: 0, insert: call(function(CreateInstance(g:COOPER_STR, {})["New"], CreateInstance(g:COOPER_STR, {})), [""])}
		
" 			if len(oldContentUStr) != (i + j) 
" 				tform["num_delete"] = (len(oldContentUStr) - (i + j))
" 			endif

" 			if len(newContentUStr) != (i + j) 
" 				tform["insert"] = call(function(CreateInstance(g:COOPER_STR, {})["New"], CreateInstance(g:COOPER_STR, {})), [list2str(newContentUStr[i : len(newContentUStr) - j - 1])])
" 			endif

" 			if has_key(tform, "insert") || has_key(tform, "num_delete")
" 				call call(function(cooperBindVim["cooperClient"]["SendTransform"], cooperBindVim["cooperClient"]), [cooperBindVim.documentId, tform])
" 			endif
" 		endif
" enddef

" @accessible
function! s:cooperBindVim.TriggerDiffbak(bufnr, start, end, added, changes) dict
		if(!self.startSync)
			call setbufvar(self.textArea.bufnr, "&buflisted", 1)
			let newContent = g:COOPER_STR.New(join(getbufline(self.textArea.bufnr, 1, "$"),"\n"))
			let oldContent = self.content
			if(type(oldContent) == v:t_string)
				let oldContent = g:COOPER_STR.New(self.content)
			endif

			if(!self.ready || newContent.Str() == oldContent.Str())
				return
			endif
			
			let self.content = newContent
			let i = 0
			let j = 0
			while(len(oldContent.UStr())>i && len(newContent.UStr())>i && newContent.UStr()[i] == oldContent.UStr()[i])
				 let i = i + 1 
			endwhile
			while((newContent.UStr()[(len(newContent.UStr())- 1 -j)] == oldContent.UStr()[(len(oldContent.UStr())- 1 -j)]) 
					\ && ((i+j) < len(newContent.UStr())) 
					\ && ((i+j)<len(oldContent.UStr())))
				let j = j + 1
			endwhile
			let tform = #{position: i}
		
			if(len(oldContent.UStr()) != (i+j))
				let tform.num_delete = (len(oldContent.UStr()) - (i + j))
			endif

			if(len(newContent.UStr()) != (i + j)) 
				let tform.insert = g:COOPER_STR.New(list2str(newContent.UStr()[i:len(newContent.UStr()) - j - 1]))
			endif

			if(has_key(tform,"insert") || has_key(tform, "num_delete"))
				call self.cooperClient.SendTransform(self.documentId, tform)
				doautocmd CursorMovedI
			endif
		endif
endfun

" @accessible
function! s:cooperBindVim.Transforms(body) dict
	if(a:body.document.id == self.documentId)
		let transforms = a:body.transforms
		for tform in transforms
			call self.ApplyTransform(tform)
		endfor
		doautocmd CursorMovedI
		redraw!
	endif
endfun

" @accessible
function! s:cooperBindVim.Unsubscribe(body) dict
	if(a:body.document.id == self.documentId)
		let self.ready = 0
		let self.textArea.disabled = 1
	endif
endfun

function! s:IndexFromPos(bufnr, cursor)
	call setbufvar(a:bufnr, "&buflisted", 1)
	let content = join(getbufline(a:bufnr, 1, a:cursor[1] - 1),"\n")."\n"
	" len(str)爲字節長度，所以要把str轉爲list才是字符長度
	let len = len(str2list(content))
	let position = a:cursor[2] > 0 ?  (len + a:cursor[2] - 1) : len + a:cursor[2]
	return position
endfun

function! s:PosFromIndex(bufnr, position)
	call setbufvar(a:bufnr, "&buflisted", 1)
	let content = str2list(join(getbufline(a:bufnr, 1, "$"),"\n"))
	let left = content[0:a:position - 1]
	let lnum = count(list2str(left), "\n") + 1
	let col = a:position - len(str2list(join(getbufline(a:bufnr, 1, lnum -1),"\n")."\n"))
	return [lnum, col+1]
endfun

function! SendCursor()
	call call(function("s:SendCursorMetadata", b:cooperBindVim),[])
endfun

" @accessible
function! s:cooperBindVim.SendCursorMetadata() dict
	if(self.ready)
		let position = s:IndexFromPos(self.textArea.bufnr, getcurpos())
		call self.cooperClient.SendGlobalMetadata(#{
					\ type: "cursor_update",
					\ body: #{
					\	position: position,
					\	document: #{
					\		id: self.documentId			
					\	}			
					\ }		
			\ })
	endif
endfun

" @accessible
function! s:cooperBindVim.GlobalMata(body) dict
	if(self.ready)
		call self.UpdateUserInfo(a:body)
		if(a:body.metadata.type == "user_subscribe")
			if(a:body.metadata.body.document.id == self.documentId)
				call self.SendCursorMetadata()
			endif
		endif
	endif
endfun

function! s:Hash(str)
	let hash = 0
	let i = 0
	let chr = 0
	let len = 0

	if(type(a:str) != v:t_string || len(a:str) ==0)
		return 0
	endif
	let str = g:COOPER_STR.New(a:str)
	for i in range(len(str.UStr()))
		let chr = str.UStr()[i]
		let hash = float2nr(((hash * pow(2, 2)) - hash) + chr)
		let hash = or(hash, 0)
		let hash = hash + chr
	endfor

	return hash
endfun

function! s:HSVtoRGB(h, s, v)
	let r = 0
	let g = 0
	let b = 0
	let i = 0
	let f = 0
	let p = 0
	let q = 0
	let t = 0

	let h = a:h
	let s = a:s
	let v = a:v

	if((h == v:t_number || h == v:t_float) && s == v:null && v == v:null)
		let s = h.s
		let v = h.v
		let h = h.h
	endif

	let i = float2nr(floor(h * 6))
	let f = h * 6 - i
	let p = v * (1 - s)
	let q = v * (1 - f * s)
	let t = v * (1 - (1 - f) * s)

	if(i % 6 == 0)
		let r = v
		let g = t
		let b = p
	elseif(i % 6 == 1)
		let r = q
		let g = v
		let b = p
	elseif(i % 6 == 2)
		let r = p
		let g = v
		let b = t
	elseif(i % 6 == 3)
		let r = p
		let g = q
		let b = v
	elseif(i % 6 == 4)
		let r = t
		let g = p
		let b = v
	elseif(i % 6 == 5)
		let r = v
		let g = p
		let b = q
	endif
	
	return #{
		\ r:float2nr(floor(r * 255)),
		\ g:float2nr(floor(g * 255)),
		\ b:float2nr(floor(b * 255))
		\ }
endfun

" 6918036b-69ef-4672-be78-f656bd9d1042
" 9223372036854775807
" 1450142802809611

" 84d82031-08cc-4fbc-9be0-595895ea8010
function! s:IdToColor(id)
	let idHash = s:Hash(a:id)

	if(idHash < 0)
		let idHash = idHash * -1
	endif

	let hue = floor((idHash % 100000)) / 1000
	let rgb = s:HSVtoRGB(hue, 1 , 0.8)
	
	return printf("#%02x%02x%02x", rgb.r, rgb.g, rgb.b)
endfun

" @accessible
function! s:RestorePopup() dict
	for sessionId in keys(self.cursors)
		if(has_key(self.cursors, "popup"))
			call self.cursors[sessionId]["popup"].ClosePopup()
			call self.cursors[sessionId]["popup"].CreatePopup()
		else
			let popupUser = g:POPUP_USER.New()
			call popupUser.SetOption(#{username: self.cursors[sessionId]["username"], 
								\ line: self.cursors[sessionId]["row"], col: self.cursors[sessionId]["col"], 
								\ highlight:self.cursors[sessionId]["highlight"]})
			call popupUser.CreatePopup()
			let self.cursors[sessionId]["popup"] = popupUser
		endif
	endfor
endfun

function! TestIdToColor(id)
	"echom s:IdToColor(a:id)
endfun

