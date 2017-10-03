
{Disposable, CompositeDisposable} = require 'event-kit'

VimState = require './vim-state'

module.exports =
  config:
    embed:
      type: 'boolean'
      default: false
  "neovim-path":
    type: 'string'
    default: '/usr/local/bin/nvim'

  activate: ->

    @disposables = new CompositeDisposable

    @disposables.add atom.workspace.observeTextEditors (editor) ->

      console.log 'uri:',editor.getURI()
      editorView = atom.views.getView(editor)

      if editorView
        console.log 'view:',editorView
        editorView.classList.add('vim-mode')
        editorView.vimState = new VimState(editorView)


  deactivate: ->

    atom.workspaceView?.eachEditorView (editorView) ->
      editorView.off('.vim-mode')

    @disposables.dispose()

