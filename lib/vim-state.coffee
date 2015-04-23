_ = require 'underscore-plus'
$ = require  'jquery'
{Point, Range} = require 'atom'
Marker = require 'atom'
net = require 'net'
os = require 'os'
MarkerView = require './marker-view'
msgpack = require './msgpack'

HighlightedAreaView = require './highlighted-area-view'

if os.platform() is 'win32'
    CONNECT_TO = '\\\\.\\pipe\\neovim581'
else
    CONNECT_TO = '/tmp/neovim/neovim581'

MESSAGE_COUNTER = 1
DEBUG = false

subscriptions = {}
subscriptions['redraw'] = false
socket_subs = null
collected = new Buffer(0)
screen = []
screen_f = []
scrolled = false
current_editor = undefined
editor_views = {}

scrolltopchange_subscription = undefined
scrolltop = undefined
internal_change = false

element = document.createElement("item-view")
setInterval ( => ns_redraw_win_end()), 500

range = (start, stop, step) ->
    if typeof stop is "undefined"
        # one param defined
        stop = start
        start = 0
    step = 1  if typeof step is "undefined"
    return []  if (step > 0 and start >= stop) or (step < 0 and start <= stop)
    result = []
    i = start
  
    while (if step > 0 then i < stop else i > stop)
        result.push i
        i += step
    result

normalize_filename = (filename) ->
    if filename
        filename = filename.split('\\').join('/')
    return filename

neovim_send_message = (message,f = undefined) ->
    try
        socket2 = new net.Socket()
        socket2.connect(CONNECT_TO)
        socket2.on('error', (error) =>
          console.log 'error communicating (send message): ' + error
          socket2.destroy()
        )
        #socket2.on('end', =>
          #socket2.destroy()
        #)
        socket2.on('data', (data) =>
          {value:q, trailing:t} = msgpack.decode_pub(msgpack.to_uint8array(data))
          if t isnt 0
              console.log 'not reliable'
          if f
              f(q[3])
          socket2.destroy()
        )
        message[1] = MESSAGE_COUNTER
        MESSAGE_COUNTER = (MESSAGE_COUNTER + 1) % 256
        msg2 = msgpack.encode_pub(message)
        #socket2.write(msg2, => socket2.end())
        socket2.write(msg2)
    catch err
        console.log 'error in neovim_send_message '+err


ns_redraw_win_end = () ->

    if not current_editor
        return

    if not editor_views[current_editor.getURI()]
        return

    neovim_send_message([0,1,'vim_eval',['&modified']], (mod) =>

        q = '.tab-bar .tab [data-path*="'
        q = q.concat(current_editor.getURI())
        q = q.concat('"]')
        console.log q

        tabelement = document.querySelector(q)
        if tabelement
            tabelement = tabelement.parentNode
            if tabelement
                if parseInt(mod) == 1
                    if not tabelement.classList.contains('modified')
                        tabelement.classList.add('modified')
                    tabelement.isModified = true
                else
                    if tabelement.classList.contains('modified')
                        tabelement.classList.remove('modified')
                    tabelement.isModified = false

    )

    focused = editor_views[current_editor.getURI()].classList.contains('is-focused')

    if focused 
        neovim_send_message([0,1,'vim_eval',["expand('%:p')"]], (filename) =>
            #console.log 'filename reported by vim:',filename
            #console.log 'current editor uri:',current_editor.getURI()

            ncefn =  normalize_filename(current_editor.getURI())
            nfn = normalize_filename(filename)
            console.log 'filename reported by vim:',nfn
            console.log 'current editor uri:',ncefn



            if filename and current_editor.getURI() and nfn isnt ncefn
                console.log 'trying to open using atom'
                atom.workspace.open(filename)
            else
                neovim_send_message([0,1,'vim_eval',["line('$')"]], (nLines) =>
                    if current_editor
                        if current_editor.buffer.getLastRow() < parseInt(nLines)
                            nl = parseInt(nLines) - current_editor.buffer.getLastRow()
                            diff = ''
                            for i in [0..nl-1]
                                diff = diff + '\n'
                            current_editor.buffer.append(diff, true)
                            neovim_send_message([0,1,'vim_command',['redraw!']])
                        else if current_editor.buffer.getLastRow() > parseInt(nLines)
                            for i in [parseInt(nLines)..current_editor.buffer.getLastRow()]
                                current_editor.buffer.deleteRow(i)


                        lines = current_editor.buffer.getLines()
                        pos = 0
                        for item in lines
                            if item.length > 96
                                options =  { normalizeLineEndings:false, undo: 'skip' }
                                current_editor.buffer.setTextInRange(new Range(
                                    new Point(pos,96),
                                    new Point(pos,item.length)),'',options)
                            pos = pos + 1

                )
            )

lineSpacing = ->
    lineheight = parseFloat(atom.config.get('editor.lineHeight')) 
    fontsize = parseFloat(atom.config.get('editor.fontSize'))
    return Math.floor(lineheight * fontsize)

vim_mode_save_file = () ->
    console.log 'inside neovim save file'
    neovim_send_message([0,1,'vim_command',['write']])

scrollTopChanged = () ->
    if not internal_change
        if editor_views[current_editor.getURI()].classList.contains('is-focused')
            console.log 'scrolled';
            if scrolltop
                diff = scrolltop - current_editor.getScrollTop()
                if  diff > 0
                    console.log 'scroll up:',diff
                    neovim_send_message([0,1,'vim_input',['<ScrollWheelUp>']])
                else
                    console.log 'scroll down:',diff
                    neovim_send_message([0,1,'vim_input',['<ScrollWheelDown>']])

    scrolltop = current_editor.getScrollTop()


class EventHandler
    constructor: (@vimState) ->
        qtop = current_editor.getScrollTop()
        qbottom = current_editor.getScrollBottom()

        @rows = Math.floor((qbottom - qtop)/lineSpacing()+1)
        console.log 'rows:', @rows

        @cols = 100
        @command_mode = true

    handleEvent: (data) =>
        internal_change = true
        dirty = (false for i in [0..@rows-2])
        collected = Buffer.concat([collected, data])
        i = collected.length
        while i >= 1
            try
                v = collected.slice(0,i)
                {value:q,trailing} = msgpack.decode_pub(msgpack.to_uint8array(v))
                if trailing >= 0
                    #console.log 'subscribe',q
                    [bufferId, eventName, eventInfo] = q
                    if eventName is "redraw"
                        #console.log "eventInfo", eventInfo
                        for x in eventInfo
                            if x[0] is "cursor_goto"
                                for v in x[1..]
                                    @vimState.location[0] = parseInt(v[0])
                                    @vimState.location[1] = parseInt(v[1])

                            else if x[0] is 'set_scroll_region'
                                @screen_top = parseInt(x[1][0])
                                @screen_bot = parseInt(x[1][1])
                                @screen_left = parseInt(x[1][2])
                                @screen_right = parseInt(x[1][3])

                            else if x[0] is "insert_mode"
                                @vimState.activateInsertMode()
                                @command_mode = false

                            else if x[0] is "normal_mode"
                                @vimState.activateCommandMode()
                                @command_mode = true

                            else if x[0] is "bell"
                                atom.beep()

                            else if x[0] is "cursor_on"
                                if @command_mode
                                    @vimState.activateCommandMode()
                                else
                                    @vimState.activateInsertMode()
                                @vimState.cursor_visible = true

                            else if x[0] is "cursor_off"
                                @vimState.activateInvisibleMode()
                                @vimState.cursor_visible = false

                            else if x[0] is "scroll"
                                for v in x[1..]
                                    top = @screen_top
                                    bot = @screen_bot + 1

                                    left = @screen_left
                                    right = @screen_right + 1

                                    count = parseInt(v[0])
                                    #console.log 'scrolling:',count
                                    #tlnumber = tlnumber + count
                                    if count > 0
                                        src_top = top+count
                                        src_bot = bot
                                        dst_top = top
                                        dst_bot = bot - count
                                        clr_top = dst_bot
                                        clr_bot = src_bot

                                    else
                                        src_top = top
                                        src_bot = bot + count
                                        dst_top = top - count
                                        dst_bot = bot
                                        clr_top = src_top
                                        clr_bot = dst_top

                                    #for posi in range(clr_top,clr_bot)
                                        #for posj in range(left,right)
                                            #screen[posi][posj] = ' '

                                    top = @screen_top
                                    bottom = @screen_bot
                                    left = @screen_left
                                    right = @screen_right
                                    #console.log 'left:',left
                                    if count > 0
                                        start = top
                                        stop = bottom - count + 1
                                        step = 1
                                    else
                                        start = bottom
                                        stop = top - count + 1
                                        step = -1

                                    for row in range(start,stop,step)

                                        dirty[row] = true
                                        target_row = screen[row]
                                        source_row = screen[row + count]
                                        for col in range(left,right+1)
                                            target_row[col] = source_row[col]

                                    for row in  range(stop, stop+count,step)
                                        for col in  range(left,right+1)
                                            screen[row][col] = ' '

                                    scrolled = true
                                    if count > 0
                                        @vimState.scrolled_down = true
                                    else
                                        @vimState.scrolled_down = false

                            else if x[0] is "put"
                                cnt = 0
                                #console.log 'put:',x[1..]
                                for v in x[1..]
                                    ly = @vimState.location[0]
                                    lx = @vimState.location[1]
                                    if 0<=ly and ly < @rows-1
                                        qq = v[0]
                                        screen[ly][lx] = qq[0]
                                        @vimState.location[1] = lx + 1
                                        dirty[ly] = true
                                    else if ly == @rows - 1
                                        qq = v[0]
                                        @vimState.status_bar[lx] = qq[0]
                                        @vimState.location[1] = lx + 1
                                    else if ly > @rows - 1
                                        console.log 'over the max'

                            else if x[0] is "clear"
                                #console.log 'clear'
                                for posj in [0..@cols-1]
                                    for posi in [0..@rows-2]
                                        screen[posi][posj] = ' '
                                        dirty[posi] = true

                                    @vimState.status_bar[posj] = ' '

                            else if x[0] is "eol_clear"
                                ly = @vimState.location[0]
                                lx = @vimState.location[1]
                                if ly < @rows - 1
                                    for posj in [lx..@cols-1]
                                        for posi in [ly..ly]
                                            if posj >= 0
                                                dirty[posi] = true
                                                screen[posi][posj] = ' '

                                else if ly == @rows - 1
                                    for posj in [lx..@cols-1]
                                        @vimState.status_bar[posj] = ' '
                                else if ly > @rows - 1
                                    console.log 'over the max'

                        @vimState.redraw_screen(@rows, dirty)

                    i = i - trailing
                    #console.log 'found message at:',i
                    collected = collected.slice(i,collected.length)
                    i = collected.length

                else

                    #@redraw_screen(rows)
                    break

            catch err
                #console.log err,i,collected.length
                console.log err
                console.log 'stack:',err.stack
                @vimState.redraw_screen(@rows, null)
                break

        if scrolled
            neovim_send_message([0,1,'vim_command',['redraw!']])
            scrolled = false

        options =  { normalizeLineEndings:false, undo: 'skip' }
        current_editor.buffer.setTextInRange(new Range(
                new Point(current_editor.buffer.getLastRow(),0),
                new Point(current_editor.buffer.getLastRow(),96)),'',
                options)
        internal_change = false 

module.exports =
class VimState
  editor: null
  mode: null

  constructor: (@editorView) ->
    @editor = @editorView.getModel()
    editor_views[@editor.getURI()] = @editorView
    @editorView.component.setInputEnabled(false);
    @mode = 'command'
    @cursor_visible = true
    @scrolled_down = false
    @tlnumber = 0
    @status_bar = []
    @location = []

    #
    #@area = new HighlightedAreaView(@editorView)
    #@area.attach()
    #

    if not current_editor
        current_editor = @editor
    @changeModeClass('command-mode')
    @activateCommandMode()

    atom.packages.once 'activated', ->
        element.innerHTML = ''
        @statusbar = document.querySelector('status-bar').addLeftTile(item:element,
                                                                        priority:10 )

    socket = new net.Socket()
    socket.connect(CONNECT_TO)

    socket.on('data', (data) =>
        {value:q,trailing} = msgpack.decode_pub(msgpack.to_uint8array(data))
        #console.log q
        #console.log trailing
        qq = q[3][1]
        #console.log 'data:',qq

        socket.end()
        socket.destroy()
    )
    msg = msgpack.encode_pub([0,1,'vim_get_api_info',[]])
    socket.write(msg)

    #if not subscriptions['redraw']
    #@neovim_subscribe()

    #atom.project.eachBuffer (buffer) =>
      #@registerChangeHandler(buffer)

    #atom.workspaceView.on 'pane-container:active-pane-item-changed', @activePaneChanged
    atom.workspace.onDidChangeActivePaneItem @activePaneChanged
    atom.commands.add 'atom-text-editor', 'core:save', (e) -> 
        e.preventDefault()
        e.stopPropagation()
        vim_mode_save_file()

    @editorView.onkeypress = (e) =>
        if @editorView.classList.contains('is-focused')
            q =  String.fromCharCode(e.which)
            neovim_send_message([0,1,'vim_input',[q]])
            false
        else
            true

    @editorView.onkeydown = (e) =>
        if @editorView.classList.contains('is-focused') and not e.altKey
            translation = @translateCode(e.which, e.shiftKey, e.ctrlKey)
            if translation != ""
                neovim_send_message([0,1,'vim_input',[translation]])
                false
        else
            true


  translateCode: (code, shift, control) ->
    console.log 'code:',code
    if control && code>=65 && code<=90
        String.fromCharCode(code-64)
    else if code>=8 && code<=10 || code==13 || code==27
        String.fromCharCode(code)
    else if code==35
        '<End>'
    else if code==36
        '<Home>'
    else if code==33
        '<PageUp>'
    else if code==34
        '<PageDown>'
    else if code==37
        '<left>'
    else if code==38
        '<up>'
    else if code==39
        '<right>'
    else if code==40
        '<down>'
    else if code==188 and shift
        '<lt>'
    else
        ""

  destroy_sockets:(editor) =>
    if subscriptions['redraw']
        if editor.getURI() != @editor.getURI()
            #subscriptions['redraw'] = false

            console.log 'unsubscribing'

            #message = [0,1,'ui_detach',[]]
            #message[1] = MESSAGE_COUNTER
            #MESSAGE_COUNTER = (MESSAGE_COUNTER + 1) % 256
            #console.log 'MESSAGE_COUNTER',MESSAGE_COUNTER
            #msg2 = encode_pub(message)

            #socket_subs.write(msg2)
            #socket_subs.end()
            #socket_subs.destroy()
            #socket_subs = null

            #collected = new Buffer(0)


  activePaneChanged: =>
    try
        neovim_send_message([0,1,'vim_command',['e '+
                            atom.workspace.getActiveTextEditor().getURI()]],(x) =>
            if scrolltopchange_subscription
                scrolltopchange_subscription.dispose()

            current_editor = atom.workspace.getActiveTextEditor()
            scrolltopchange_subscription = 
                current_editor.onDidChangeScrollTop scrollTopChanged 
            scrolltop = undefined

            @tlnumber = 0
            @afterOpen()
        )
    catch err

        console.log err
        console.log 'problem changing panes'

  afterOpen: =>
    #console.log 'in after open'
    neovim_send_message([0,1,'vim_command',['set scrolloff=2']])
    neovim_send_message([0,1,'vim_command',['set noswapfile']])
    neovim_send_message([0,1,'vim_command',['set nowrap']])
    neovim_send_message([0,1,'vim_command',['set nu']])
    neovim_send_message([0,1,'vim_command',['set autochdir']])
    neovim_send_message([0,1,'vim_command',['set autoindent']])
    neovim_send_message([0,1,'vim_command',['set smartindent']])
    neovim_send_message([0,1,'vim_command',['set hlsearch']])
    neovim_send_message([0,1,'vim_command',['set tabstop=4']])
    neovim_send_message([0,1,'vim_command',['set shiftwidth=4']])
    neovim_send_message([0,1,'vim_command',['set expandtab']])
    neovim_send_message([0,1,'vim_command',['set hidden']])
    neovim_send_message([0,1,'vim_command',['set list']])
    neovim_send_message([0,1,'vim_command',['set wildmenu']])
    neovim_send_message([0,1,'vim_command',['set showcmd']])
    neovim_send_message([0,1,'vim_command',['set incsearch']])
    neovim_send_message([0,1,'vim_command',['set autoread']])
    neovim_send_message([0,1,'vim_command',['set backspace=indent,eol,start']])
    neovim_send_message([0,1,'vim_command',['redraw!']])


    if not subscriptions['redraw']
        #console.log 'subscribing, after open'
        @neovim_subscribe()
    #else
        #console.log 'NOT SUBSCRIBING, problem'
        #

  postprocess: (rows) =>
    screen_f = []
    for posi in [0..rows-1]
        line = undefined
        if screen[posi]
            line = []
            for posj in [0..screen[posi].length-2]
                if screen[posi][posj]=='$' and screen[posi][posj+1]==' ' and 
                   screen[posi][posj+2]==' '
                    break
                line.push screen[posi][posj]
        screen_f.push line

  redraw_screen:(rows, dirty) =>
    @postprocess(rows)
    tlnumberarr = []
    for posi in [0..rows-1]
        try
            pos = parseInt(screen_f[posi][0..3].join(''))
            if not isNaN(pos)
                tlnumberarr.push (  (pos - 1) - posi  )
            else
                tlnumberarr.push -1
        catch err
            tlnumberarr.push -1

    if scrolled and @scrolled_down
        @tlnumber = tlnumberarr[tlnumberarr.length-2]
    else if scrolled and not @scrolled_down
        @tlnumber = tlnumberarr[0]
    else
        @tlnumber = tlnumberarr[0]

    if dirty
        onedirty = false
        for posi in [0..rows-2]
            if dirty[posi]
                onedirty = true
                break
        
        if onedirty
            for posi in [0..rows-2]
                qq = screen_f[posi]
                pos = parseInt(qq[0..3].join(''))
                if not isNaN(pos)
                    if (pos-1 == @tlnumber + posi) and dirty[posi]
                        if not DEBUG
                            qq = qq[4..].join('')
                        else
                            qq = qq[..].join('')   #this is for debugging

                        linerange = new Range(new Point(@tlnumber+posi,0),
                                                new Point(@tlnumber + posi, 96))
                        options =  { normalizeLineEndings:false, undo: 'skip' }
                        current_editor.buffer.setTextInRange(linerange, qq, options)
                        dirty[posi] = false

    sbt = @status_bar.join('')
    @updateStatusBarWithText(sbt)

    if @cursor_visible and @location[0] <= rows - 2
        if not DEBUG
            current_editor.setCursorBufferPosition(new Point(@tlnumber + @location[0], 
                                                        @location[1]-4),{autoscroll:true})
        else
            current_editor.setCursorBufferPosition(new Point(@tlnumber + @location[0], 
                                                        @location[1]),{autoscroll:true})

    current_editor.setScrollTop(lineSpacing()*@tlnumber)

  neovim_subscribe: =>
    console.log 'neovim_subscribe'
    if socket_subs == null
        socket_subs = new net.Socket()
        socket_subs.connect(CONNECT_TO)
        collected = new Buffer(0)

    socket_subs.on('error', (error) =>
      console.log 'error communicating (subscribe)'
    )

    eventHandler = new EventHandler this

    socket_subs.on('data', eventHandler.handleEvent)

    message = [0,1,'ui_attach',[eventHandler.cols,eventHandler.rows,true]]
    #rows = @editor.getScreenLineCount()
    @location = [0,0]
    @status_bar = (' ' for ux in [1..eventHandler.cols])
    screen = ((' ' for ux in [1..eventHandler.cols])  for uy in [1..eventHandler.rows-1])

    message[1] = MESSAGE_COUNTER
    MESSAGE_COUNTER = (MESSAGE_COUNTER + 1) % 256
    console.log 'MESSAGE_COUNTER',MESSAGE_COUNTER
    msg2 = msgpack.encode_pub(message)
    socket_subs.write(msg2)
    subscriptions['redraw'] = true


  # last deleted buffer.
  #
  # Returns nothing.
  registerChangeHandler: (buffer) ->
#    buffer.on 'changed', ({newRange, newText, oldRange, oldText}) =>
#      return unless @setRegister?
#      if newText == ''
#        @setRegister('"', text: oldText, type: Utils.copyType(oldText))

  ##############################################################################
  # Mode Switching
  ##############################################################################

  # Private: Used to enable command mode.
  #
  # Returns nothing.
  activateCommandMode: ->
    @mode = 'command'
    @changeModeClass('command-mode')
    @updateStatusBar()

  # Private: Used to enable insert mode.
  #
  # Returns nothing.
  activateInsertMode: (transactionStarted = false)->
    @mode = 'insert'
    #@editor.beginTransaction() unless transactionStarted
    @changeModeClass('insert-mode')
    @updateStatusBar()

  activateInvisibleMode: (transactionStarted = false)->
    @mode = 'insert'
    #@editor.beginTransaction() unless transactionStarted
    @changeModeClass('invisible-mode')
    @updateStatusBar()


  # Private: Get the input operator that needs to be told about about the
  # typed undo transaction in a recently completed operation, if there
  # is one.
  inputOperator: (item) ->
    return item unless item?
    return item if item.inputOperator?()
    return item.composedObject if item.composedObject?.inputOperator?()


  # Private: Used to enable visual mode.
  #
  # type - One of 'characterwise', 'linewise' or 'blockwise'
  #
  # Returns nothing.
  activateVisualMode: (type) ->
    @deactivateInsertMode()
    @mode = 'visual'
    @changeModeClass('visual-mode')
    @updateStatusBar()

  # Private: Used to enable operator-pending mode.
  activateOperatorPendingMode: ->
    @deactivateInsertMode()
    @mode = 'operator-pending'
    @submodule = null
    @changeModeClass('operator-pending-mode')
    @updateStatusBar()

  changeModeClass: (targetMode) ->
    #console.log 'query time:',current_editor.getURI()
    #console.log 'editor_views:',editor_views
    editorview = editor_views[current_editor.getURI()]
    for mode in ['command-mode', 'insert-mode', 'visual-mode', 
                'operator-pending-mode', 'invisible-mode']
        if mode is targetMode
            editorview.classList.add(mode)
        else
            editorview.classList.remove(mode)

  updateStatusBarWithText:(text) ->
    q = '<samp>'
    qend = '</samp>'
    element.innerHTML = q.concat(text).concat(qend)

  updateStatusBar: ->
    element.innerHTML = @mode

