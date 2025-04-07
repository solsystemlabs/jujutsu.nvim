" Vim syntax file
" Language: Jujutsu log output
" Maintainer: Taylor Eernisse
" Latest Revision: 2025-04-07

if exists("b:current_syntax")
  finish
endif

" Syntax highlighting for jujutsu log output
syntax match jujutsuLogHeader /^Working copy:/
syntax match jujutsuLogHeader /^Local changes:/
syntax match jujutsuLogHeader /^Remote changes:/

" Commit ID and change ID patterns
syntax match jujutsuLogCommitID /\<[0-9a-z]\{8,12}\>/
syntax match jujutsuLogChangeID /\<[a-z]\{8}\>/
syntax match jujutsuLogWorkingCopy /@/

" Branch and bookmark patterns
syntax match jujutsuLogBookmark /\S\+@\w\+/
syntax match jujutsuLogRemote /@\w\+/

" Author information
syntax match jujutsuLogAuthor /\<[^<>]\+<[^<>]\+>/

" Graph elements
syntax match jujutsuLogGraphLine /[|/\\]/ contained
syntax match jujutsuLogGraphCross /[+*]/ contained
syntax match jujutsuLogGraph /^.\{-}[|/\\+*]/ contains=jujutsuLogGraphLine,jujutsuLogGraphCross

" Date patterns
syntax match jujutsuLogDate /\d\{4}-\d\{2}-\d\{2}/
syntax match jujutsuLogTime /\d\{2}:\d\{2}:\d\{2}/

" Define the highlighting
hi def link jujutsuLogHeader Title
hi def link jujutsuLogCommitID Identifier
hi def link jujutsuLogChangeID Special
hi def link jujutsuLogWorkingCopy Question
hi def link jujutsuLogBookmark Function
hi def link jujutsuLogRemote Type
hi def link jujutsuLogAuthor String
hi def link jujutsuLogGraphLine Comment
hi def link jujutsuLogGraphCross Comment
hi def link jujutsuLogGraph Comment
hi def link jujutsuLogDate PreProc
hi def link jujutsuLogTime PreProc

let b:current_syntax = "jujutsu-log"
