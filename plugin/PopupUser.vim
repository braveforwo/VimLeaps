if(exists("g:POPUP_USER"))
	finish
endif

let s:popupUser = {}
let g:POPUP_USER = s:popupUser

call prop_type_add('popupMarker', {})
" @accessible
function! s:popupUser.New() dict 
	let popupUser = deepcopy(self)
	let popupUser.ID = -1
	let popupUser.username = ""
	let popupUser.line = -1
	let popupUser.col = -1
	let popupUser.highlight = ""
	let popupUser.flag = "🚩"
	let popupUser.sessionId = 0
	return popupUser
endfun

" @accessible
function! s:popupUser.CreatePopup() dict
	call prop_add(self.line, self.col - 1 > 0 ? self.col - 1 : 1, #{length:1, type:"popupMarker", id:self.propId})
	let self.ID = popup_create(self.flag.self.username, #{
				\pos: "botleft",
				\highlight: self.highlight,
				\textprop: "popupMarker",
				\textpropid: self.propId
				\})
	"echom self
endfun

" @accessible
function! s:popupUser.SetText(username) dict
	let self.username = a:username
	call popup_settext(self.ID, self.flag . self.username)
endfun

" @accessible
function! s:popupUser.SetOption(options) dict
	let self.username = a:options.username
        let self.line = a:options.line
	let self.col = a:options.col
	let self.highlight = a:options.highlight
	let self.propId = abs(a:options.propId)[0:4]
endfun

" @accessible
function! s:popupUser.PopupMove(options) dict
	let self.line = a:options.line
	let self.col = a:options.col
	call popup_move(self.ID, a:options)
endfun

" @accessible
function! s:popupUser.ClosePopup() dict
	call prop_remove(#{id: self.propId})
	call popup_close(self.ID)
endfun

function! PopupUserTest()
	let s:popup = g:POPUP_USER.New()
	call s:popup.SetOption(#{username: "username1", line: 2, col: 3, highlight: "CursorLineNr"})
	call s:popup.CreatePopup()
endfun

function! PopupSetTextTest()
	call s:popup.SetText("username3")
endfun

function! PopupMoveTest()
	call s:popup.PopupMove(#{line: 3, col: 3})
endfun

function! PopupCloseTest()
	call s:popup.ClosePopup()
endfun

