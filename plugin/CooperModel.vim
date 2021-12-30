if(exists("g:COOPER_MODEL"))
	finish
endif

" cooper_model is an object designed to keep track of the inbound and outgoing transforms
" for a local document, and updates the caller with the appropriate actions at each stage.


let s:cooperModel = {}
let g:COOPER_MODEL = s:cooperModel

" cooper_model has three states:
" 1. READY     - No pending sends, transforms received can be applied instantly to local document.
" 2. SENDING   - Transforms are being sent and we're awaiting the corrected version of those
"                transforms.
" 3. BUFFERING - A corrected version has been received for our latest send but we're still waiting
"                for the transforms that came before that send to be received before moving on.
" @accessible
function! s:cooperModel.New(id, baseVersion) dict
	let cooperModel = deepcopy(self)
	let cooperModel.id = a:id
	let cooperModel.READY = 1
	let cooperModel.SENDING = 2
	let cooperModel.BUFFERING = 3
	
	let cooperModel.cooperState = cooperModel.READY
	
	let cooperModel.correctedVersion = 0
	let cooperModel.version = a:baseVersion

	let cooperModel.unapplied = []
	let cooperModel.unsent = []
	let cooperModel.sending = v:null 
	return cooperModel
endfun

" Validate Transforms iterates an array of transform objects and validates that each transform
" contains the correct fields. Returns an error message as a string if there was a problem.
" @accessible
function! s:cooperModel.ValidateTransforms(transforms) dict
	for tform in a:transforms
		if(type(tform.position) != v:t_number)
			let tform.position = str2nr(tform.position)
			if(!has_key(tform, "position"))
				return "transform contained NaN value for position: " . string(tform)
			endif
		endif
		
		if(has_key(tform, "num_delete"))
			if(type(tform.num_delete) != v:t_number)
				let tform.num_delete = str2nr(tform.num_delete)
				if(!has_key(tform, "num_delete"))
					return "transform contained NaN value for num_delete: " . string(tform)
				endif
			endif
		else
			let tform.num_delete = 0
		endif
	
		if(has_key(tform,"version") && type(tform.version) != v:t_number)
			let tform.version = str2nr(tform.version)
			if(has_key(tform,"version"))
				return "transform contained NaN value for version: " . string(tform)
			endif
		endif

		if(has_key(tform,"insert"))
			try
				let tform.insert = g:COOPER_STR.New(tform.insert)
			catch
				echom v:exception
				return "transform contained non-string value for insert: " . string(tform)
			endtry
		else
			let tform.insert = g:COOPER_STR.New("")
		endif
	endfor
endfun

" MergeTransforms takes two transforms (the next to be sent, and the one that follows) and
" attempts to merge them into one transform. This will not be possible with some combinations, and
" the function returns a boolean to indicate whether the merge was successful.
"
" @accessible
function! s:cooperModel.MergeTransforms(first, second) dict
	let overlap = 0
	let remainder = 0
	let first =a:first
	let firstLen = len(first.insert.UStr())
	
	if((first.position + firstLen) == a:second.position)	
		let first.insert = g:COOPER_STR.New(first.insert.Str() . a:second.insert.Str())
		let first.num_delete = first.num_delete + a:second.num_delete
		return 1
	endif
	
	if(a:second.position == first.position)
		let remainder = max([0, a:second.num_delete - firstLen])
		let first.num_delete = first.num_delete + remainder
		let first.insert = g:COOPER_STR.New(a:second.insert.Str() . list2str(first.insert.UStr()[a:second.num_delete:]))
		return 1	
	endif

	if(a:second.position > first.position && a:second.position < (first.position + firstLen))
		let overlap = a:second.position - first.position
		let remainder = max([0, a:second.num_delete -(firstLen - overlap)])
		let first.num_delete = first.num_delete + remainder
		let first.insert = g:COOPER_STR.New(list2str(first.insert.UStr()[0: overlap-1]) . a:second.insert.Str() . first.insert.Str() . list2str(first.insert.UStr()[overlap + a:second.num_delete:]))
		return 1
	endif
	return 0
endfun

" CollideTransforms takes an unapplied transform from the server, and an unsent transform from the
" client and modifies both transforms.
"
" The unapplied transform is fixed so that when applied to the local document is unaffected by the
" unsent transform that has already been applied. The unsent transform is fixed so that it is
" unaffected by the unapplied transform when submitted to the server.
" 
" @accessible
function! s:cooperModel.CollideTransforms(unapplied, unsent) dict
	let earlier = {}
	let later = {}

	if(a:unapplied.position <= a:unsent.position)
		let earlier = a:unapplied
		let later = a:unsent
	else
		let earlier = a:unsent
		let later = a:unapplied
	endif

	let earlierLen = len(earlier.insert.UStr())
	let laterLen = len(later.insert.UStr())

	if(earlier.num_delete == 0)
		let later.position = later.position + earlierLen
	elseif((earlier.num_delete + earlier.position) <= later.position)
		let later.position = later.position + (earlierLen - earlier.num_delete)
	else
		let posGap = later.position - earlier.position
		let excess = max([0, earlier.num_delete - posGap])

		if(excess > later.num_delete)
			let earlier.num_delete = earlier.num_delete + (laterLen - later.num_delete)
			let earlier.insert = g:COOPER_STR.New(earlier.insert.Str() . later.insert.Str())
		else
			let earlier.num_delete = posGap
		endif

		let later.num_delete = max([0, later.num_delete - excess])
		let later.position = earlier.position + earlierLen
	endif
endfun

" resolve_state will prompt the cooper_model to re-evalutate its current state for validity. If this
" state is determined to no longer be appropriate then it will return an object containing the
" following actions to be performed.
" @accessible
function! s:cooperModel.ResolveState() dict
	if(self.cooperState == self.READY)
		
	elseif(self.cooperState == self.SENDING)
		return {}
	elseif(self.cooperState == self.BUFFERING)
		if((self.version + len(self.unapplied)) >= (self.correctedVersion - 1))
			let self.version = self.version + len(self.unapplied) + 1
			let toCollide = [self.sending] + self.unsent
			let unapplied = self.unapplied

			let self.unapplied = []

			for unappliedItem in unapplied
				for toCollideItem in toCollide
					call self.CollideTransforms(unappliedItem, toCollideItem)
				endfor
			endfor
			
			let self.sending = v:null
		
			if(len(self.unsent) > 0)
				let self.sending = remove(self.unsent,0)
				
				while(len(self.unsent) > 0 && self.MergeTransforms(self.sending, self.unsent[0]))
					call remove(self.unsent,0)
					"call self.unsent.Shift()
				endwhile

				let self.sending.version = self.version + 1
				
				let self.cooperState = self.SENDING
				return #{send:#{
					\ version: self.sending.version,
					\ num_delete: self.sending.num_delete,
					\ insert: self.sending.insert.Str(),
					\ position: self.sending.position},apply:unapplied}
			else
				let self.cooperState = self.READY
				return #{apply: unapplied}
			endif 
		endif
	endif
	return {}
endfun

" correct is the function to call following a "correction" from the server, this correction value
" gives the model the information it needs to determine which changes are missing from our model
" from before our submission was accepted.
" @accessible
function! s:cooperModel.Correct(version) dict
	if(self.cooperState == self.READY)
		
	elseif(self.cooperState == self.BUFFERING)
		return #{error: "received unexpected correct action"}
	elseif(self.cooperState == self.SENDING)
		let self.cooperState = self.BUFFERING
		let self.correctedVersion = a:version
		return self.ResolveState()
	endif

	return {}
endfun	

" submit is the function to call when we wish to submit more local changes to the server. The model
" will determine whether it is currently safe to dispatch those changes to the server, and will
" also provide each change with the correct version number.
" @accessible
function! s:cooperModel.Submit(transform) dict
	"echom "8888888"
	if(self.cooperState == self.READY)
		let self.cooperState = self.SENDING
		let a:transform.version = self.version + 1
		let self.sending = a:transform
		return #{send: #{
				\ version: self.sending.version,
				\ num_delete: self.sending.num_delete,
				\ insert: self.sending.insert.Str(),
				\ position: self.sending.position}}
	elseif(self.cooperState == self.BUFFERING)
	
	elseif(self.cooperState == self.SENDING)
		let self.unsent = self.unsent + [a:transform]
	endif
	return {}
endfun

"receive is the function to call when we have received transforms from our server. If we have
" recently dispatched transforms and have yet to receive our correction then it is unsafe to apply
" these changes to our local document, so the model will keep return these transforms to us when it
" is known to be safe.
" @accessible
function! s:cooperModel.Receive(transforms) dict
	"echom "101010"
	let expectedVersion = self.version + len(self.unapplied) + 1
	if((len(a:transforms) > 0) && (a:transforms[0].version != expectedVersion))
		return #{ error :
			\ "Received unexpected transform version: " . a:transforms[0].version .
			\	", expected: " . expectedVersion }
	endif
	
	if(self.cooperState == self.READY)
		let self.version = self.version + len(a:transforms)
		return #{apply: a:transforms}
	elseif(self.cooperState == self.BUFFERING)
		let self.unapplied = self.unapplied + a:transforms
		return self.ResolveState()
	elseif(self.cooperState == self.SENDING)
		let self.unapplied = self.unapplied + a:transforms
	endif
	return {}
endfun

