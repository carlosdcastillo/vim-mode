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
    # patch for react editor
    #DisplayBuffer = require "src/display-buffer"
    #DisplayBuffer::getScrollHeight = ->
    #  # patch code start
    #  lineHeight = if @getLineHeight then @getLineHeight() else @getLineHeightInPixels()
    #  if not lineHeight > 0
    #    throw new Error("You must assign lineHeight before calling ::getScrollHeight()")
    #  height = @getLineCount() * lineHeight
    #  height = height + @getHeight() - (lineHeight * 3)
    #  height
    #  # patch code end

    # patch for classic editor
    # EditorView = require "src/editor-view"
    # EditorView::updateLayerDimensions = ->
    #   height = @lineHeight * @editor.getScreenLineCount()
    #   # patch code start
    #   if @closest(".pane").length > 0 && atom.workspaceView.getActiveView() instanceof EditorView
    #     height = height + @height() - (@lineHeight * 3)
    #   # patch code end
    #   if @layerHeight != height
    #     @layerHeight = height
    #     @underlayer.height(@layerHeight)
    #     @renderedLines.height(@layerHeight)
    #     @overlayer.height(@layerHeight)
    #     @verticalScrollbarContent.height(@layerHeight)
    #     if @scrollBottom() > height
    #       @scrollBottom(height)
    #   minWidth = Math.max(@charWidth * @editor.getMaxScreenLineLength() + 20, @scrollView.width())
    #   if @layerMinWidth != minWidth
    #     @renderedLines.css('min-width', minWidth)
    #     @underlayer.css('min-width', minWidth)
    #     @overlayer.css('min-width', minWidth)
    #     @layerMinWidth = minWidth
    #     @trigger('editor:min-width-changed')
    @_initializeWorkspaceState()
    atom.workspaceView.eachEditorView (editorView) =>
      return unless editorView.attached
      return if editorView.mini

      editorView.addClass('vim-mode')
      editorView.vimState = new VimState(editorView)

  deactivate: ->
    atom.workspaceView?.eachEditorView (editorView) =>
      editorView.off('.vim-mode')
