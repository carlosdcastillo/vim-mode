_ = require 'underscore-plus'
$ = require  'jquery'
{Point, Range} = require 'atom'
Marker = require 'atom'
net = require 'net'
os = require 'os'
util = require 'util'

Session = require 'msgpack5rpc'

if os.platform() is 'win32'
    CONNECT_TO = '\\\\.\\pipe\\neovim'
else
    CONNECT_TO = '/tmp/neovim/neovim'

DEBUG = false

lupdates = []
subscriptions = {}
subscriptions['redraw'] = false
screen = []
screen_f = []
scrolled = false
current_editor = undefined
editor_views = {}
active_change = true

scrolltopchange_subscription = undefined
bufferchange_subscription = undefined
scrolltop = undefined
internal_change = false
updating = false
internal_change_timeout_var = undefined
updating_change_timeout_var = undefined

element = document.createElement("item-view")
setInterval ( -> ns_redraw_win_end()), 150

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


socket2 = new net.Socket()
socket2.connect(CONNECT_TO)
socket2.on('error', (error) ->
    console.log 'error communicating (send message): ' + error
    socket2.destroy()
)
tmpsession = new Session()
tmpsession.attach(socket2, socket2)

class RBuffer
    constructor:(data) ->
        @data = data
    
class RWindow
    constructor:(data) ->
        @data = data
        
class RTabpage
    constructor:(data) ->
        @data = data

session = undefined
types = []
tmpsession.request('vim_get_api_info', [], (err, res) ->
    metadata = res[1]
    constructors = [
        RBuffer
        RWindow
        RTabpage
    ]
    i = 0
    l = constructors.length
    while i < l
        ((constructor) ->
            types.push
                constructor: constructor
                code: metadata.types[constructor.name[1..]].id
                decode: (data) ->
                    new constructor(data)
                encode: (obj) ->
                    obj.data
            return
        ) constructors[i]
        i++


    tmpsession.detach()
    socket = new net.Socket()
    socket.connect(CONNECT_TO)
    session = new Session(types)
    session.attach(socket, socket)
)
 
buf2str = (buffer) ->
    if not buffer
        return ''
    res = ''
    i = 0
    while i < buffer.length
        res = res + String.fromCharCode(buffer[i])
        i++
    res

neovim_send_message = (message,f = undefined) ->
    try
        session.request(message[0], message[1], (err, res) ->
            if f
                if typeof(res) is 'number'
                    f(util.inspect(res))
                else
                    f(res)
        )
    catch err
        console.log 'error in neovim_send_message '+err


neovim_set_text = (text, start, end, delta) ->
    lines = text.split('\n')
    lines = lines[0..lines.length-2]
    neovim_send_message(['vim_get_current_buffer',[]],
        ((buf) ->
            console.log 'buff',buf
            neovim_send_message(['buffer_line_count',[buf]],
                ((vim_cnt) ->
                    console.log 'vimcnt',vim_cnt
                    neovim_send_message(['buffer_get_line_slice', [buf, 0, 
                                                                    parseInt(vim_cnt), true, 
                                                                    false]], 
                        ((vim_lines_r) ->
                            vim_lines = []
                            for item in vim_lines_r
                                vim_lines.push buf2str(item)
                            console.log 'vim_lines', vim_lines
                            console.log 'lines',lines
                            l = []
                            pos = 0
                            for pos in [0..vim_lines.length + delta - 1]
                                item = vim_lines[pos]
                                if pos < start
                                    l.push(item)

                                if pos >= start and pos <= end + delta
                                    l.push(lines[pos])
                                
                                if pos > end + delta
                                    l.push(vim_lines[pos-delta])

                            neovim_send_message(['buffer_set_line_slice', 
                                                [buf,0,l.length,true]],
                                                del_line(buf,l,delta,-delta))
                        )
                    )
                )
            )
        )
    )

del_line = (buf, l, delta, i) ->
    ( ->
        if delta < 0 and i isnt 0
            neovim_send_message(['buffer_del_line', [buf, l.length + i]], 
                                del_line(buf, l, delta, i-1))
        else
            neovim_send_message(['vim_command',['redraw!']],
                ( ->
                    updating = false
                )
            )
    )


real_update = () ->
    if not updating
        updating = true

        curr_updates = lupdates.slice(0)
        lupdates = []

        mn = curr_updates[0].start
        mx = curr_updates[0].end
        tot = 0

        for item in curr_updates
            console.log 'item:',item
            if item.start < mn
                mn = item.start
            if item.end > mx
                mx = item.end
            tot = tot + item.delta

        item = curr_updates[curr_updates.length - 1]
        neovim_set_text(item.text, mn, mx, tot)
        setTimeout(( ->
            neovim_send_message(['vim_command',['redraw!']])
        ), 20)
        
register_change_handler = () ->
    bufferchange_subscription = current_editor.onDidChange ( (change)  ->

        q = current_editor.getText()
        if not internal_change and not updating
            if updating_change_timeout_var
                clearTimeout(updating_change_timeout_var)
            lupdates.push({text: q, start: change.start, \
                end: change.end, delta: change.bufferDelta})

            #updating_change_timeout_var =
                #setTimeout(( -> real_update()), 20)
            real_update()

    )


sync_lines = () ->

    neovim_send_message(['vim_eval',["line('$')"]], (nLines) ->
        if updating
            return
        if internal_change_timeout_var
            clearTimeout(internal_change_timeout_var)
        internal_change = true

        if current_editor
            if current_editor.buffer.getLastRow() < parseInt(nLines)
                nl = parseInt(nLines) - current_editor.buffer.getLastRow()
                diff = ''
                for i in [0..nl-1]
                    diff = diff + '\n'
                append_options = {normalizeLineEndings: true}
                current_editor.buffer.append(diff, append_options)
                neovim_send_message(['vim_command',['redraw!']])
            else if current_editor.buffer.getLastRow() > parseInt(nLines)
                for i in [parseInt(nLines)..current_editor.buffer.getLastRow()-1]
                    current_editor.buffer.deleteRow(i)

            #this should be done, but breaks everything, so I'm not doing it:

            #lines = current_editor.buffer.getLines()
            #pos = 0
            #for item in lines
            #    if item.length > 96
            #        options =  { normalizeLineEndings: true, undo: 'skip' }
            #        current_editor.buffer.setTextInRange(new Range(
            #            new Point(pos,96),
            #            new Point(pos,item.length)),'',options)
            #    pos = pos + 1

        internal_change_timeout_var =
            setTimeout(( -> internal_change = false), 5)
        #internal_change = false
    )

ns_redraw_win_end = () ->

    current_editor = atom.workspace.getActiveTextEditor()

    if not current_editor
        return

    uri = current_editor.getURI()

    editor_views[uri] = atom.views.getView(current_editor)

    if not editor_views[uri]
        return

    neovim_send_message(['vim_eval',['&modified']], (mod) ->
        mod = buf2str(mod)

        q = '.tab-bar .tab [data-path*="'
        q = q.concat(uri)
        q = q.concat('"]')
        #console.log q

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

    focused = editor_views[uri].classList.contains('is-focused')

    if true
        neovim_send_message(['vim_eval',["expand('%:p')"]], (filename) ->
            filename = buf2str(filename)
            #console.log 'filename reported by vim:',filename
            #console.log 'current editor uri:',uri

            ncefn =  normalize_filename(uri)
            nfn = normalize_filename(filename)

            if ncefn and nfn and nfn isnt ncefn
                console.log '-------------------------------',nfn
                console.log '*******************************',ncefn
                atom.workspace.open(filename)
                
            else

                sync_lines()
            )

    active_change = false
    for texteditor in atom.workspace.getTextEditors()
        turi = texteditor.getURI()
        if turi
            if turi[turi.length-1] is '~'
                texteditor.destroy()
            
    active_change = true

lineSpacing = ->
    lineheight = parseFloat(atom.config.get('editor.lineHeight'))
    fontsize = parseFloat(atom.config.get('editor.fontSize'))
    return Math.floor(lineheight * fontsize)

vim_mode_save_file = () ->
    console.log 'inside neovim save file'
    neovim_send_message(['vim_command',['write']])

scrollTopChanged = () ->
    if not internal_change
        if editor_views[current_editor.getURI()].classList.contains('is-focused')
            console.log 'scrolled'
            if scrolltop
                diff = scrolltop - current_editor.getScrollTop()
                if  diff > 0
                    console.log 'scroll up:',diff
                    neovim_send_message(['vim_input',['<ScrollWheelUp>']])
                else
                    console.log 'scroll down:',diff
                    neovim_send_message(['vim_input',['<ScrollWheelDown>']])
        else

            rng = current_editor.getSelectedBufferRange()
            if not rng.isEmpty()
                value = rng.end.row + 1
                neovim_send_message(['vim_input',[''+value+'G']])
                value = rng.end.column
                neovim_send_message(['vim_input',[''+value+'|']])

    scrolltop = current_editor.getScrollTop()


class EventHandler
    constructor: (@vimState) ->
        qtop = current_editor.getScrollTop()
        qbottom = current_editor.getScrollBottom()

        @rows = Math.floor((qbottom - qtop)/lineSpacing()+1)
        console.log 'rows:', @rows

        height = Math.floor(50+(@rows-0.5) * lineSpacing())

        atom.setWindowDimensions ('width': 1400, 'height': height)
        @cols = 100
        @command_mode = true

    handleEvent: (event, q) =>
        if q.length is 0
            return
        if updating
            return
            
        if internal_change_timeout_var
            clearTimeout(internal_change_timeout_var)
        internal_change = true
        dirty = (false for i in [0..@rows-2])

        if event is "redraw"
            #console.log "eventInfo", eventInfo
            for x in q
                if not x
                    continue
                x[0] = buf2str(x[0])
                if x[0] is "cursor_goto"
                    for v in x[1..]
                        try
                            v[0] = util.inspect(v[0])
                            v[1] = util.inspect(v[1])
                            @vimState.location[0] = parseInt(v[0])
                            @vimState.location[1] = parseInt(v[1])
                        catch
                            console.log 'problem in goto'

                else if x[0] is 'set_scroll_region'
                    @screen_top = parseInt(util.inspect(x[1][0]))
                    @screen_bot = parseInt(util.inspect(x[1][1]))
                    @screen_left = parseInt(util.inspect(x[1][2]))
                    @screen_right = parseInt(util.inspect(x[1][3]))

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
                        try
                            top = @screen_top
                            bot = @screen_bot + 1

                            left = @screen_left
                            right = @screen_right + 1

                            count = parseInt(util.inspect(v[0]))
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
                        catch
                            console.log 'problem scrolling'

                else if x[0] is "put"
                    cnt = 0
                    #console.log 'put:',x[1..]
                    for v in x[1..]
                        try
                            v[0] = buf2str(v[0])
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
                        catch
                            console.log 'problem putting'

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

        if scrolled
            neovim_send_message(['vim_command',['redraw!']])
            scrolled = false

        options =  { normalizeLineEndings: true, undo: 'skip' }
        if current_editor
            current_editor.buffer.setTextInRange(new Range(
                new Point(current_editor.buffer.getLastRow(),0),
                new Point(current_editor.buffer.getLastRow(),96)),'',
                options)
        internal_change_timeout_var =
            setTimeout(( -> internal_change = false), 5)
        #internal_change = false

module.exports =
class VimState
    editor: null
    mode: null
  
    constructor: (@editorView) ->
        @editor = @editorView.getModel()
        editor_views[@editor.getURI()] = @editorView
        @editorView.component.setInputEnabled(false)
        @mode = 'command'
        @cursor_visible = true
        @scrolled_down = false
        @tlnumber = 0
        @status_bar = []
        @location = []
    
        if not current_editor
            current_editor = @editor
        @changeModeClass('command-mode')
        @activateCommandMode()

        atom.packages.onDidActivatePackage(  ->
            element.innerHTML = ''
            @statusbar =
                document.querySelector('status-bar').addLeftTile(item:element,
                priority:10 )

        )

        atom.workspace.onDidChangeActivePaneItem @activePaneChanged
        atom.commands.add 'atom-text-editor', 'core:save', (e) ->
            e.preventDefault()
            e.stopPropagation()
            vim_mode_save_file()
    
        @editorView.onkeypress = (e) =>
            q1 = @editorView.classList.contains('is-focused')
            q2 = @editorView.classList.contains('autocomplete-active')
            if q1 and not q2
                q =  String.fromCharCode(e.which)
                neovim_send_message(['vim_input',[q]])
                false
            else
                true
    
        @editorView.onkeydown = (e) =>
            q1 = @editorView.classList.contains('is-focused')
            q2 = @editorView.classList.contains('autocomplete-active')
            if q1 and not q2 and not e.altKey
                translation = @translateCode(e.which, e.shiftKey, e.ctrlKey)
                if translation != ""
                    neovim_send_message(['vim_input',[translation]])
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
  
    activePaneChanged: =>
        if active_change
    
            if updating
                return
            if internal_change_timeout_var
                clearTimeout(internal_change_timeout_var)
            internal_change = true
            try

                filename = atom.workspace.getActiveTextEditor().getURI()
                neovim_send_message(['vim_command',['e '+ filename]],(x) =>
                    if scrolltopchange_subscription
                        scrolltopchange_subscription.dispose()
                    if bufferchange_subscription
                        bufferchange_subscription.dispose()
    
                    current_editor = atom.workspace.getActiveTextEditor()
                    if current_editor
                        scrolltopchange_subscription =
                            current_editor.onDidChangeScrollTop scrollTopChanged
    
                        register_change_handler()
    
                    scrolltop = undefined
    
                    @tlnumber = 0
                    @afterOpen()
                )
            catch err
    
                console.log err
                console.log 'problem changing panes'
    
            internal_change_timeout_var =
                setTimeout(( -> internal_change = false), 5)
            #internal_change = false
  
    afterOpen: =>
        #console.log 'in after open'
        neovim_send_message(['vim_command',['set scrolloff=2']])
        neovim_send_message(['vim_command',['set nocompatible']])
        neovim_send_message(['vim_command',['set noswapfile']])
        neovim_send_message(['vim_command',['set nowrap']])
        neovim_send_message(['vim_command',['set nu']])
        neovim_send_message(['vim_command',['set autochdir']])
        neovim_send_message(['vim_command',['set autoindent']])
        neovim_send_message(['vim_command',['set smartindent']])
        neovim_send_message(['vim_command',['set hlsearch']])
        neovim_send_message(['vim_command',['set tabstop=4']])
        neovim_send_message(['vim_command',['set shiftwidth=4']])
        neovim_send_message(['vim_command',['set expandtab']])
        neovim_send_message(['vim_command',['set hidden']])
        neovim_send_message(['vim_command',['set list']])
        neovim_send_message(['vim_command',['set wildmenu']])
        neovim_send_message(['vim_command',['set showcmd']])
        neovim_send_message(['vim_command',['set incsearch']])
        neovim_send_message(['vim_command',['set autoread']])
        neovim_send_message(['vim_command',
            ['set backspace=indent,eol,start']])
    
        if not subscriptions['redraw']
            #console.log 'subscribing, after open'
            @neovim_subscribe()
        #else
            #console.log 'NOT SUBSCRIBING, problem'
            #
    
    postprocess: (rows, dirty) ->
        screen_f = []
        for posi in [0..rows-1]
            line = undefined
            if screen[posi] and dirty[posi]
                line = []
                for posj in [0..screen[posi].length-2]
                    if screen[posi][posj]=='$' and screen[posi][posj+1]==' ' and
                       screen[posi][posj+2]==' '
                        break
                    line.push screen[posi][posj]
            else
                if screen[posi]
                    line = screen[posi]
            screen_f.push line
  
    redraw_screen:(rows, dirty) =>
        if current_editor
            @postprocess(rows, dirty)
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
    
                options =  { normalizeLineEndings: true, undo: 'skip' }
                #options =  { normalizeLineEndings:false }
    
                if DEBUG
                    initial = 0
                else
                    initial = 4
    
                for posi in [0..rows-2]
                    if not (tlnumberarr[posi] is -1)
                        if (tlnumberarr[posi] + posi == @tlnumber + posi) and dirty[posi]
                            qq = screen_f[posi]
                            qq = qq[initial..].join('')
                            linerange = new Range(new Point(@tlnumber+posi,0),
                                                    new Point(@tlnumber + posi, 96))
                            current_editor.buffer.setTextInRange(linerange,
                                qq, options)
                            dirty[posi] = false
    
            sbt = @status_bar.join('')
            @updateStatusBarWithText(sbt, (rows - 1 == @location[0]), @location[1])
    
            if @cursor_visible and @location[0] <= rows - 2
                if not DEBUG
                    current_editor.setCursorBufferPosition(
                        new Point(@tlnumber + @location[0],
                        @location[1]-4),{autoscroll:true})
                else
                    current_editor.setCursorBufferPosition(
                        new Point(@tlnumber + @location[0],
                        @location[1]),{autoscroll:true})
    
            current_editor.setScrollTop(lineSpacing()*@tlnumber)
  
    neovim_subscribe: =>
        console.log 'neovim_subscribe'
    
        eventHandler = new EventHandler this
    
        message = ['ui_attach',[eventHandler.cols,eventHandler.rows,true]]
        neovim_send_message(message)
    
        session.on('notification', eventHandler.handleEvent)
        #rows = @editor.getScreenLineCount()
        @location = [0,0]
        @status_bar = (' ' for ux in [1..eventHandler.cols])
        screen = ((' ' for ux in [1..eventHandler.cols])  for uy in [1..eventHandler.rows-1])
    
        subscriptions['redraw'] = true
  
  
  
  
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
        @changeModeClass('insert-mode')
        @updateStatusBar()
  
    activateInvisibleMode: (transactionStarted = false)->
        @mode = 'insert'
        @changeModeClass('invisible-mode')
        @updateStatusBar()
  
    changeModeClass: (targetMode) ->
        if current_editor
            editorview = editor_views[current_editor.getURI()]
            if editorview
                for mode in ['command-mode', 'insert-mode', 'visual-mode',
                            'operator-pending-mode', 'invisible-mode']
                    if mode is targetMode
                        editorview.classList.add(mode)
                    else
                        editorview.classList.remove(mode)
  
    updateStatusBarWithText:(text, addcursor, loc) ->
        if addcursor
            text = text[0..loc-1].concat('&#9632').concat(text[loc+1..])
        text = text.split(' ').join('&nbsp;')
        q = '<samp>'
        qend = '</samp>'
        element.innerHTML = q.concat(text).concat(qend)
  
    updateStatusBar: ->
        element.innerHTML = @mode

