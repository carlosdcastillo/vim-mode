VimState = require './vim-state'

module.exports =
  configDefaults:
    'commandModeInputViewFontSize': 11
    'startInInsertMode': false

  _initializeWorkspaceState: ->
    atom.workspace.vimState ||= {}
    atom.workspace.vimState.registers ||= {}
    atom.workspace.vimState.searchHistory ||= []

  activate: (state) ->
    @_initializeWorkspaceState()
    atom.workspace.observeTextEditors (editor) =>

        console.log 'uri:',editor.getURI()
        editorView = atom.views.getView(editor)
        if editorView
            console.log 'view:',editorView
            #return unless editorView.attached
            #return if editorView.mini

            editorView.classList.add('vim-mode')
            editorView.vimState = new VimState(editorView)

  deactivate: ->
    atom.workspaceView?.eachEditorView (editorView) =>
      editorView.off('.vim-mode')
