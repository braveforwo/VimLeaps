" cooper_str is a wrapper around strings that stores lazy evaluated 
" codepoint arrays using the ES6triple dot operator.
" ---------------------------------------------------------------
if(exists("g:COOPER_STR"))
	finish
endif

let s:cooperStr = {}
let g:COOPER_STR = s:cooperStr

" Param any_str either a standard string or an array of unicode codepoints.
" @accessible
function! s:cooperStr.New(anystr) dict
	if(type(a:anystr)==v:t_dict)
		let self.str = a:anystr.Str()
		let self.ustr = a:anystr.UStr()
	elseif(type(a:anystr)==v:t_string) 
		let self.str = a:anystr
	elseif(type(a:anystr)==v:t_list)
		let self.ustr = a:anystr
	else
		throw "attempted to construct cooper_str with non-string/array type"
	endif	
	return deepcopy(self)	
endfun

" Returns the standard underlying string.
" @accessible
function! s:cooperStr.Str() dict
	if(!has_key(self,"str"))
		let self.str = list2str(self.ustr)
	endif
	return self.str
endfun

" Returns the underlying unicode codepoint array.
" @accessible
function! s:cooperStr.UStr() dict
	if(!has_key(self,"ustr"))
		let self.ustr = str2list(self.str)
	endif
	return self.ustr
endfun


