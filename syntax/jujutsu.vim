" Vim syntax file
" Language: Jujutsu output
" Maintainer: Your Name
" Latest Revision: 2024-04-07

if exists("b:current_syntax")
  finish
endif

" Syntax highlighting for jujutsu status output
syntax match jujutsuHeader /^Working copy changes:/
syntax match jujutsuHeader /^Working copy :/
syntax match jujutsuHeader /^Parent commit:/

syntax match jujutsuModified /^M \S\+$/
syntax match jujutsuAdded /^A \S\+$/
syntax match jujutsuDeleted /^D \S\+$/
syntax match jujutsuUntracked /^U \S\+$/
syntax match jujutsuRenamed /^R \S\+$/
syntax match jujutsuCopied /^C \S\+$/

syntax match jujutsuCommitID /\<[0-9a-f]\{8}\>/
syntax match jujutsuChangeID /\<[a-z]\{8}\>/

syntax match jujutsuBookmark /\S\+@\w\+/
syntax match jujutsuRemote /@\w\+/

" Syntax highlighting for jujutsu diff output
syntax match jujutsuDiffHeader /^diff/
syntax match jujutsuDiffHunk /^@@ -\d\+,\d\+ +\d\+,\d\+ @@/
syntax match jujutsuDiffAdd /^+.*$/
syntax match jujutsuDiffRemove /^-.*$/

" Syntax highlighting for jujutsu blame output
syntax match jujutsuBlameCommitID /^\S\+ \S\+ /
syntax match jujutsuBlameAuthor /\<[^<>]\+<[^<>]\+>/

" Define the highlighting
hi def link jujutsuHeader Title
hi def link jujutsuModified Identifier
hi def link jujutsuAdded String
hi def link jujutsuDeleted Error
hi def link jujutsuUntracked Comment
hi def link jujutsuRenamed Type
hi def link jujutsuCopied Type

hi def link jujutsuCommitID Identifier
hi def link jujutsuChangeID Special
hi def link jujutsuBookmark Function
hi def link jujutsuRemote Type

hi def link jujutsuDiffHeader Title
hi def link jujutsuDiffHunk Special
hi def link jujutsuDiffAdd DiffAdd
hi def link jujutsuDiffRemove DiffDelete

hi def link jujutsuBlameCommitID Identifier
hi def link jujutsuBlameAuthor String

let b:current_syntax = "jujutsu"
