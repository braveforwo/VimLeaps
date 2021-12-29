if(exists("g:COOPER_CLIENT"))
	finish
endif

" cooper_client is the main tool provided to allow an easy and stable interface for 
" connecting to a coopers server.

let g:COOPER_CLIENT=expand("<sfile>:p")
call DefineClass(g:COOPER_CLIENT,{},[])

" @accessible
function! s:New() dict
	if(exists("g:syncChannel") && g:syncChannel != "")
		let self.socket = g:syncChannel
	else
		let self.socket = v:null
	endif
	
	let self.models = {}

	let self.EVENT_TYPE = #{
		\ CONNECT: "connect",
		\ DISCONNECT: "disconnect",
		\ SUBSCRIBE: "subscribe",
		\ UNSUBSCRIBE: "unsubscribe",
		\ TRANSFORMS: "transforms", 
		\ METADATA: "metadata",
		\ GLOBAL_METADATA: "global_metadata",
		\ ERROR: "error" }

	let self.events = {}
	let self.singleEvents = {}

	return deepcopy(self)
endfun

" on, attach a function to an event of the cooper_client. Use this to subscribe to
" transforms, document responses and errors etc.
" @accessible
function! s:On(name, subscriber) dict
	if(type(a:subscriber) != v:t_func)
		return "subscriber was not a function"
	endif

	if(has_key(self.events, a:name) && type(self.events[a:name]) == v:t_list)
		let self.events[a:name] = self.events[a:name] + [a:subscriber]
	else
		let self.events[a:name] = [a:subscriber]
	endif 
endfun

" OnNext, attach a function to the next trigger only of an event of the
" cooper_client.
" @accessible
function! s:OnNext(name, subscriber) dict
	if(type(a:subscriber) != v:t_func)
		return "subscriber was not a function"
	endif
	
	if(has_key(self.singleEvents, a:name) && type(self.singleEvents[a:name]) == v:t_list)
		let self.singleEvents[a:name] = self.singleEvents[a:name] + [a:subscriber]
	else
		let self.singleEvents[a:name] = [a:subscriber]
	endif 
endfun

" ClearHandlers, removes all functions subscribed to an event.
" @accessible
function! s:ClearHandlers(name) dict
	let self.events[a:name] = []
	let self.singleEvents[a:name] = []
endfun

" DispatchEvent, sends args to all subscribers of an event.
" @accessible
function! s:DispatchEvent(name, args) dict
	if(has_key(self.events, a:name) && type(self.events[a:name]) == v:t_list)
		for index in range(len(self.events[a:name]))
			call call(self.events[a:name][index], a:args)
		endfor
	endif

	if(has_key(self.singleEvents, a:name) && type(self.singleEvents[a:name]) == v:t_list)
		while(len(self.singleEvents[a:name]) > 0)
			let end = len(self.singleEvents[a:name])-1
			if(type(self.singleEvents[a:name][end]) == v:t_func)
				call call(self.singleEvents[a:name][end], a:args)
			endif
			call remove(self.singleEvents[a:name], -1)
		endwhile
	endif
endfun

" DoAction is a call that acts accordingly provided an action_obj from our cooper model
" @accessible
function! s:DoAction(modelId, actionObj) dict
	if(has_key(a:actionObj,"error"))
		return a:actionObj.error
	endif

	if(has_key(a:actionObj,"apply") && type(a:actionObj.apply) == v:t_list)
		call self.DispatchEvent(self.EVENT_TYPE.TRANSFORMS,[#{
						\ document:#{
						\	id: a:modelId
						\	},
						\ transforms: a:actionObj.apply
						\ }])
	endif

	if(has_key(a:actionObj,"send") && type(a:actionObj.send) == v:t_dict)
		call self.Send(#{
			\ type: "transform",
			\ body: #{
			\	document: #{	
			\		id: a:modelId
			\	},
			\	transform: a:actionObj.send
			\ }		
		\ })
	endif
endfun

" process_message is a call that takes a server provided message object and decides the
" appropriate action to take. If an error occurs during this process then an error message is
" returned.
" @accessible
function! s:ProcessMessage(message) dict
	let validateError = ""
	let actionObj = {}
	let actionErr = ""

	if(!has_key(a:message, "type") || type(a:message.type) != v:t_string)
		return "message received did not contain a valid type"
	endif
	
	if(!has_key(a:message, "body") || type(a:message.body) != v:t_dict)
		return "message received did not contain a valid body"
	endif

	let msgBody = a:message.body
	let documentId = ""

	if(a:message.type == "subscribe")
		if(type(msgBody.document) != v:t_dict || 
		\ type(msgBody.document.id) != v:t_string || 
		\ type(msgBody.document.content) != v:t_string ||
		\ msgBody.document.version <= 0 )
			return "message document type contained invalid document object"
		endif

		if(len(self.models) > 0)
			return
		endif

		let self.models[msgBody.document.id] = CreateInstance(g:COOPER_MODEL,{}).New(msgBody.document.id, msgBody.document.version)
		
		call self.DispatchEvent(self.EVENT_TYPE.SUBSCRIBE, [msgBody])
	
	elseif(a:message.type == "unsubscribe")
		if(type(msgBody.document) != v:t_dict || type(msgBody.document.id) != v:t_string)
			return "message document type contained invalid document object"
		endif
		let documentId = msgBody.document.id
		if(!has_key(self.models, documentId))
			return "transforms were received for unsubscribed document"
		endif
	
		call remove(self.models, msgBody.document.id)
		call self.DispatchEvent(self.EVENT_TYPE.UNSUBSCRIBE, [msgBody])

	elseif(a:message.type == "transforms")
		let documentId = msgBody.document.id
		let transforms = msgBody.transforms
		if(!has_key(self.models, documentId))
			return "transforms were received for unsubscribed document"
		endif

		let model = self.models[documentId]

		let validateError = model.ValidateTransforms(transforms)
		
		if(type(validateError) == v:t_string && validateError != "")
			return "received transforms with error: " . validate_error
		endif

		let actionObj = model.Receive(transforms)
		let actionErr = self.DoAction(documentId, actionObj)
		if(type(actionErr) == v:t_string && actionErr != "")
			return "failed to receive transforms: " . action_err
		endif

	elseif(a:message.type == "metadata")
		call self.DispatchEvent(self.EVENT_TYPE.METADATA, [msgBody])

	elseif(a:message.type == "global_metadata")
		call self.DispatchEvent(self.EVENT_TYPE.GLOBAL_METADATA, [msgBody])
		
	elseif(a:message.type == "correction")
		let documentId = msgBody.document.id
		if(!has_key(self.models, documentId))
			return "correction was received for unsubscribed document"
		endif
		
		if(type(msgBody.correction) != v:t_dict)
			return "correction received without body"
		endif

		if(type(msgBody.correction.version) != v:t_number)
			if(has_key(msgbody.correction, "version"))
				return "correction received was null"
			endif
			let msgBody.correction.version = str2nr(msgBody.correction.version)
		endif

		let model = self.models[documentId]

		let actionObj = model.Correct(msgBody.correction.version)
		let actionErr = self.DoAction(documentId, actionObj)
		if(type(actionErr) == v:t_string && actionErr != "")
			return "model failed to correct: " . action_err
		endif
	elseif(a:message.type == "error")
		"call LogDebug(msgBody)
		if(self.socket != v:null)
			call ch_close(self.socket)
		endif

		if(type(msgBody.error.message) == v:t_string)
			return msgBody.error.message
		endif
		return "server sent undeterminable error"
	else
		return "message received was not a recognised type"
	endif
endfun

" send_transform is the function to call to send a transform off to the server. To keep the local
" document responsive this transform should be applied to the document straight away. The
" cooper_client will decide when it is appropriate to dispatch the transform, and will manage
" internally how incoming messages should be altered to account for the fact that the local
" change was made out of order.
" @accessible
function! s:SendTransform(documentId,transform) dict
	if(!has_key(self.models, a:documentId))
		return "cooper_client must be subscribed to document before submitting transforms"
	endif
	let model = self.models[a:documentId]
	
	let validateError = model.ValidateTransforms([a:transform])
	
	if(type(validateError) == v:t_string && validateError != "")
		return validateError
	endif

	let actionObj = model.Submit(a:transform)
	let actionErr = self.DoAction(a:documentId, actionObj)
	if(type(actionErr) == v:t_string && actionErr != "")
		return "model failed to submit: " . actionErr
	endif
endfun

" send metadata out to all other users connected to your shared document.
" @accessible
function! s:SendMetadata(documentId,metadata) dict
	if(!has_key(self.models,a:documentId))
		return "cooper_client must be subscribed to document before submitting metadata"
	endif
      
	call self.Send(json_encode(#{
		\ type: "metadata",
		\ body: #{
		\	document: #{
		\		id: a:documentId
		\	},
		\	metadata:a:metadata,
		\	}
		\ }))
endfun

" send global metadata out to all other users connected
" to the coopers service.
" @accessible
function! s:SendGlobalMetadata(metadata) dict
	call self.Send(#{
		\ type: "global_metadata",
		\ body: #{
		\	metadata:a:metadata,
		\	}
		\ })
endfun

" subscribe to a document session, providing the initial content as well as
" subsequent changes to the document.
" @accessible
function! s:Subscribe(documentId) dict
	if(self.socket == v:null || ch_status(self.socket) != "open")
		return "cooper_client is not currently connected"
	endif
	
	if(type(a:documentId) != v:t_string)
		return "document id was not a string type"
	endif
	
	call self.Send(#{
		\ type: "subscribe",
		\ body: #{
		\ 	document: #{
		\		id: a:documentId
		\	}
		\ }
	\ })
endfun

" unsubscribe from a document session.
" @accessible
function! s:Unsubscribe(documentId) dict
	if(self.socket == v:null || ch_status(self.socket) != "open")
		return "cooper_client is not currently connected"
	endif
	
	if(type(a:documentId) != v:t_string)
		return "document id was not a string type"
	endif
	
	call self.Send(#{
		\ type: "unsubscribe",
		\ body: #{
		\ 	document: #{
		\		id: a:documentId
		\	}
		\ }
	\ })
endfun

" connect is the first interaction that should occur with the cooper_client after defining your event
" bindings. This function will generate a socket connection with the server, ready to bind to a
" document.
" @accessible
function! s:Connect(address) dict
	if(exists("g:syncChannel") && ch_status(g:syncChannel) == "open")	
		let self.socket = g:syncChannel
		return
	endif
	if(self.socket == v:null)
		let self.socket = ch_open(a:address, #{callback: "HandleMessage", mode:"raw", close_cb: self.OnClose})
		let g:syncChannel = self.socket
		if(ch_status(self.socket) == "open")
			"call self.OnOpen()
			return 1
		else
			return "socket connection failed"
		endif
	endif
endfun

"deal scoekr return message
" @accessible
function HandleMessage(channel, msg) 
	let provider = CreateInstance(g:SERVICE_PROVIDER_CLASS)
	
	for cooperBindVim in g:COOPERsVim
		let cooperObj = cooperBindVim.cooperClient

		try
			let messageObj = json_decode(a:msg)
			
		catch
			let message = split(a:msg,"\n")
			for msg in message
				let err = cooperObj.ProcessMessage(json_decode(msg))
				let cooperBindVims  = map(deepcopy(g:COOPERsVim), {val -> strpart(v:val["documentId"], 1, len(v:val["documentId"]))})
				let json = '{"operation":"cooper", "file":'. json_encode(cooperBindVims) .', "data":'.json_encode(msg).'}'
				call provider.ExecJavaScript(json)
			endfor
			return
		endtry
		let err = cooperObj.ProcessMessage(messageObj)
		let cooperBindVims  = map(deepcopy(g:COOPERsVim), {val -> strpart(v:val["documentId"], 1, len(v:val["documentId"]))})
		let json = '{"operation":"cooper", "file":'. json_encode(cooperBindVims) .', "data":'.json_encode(a:msg).'}'
		call provider.ExecJavaScript(json)
		"echom err
		if(type(err) == v:t_string)
			call cooperObj.DispatchEvent(cooperObj.EVENT_TYPE.ERROR, [#{
				\ error: #{
				\		type: "ERR_INTERNAL_MODEL",
				\		message: err			
				\	}
			\ }])
		endif
	endfor
endfun

" @accessible
function! s:Send(message) dict
	"echom json_encode(a:message)
	call ch_sendraw(self.socket, json_encode(a:message))
endfun

" @accessible
function! s:OnOpen() dict
	let cooperObj = self
	call cooperObj.DispatchEvent(cooperObj.EVENT_TYPE.CONNECT,[{}])
endfun

" Close the connection to the document and halt all operations.
" @accessible
function! s:OnClose(channel) dict
	let cooperObj = self
	unlet g:OnceConnect
	call cooperObj.DispatchEvent(cooperObj.EVENT_TYPE.DISCONNECT,[{}])
endfun

" @accessible
function! s:Close() dict
	if ( self.socket != v:null && ch_status(self.socket) != "open" ) 
		call ch_close(self.socket)
		self.socket = v:null;
	endif
	let self.model = v:null
endfun

"def! GetLastIndexFromArray(array: list<number>, charnum: number): number
"	let index = 0
"	let i = 1
"	for item in array
"		i = i + 1
"		if item == charnum
"			index = i
"		endif
"	endfor
"	return index
"enddef

function! GetLastIndexFromArray(array, charnum)
	let index = 0
	let i = 1
	for item in a:array
		let i = i + 1
		if item == a:charnum
			let index = i
		endif
	endfor
	return index
endfun

" @accessible
function! s:Apply(transform, content, binder) dict
	let numDelete = 0
	let toInsert = ""
	let content = a:content
	if(type(a:transform.position) != v:t_number)
		return content
	endif
	
	if(type(content) != v:t_dict)
		let content = CreateInstance(g:COOPER_STR,{}).New(content)
	endif

	if(type(a:transform.num_delete) == v:t_number)
		let numDelete = a:transform.num_delete
	endif

	if(has_key(a:transform,"insert"))
		let toInsert = CreateInstance(g:COOPER_STR,{}).New(a:transform.insert).Str()
	endif
	
	let left = ""
	if(a:transform.position == 0)
		let left = list2str(content.UStr()[-1:0])
	else
		let left = list2str(content.UStr()[0:a:transform.position-1])
	endif

	let middle = toInsert
	let right = list2str(content.UStr()[a:transform.position + numDelete:len(content.UStr())-1])
	let curpos = getcurpos()
	let lnum = 0
	let col = 0
	call setbufvar(a:binder.textArea.bufnr, "&buflisted", 1)
	let content = join(getbufline(a:binder.textArea.bufnr, 1, curpos[1] - 1), "\n")
	let content = content."\n".list2str(str2list(getbufline(a:binder.textArea.bufnr, curpos[1])[0])[0:curpos[2]-1])
	let position = len(str2list(content))
	if(position <= a:transform.position)
		let lnum = curpos[1]
		let col = curpos[2]
	elseif(position < a:transform.position + numDelete && position > a:transform.position)
		let lnum = count(left, "\n") + 1
		let temp = GetLastIndexFromArray(str2list(left), str2list("\n")[0])
		let startlineIndex = temp > 0 ? temp - 2  : 0
		let content = CreateInstance(g:COOPER_STR,{}).New(content)
		let col = len(content.UStr()[startlineIndex+1:a:transform.position-1 + len(middle) - 1]) + 1
	elseif(position >= a:transform.position + numDelete)
		let position = position - numDelete + len(middle)
		let leftPart = str2list(left . middle . right)[0:position-1]
		let lnum = count(list2str(leftPart), "\n") + 1
		let temp = GetLastIndexFromArray(leftPart, str2list("\n")[0])
		let startlineIndex = temp > 0 ? temp - 2  : 0
		let col = len(leftPart[startlineIndex+1:position-1]) 
	endif
	return [left . middle . right, lnum, col]
endfun

