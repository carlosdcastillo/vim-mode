_ = require 'underscore-plus'
$ = require  'jquery'
{Point, Range} = require 'atom'
Marker = require 'atom'
net = require 'net'
os = require 'os'
util = require 'util'

Session = require 'msgpack5rpc'

VimUtils = require './vim-utils'
VimGlobals = require './vim-globals'
VimSync = require './vim-sync'

if os.platform() is 'win32'
  CONNECT_TO = '\\\\.\\pipe\\neovim'
else
  CONNECT_TO = '/tmp/neovim/neovim'

DEBUG = false

COLS = 120

eventHandler = undefined
nrows = 10
ncols = 10
mode = 'command'
subscriptions = {}
subscriptions['redraw'] = false
screen = []
screen_f = []
scrolled = false
editor_views = {}
active_change = true
next_new_file_id = 0

scrolltopchange_subscription = undefined
bufferchange_subscription = undefined
bufferchangeend_subscription = undefined
cursorpositionchange_subscription = undefined

buffer_change_subscription = undefined
buffer_destroy_subscription = undefined

non_file_assoc_atom_to_nvim = {}
non_file_assoc_nvim_to_atom = {}

scrolltop = undefined
reversed_selection = false

element = document.createElement("item-view")
interval_sync = undefined
interval_timeout = undefined

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
  VimGlobals.session = new Session(types)
  VimGlobals.session.attach(socket, socket)
)

getMaxOccurrence = (arr) ->
  o = {}
  maxCount = 0
  maxValue = undefined
  m = undefined
  i = 0
  iLen = arr.length
  while i < iLen
    m = arr[i]
    if !o.hasOwnProperty(m)
      o[m] = 0
    ++o[m]
    if o[m] > maxCount
      maxCount = o[m]
      maxValue = m
    i++
  maxValue

#These two functions are a work around so we don't stack
#vim_evals in the middle of the user typing text.
#see: https://github.com/neovim/neovim/issues/3720

activate_timer = () ->
  f =  -> (
    ns_redraw_win_end()
  )
  g =  -> (
    console.log 'INNER',element.innerHTML
    text = element.innerHTML.split('&nbsp;').join(' ')
    if text
      text = text.split('<samp>')[1]
      if text
        text = text.split('</samp>')[0]
        console.log 'text:',text

        textb = text[0..text.length/2]
        text = text[text.length/2..text.length-1]
        text = text.split(' ').join('')
        console.log 'text:',text
        console.log 'textb:',textb
        if ((text.length==1 and mode=='command' and \
            textb.indexOf('VISUAL')==-1) )
          neovim_send_message(['vim_input',['<Esc>']])
        if (textb.indexOf('completion')==-1)
          interval_sync = setInterval(f, 100)
  )
  interval_timeout = setTimeout(g, 500)

deactivate_timer = () ->
  if interval_timeout
    clearTimeout(interval_timeout)
  if interval_sync
    clearInterval(interval_sync)

neovim_send_message = (message,f = undefined) ->
  try
    if message[0] and message[1]
      VimGlobals.session.request(message[0], message[1], (err, res) ->
        if f
          if typeof(res) is 'number'
            f(util.inspect(res))
          else
            f(res)
      )
  catch err
    console.log 'error in neovim_send_message '+err
    console.log 'm1:',message[0]
    console.log 'm2:',message[1]




#This code registers the change handler. The undo fix is a workaround
#a bug I was not able to detect what coupled an extra state when
#I did Cmd-X and then pressed u. Challenge: give me the set of reasons that
#trigger such situation in the code.

register_change_handler = () ->
  bufferchange_subscription = \
    VimGlobals.current_editor.onDidChange ( (change)  ->

      if not VimGlobals.internal_change and not VimGlobals.updating

        try
          last_text = VimGlobals.current_editor.getText()
          text_list_tmp = last_text.split('\n')
          text_list = []
          for item in text_list_tmp
            text_list.push item.split('\r').join('')

          undo_fix =
              not (change.start is 0 and change.end is text_list.length-1 \
                      and change.bufferDelta is 0)

          #undo_fix = true

          qtop = VimGlobals.current_editor.getScrollTop()
          qbottom = VimGlobals.current_editor.getScrollBottom()

          tln = Math.floor((qtop)/lineSpacing()+1)
          bot = Math.floor((qbottom )/lineSpacing()+1)
          bot2 = VimGlobals.current_editor.getLineCount()
          if bot2 < bot
            bot = bot2

          rows = bot - tln
          #valid_loc = not (change.bufferDelta is 0 and \
                  #change.end-change.start >= rows-3)  and \
                  #(change.start >= tln and \
              #change.start < tln+rows-3)

          valid_loc =  not (change.bufferDelta is 0 and \
              change.end-change.start >= rows) and \
              (change.start >= tln-1 and  change.start < bot)

          #console.log 'try tln:',tln,'start:',change.start, 'bot:',bot
          if undo_fix and valid_loc
            console.log 'change:',change
            console.log 'tln:',tln,'start:',change.start, 'rows:',rows
            console.log '(uri:',VimGlobals.current_editor.getURI(),\
              'start:',change.start
            console.log 'end:',change.end,'delta:',change.bufferDelta,')'
            #deactivate_timer()
            VimGlobals.lupdates.push({uri: VimGlobals.current_editor.getURI(), \
                    text: last_text, start: change.start, end: change.end, \
                    delta: change.bufferDelta})

            VimSync.real_update()
            #activate_timer()

        catch err
          console.log err
          console.log 'err: probably not a text editor window changed'

  )



#This code is called indirectly by timer and it's sole purpose is to sync the
# number of lines from Neovim -> Atom.

sync_lines = () ->

  if VimGlobals.updating
    return

  if VimGlobals.internal_change
    return

  if VimGlobals.current_editor
    VimGlobals.internal_change = true
    VimGlobals.updating = true
    neovim_send_message(['vim_eval',["line('$')"]], (nLines) ->

      if VimGlobals.current_editor.buffer.getLastRow() < parseInt(nLines)
        nl = parseInt(nLines) - VimGlobals.current_editor.buffer.getLastRow()
        diff = ''
        for i in [0..nl-2]
          diff = diff + '\n'
        append_options = {normalizeLineEndings: false}
        VimGlobals.current_editor.buffer.append(diff, append_options)

        neovim_send_message(['vim_command',['redraw!']],
            (() ->
              VimGlobals.internal_change = false
              VimGlobals.updating = false
            )
         )
      else if VimGlobals.current_editor.buffer.getLastRow() > parseInt(nLines)
        for i in [parseInt(nLines)..\
            VimGlobals.current_editor.buffer.getLastRow()-1]
          VimGlobals.current_editor.buffer.deleteRow(i)

        neovim_send_message(['vim_command',['redraw!']],
            (() ->
              VimGlobals.internal_change = false
              VimGlobals.updating = false
            )
         )
      else
        VimGlobals.internal_change = false
        VimGlobals.updating = false

      )

# This is directly called by timer and makes sure of a bunch of housekeeping
#functions like, marking the buffer modified, working around some Neovim for
#Windows issues and invoking the code to sync the number of lines.

ns_redraw_win_end = () ->

  VimGlobals.current_editor = atom.workspace.getActiveTextEditor()

  if not VimGlobals.current_editor
    return

  uri = VimGlobals.current_editor.getURI()

  if not uri
    uri = 'newfile'+next_new_file_id
    next_new_file_id = next_new_file_id + 1

  #console.log 'URI:',uri

  editor_views[uri] = atom.views.getView(VimGlobals.current_editor)

  if not editor_views[uri]
    return


  focused = editor_views[uri].classList.contains('is-focused')


  qtop = VimGlobals.current_editor.getScrollTop()
  qbottom = VimGlobals.current_editor.getScrollBottom()
  qrows = Math.floor((qbottom - qtop)/lineSpacing()+1)

  qleft = VimGlobals.current_editor.getScrollLeft()
  qright= VimGlobals.current_editor.getScrollRight()
  qcols = Math.floor((qright-qleft)/lineSpacingHorizontal())-1


  if (nrows isnt qrows or ncols isnt qcols)
    editor_views[uri].vimState.neovim_resize(180, qrows)
    nrows = qrows
    ncols = qcols


  if not VimGlobals.updating and not VimGlobals.internal_change
    neovim_send_message(['vim_eval',["expand('%:p')"]], (filename) ->
      if filename.indexOf('term://') == -1
        filename = filename.replace /^\s+|\s+$/g, ""
        console.log 'filename after processing:', filename
        if filename is ''
          filename = 'newfile'+next_new_file_id
          next_new_file_id = next_new_file_id + 1

        #console.log 'orig filename reported by vim:',filename
        ncefn =  VimUtils.normalize_filename(uri)
        nfn = VimUtils.normalize_filename(filename)

        if ncefn and nfn and nfn isnt ncefn
          #console.log '-------------------------------',nfn
          #console.log '*******************************',ncefn
          atom.workspace.open(filename)

        #else
        #  if filename and uri
        #    sync_lines()
      else if filename of non_file_assoc_nvim_to_atom
        
      else
        tmpfilename = 'newfile'+next_new_file_id
        next_new_file_id = next_new_file_id + 1
        non_file_assoc_atom_to_nvim[tmpfilename] = filename
        non_file_assoc_nvim_to_atom[filename] = tmpfilename
        atom.workspace.open(tmpfilename)
        #sync_lines()
    )

  active_change = false
  for texteditor in atom.workspace.getTextEditors()
    turi = texteditor.getURI()
    if turi
      if turi[turi.length-1] is '~'
        texteditor.destroy()
    if not turi
      texteditor.destroy()

  active_change = true

lineSpacing = ->
  lineheight = parseFloat(atom.config.get('editor.lineHeight'))
  fontsize = parseFloat(atom.config.get('editor.fontSize'))
  return Math.floor(lineheight * fontsize)

lineSpacingHorizontal = ->
  fontsize = parseFloat(atom.config.get('editor.fontSize'))
  return Math.floor(fontsize*0.6)

vim_mode_save_file = () ->
  #console.log 'inside neovim save file'
  #
  VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
  neovim_send_message(['vim_command',['write!']])
  setTimeout( ( ->
    VimGlobals.current_editor.buffer.reload()
    VimGlobals.internal_change = false
    VimGlobals.updating = false
  ), 500)

  #VimGlobals.current_editor.setText(a)

cursorPosChanged = (event) ->

  if not VimGlobals.internal_change
    VimGlobals.internal_change = true

    if (VimGlobals.current_editor and \
            editor_views[VimGlobals.current_editor.getURI()].\
            classList.contains('is-focused'))
      pos = event.newBufferPosition
      rp = pos.row + 1
      cp = pos.column + 1
      sel = VimGlobals.current_editor.getSelectedBufferRange()
      r = sel.end.row + 1
      c = sel.end.column + 1
      reversed_selection = false
      console.log '!!!!!!!!!!!!!!!!!!!!!!!!!',r,rp,c,cp
      if r isnt rp or c isnt cp
        r = sel.start.row + 1
        c = sel.start.column + 1
        reversed_selection = true


      #console.log 'sel:',sel
      neovim_send_message(['vim_command',['cal cursor('+r+','+c+')']],
          (() ->
            if not sel.isEmpty()
              VimGlobals.current_editor.setSelectedBufferRange(sel,\
                {reversed:reversed_selection})
          )
      )
      VimGlobals.internal_change = false

scrollTopChanged = () ->
  if not VimGlobals.internal_change and not VimGlobals.updating
    if VimGlobals.current_editor
      if editor_views[VimGlobals.current_editor.getURI()].\
        classList.contains('is-focused')

      else
        up = false
        if scrolltop
          diff = scrolltop - VimGlobals.current_editor.getScrollTop()
          if diff > 0
            up = false
          else
            up = true

        sels = VimGlobals.current_editor.getSelectedBufferRanges()
        #console.log 'sels:',sels
        for sel in sels
          if up
            r = sel.start.row + 1
            c = sel.start.column + 1
          else
            r = sel.end.row + 1
            c = sel.end.column + 1
          #console.log 'sel:',sel
          neovim_send_message(['vim_command',['cal cursor('+r+','+c+')']],
              (() ->
                if not sel.isEmpty()
                  VimGlobals.current_editor.setSelectedBufferRange(\
                    sel,{selected: up})
              )
          )

  if VimGlobals.current_editor
    scrolltop = VimGlobals.current_editor.getScrollTop()


destroyPaneItem = (event) ->
  if event.item
    console.log 'destroying pane, will send command:', event.item
    console.log 'b:', event.item.getURI()
    uri =event.item.getURI()
    neovim_send_message(['vim_eval',["expand('%:p')"]],
        ((filename) ->

            #filename = VimUtils.buf2str(filename)
          console.log 'filename reported by vim:',filename
          console.log 'current editor uri:',uri
          ncefn =  VimUtils.normalize_filename(uri)
          nfn =  VimUtils.normalize_filename(filename)

          if ncefn and nfn and nfn isnt ncefn
            console.log '-------------------------------',nfn
            console.log '*******************************',ncefn

            neovim_send_message(['vim_command',['e! '+ncefn]],
                (() ->
                  neovim_send_message(['vim_command',['bd!']])
                )
            )

          else
            neovim_send_message(['vim_command',['bd!']])
      )

    )
    console.log 'destroyed pane'

activePaneChanged = () ->
  if active_change
    cnt = 0
    while ( VimGlobals.updating or VimGlobals.internal_change)
      console.log 'waiting for conditions'
      cnt = cnt + 1
      if cnt > 50
        return

    VimGlobals.tlnumber = -9999
    VimGlobals.updating = true
    VimGlobals.internal_change = true

    try
      VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
      if VimGlobals.current_editor
        filename = atom.workspace.getActiveTextEditor().getURI()
        filename2 = filename.split('/')
        if filename2[filename2.length-1] of non_file_assoc_atom_to_nvim
          cmd = 'b '+ non_file_assoc_atom_to_nvim[filename2[filename2.length-1]]
          for key, value of non_file_assoc_atom_to_nvim
            console.log 'key:',key, 'value:',value
          console.log 'CMD: ', cmd
        else
          if filename
            cmd = 'e! '+ filename
          else
            cmd = 'e! newfile'+next_new_file_id
            next_new_file_id = next_new_file_id + 1

          neovim_send_message(['vim_command',[cmd]],(x) ->

            if scrolltopchange_subscription
              scrolltopchange_subscription.dispose()
            if cursorpositionchange_subscription
              cursorpositionchange_subscription.dispose()

            VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
            if VimGlobals.current_editor
              scrolltopchange_subscription =
                VimGlobals.current_editor.onDidChangeScrollTop scrollTopChanged

              cursorpositionchange_subscription =
                VimGlobals.current_editor.onDidChangeCursorPosition \
                  cursorPosChanged

              if bufferchange_subscription
                bufferchange_subscription.dispose()

              if bufferchangeend_subscription
                bufferchangeend_subscription.dispose()

              register_change_handler()

            scrolltop = undefined

            editor_views[VimGlobals.current_editor.getURI()].\
              vimState.afterOpen()
          )
    catch err

      console.log err
      console.log 'problem changing panes'

    VimGlobals.internal_change = false
    VimGlobals.updating = false

class EventHandler
  constructor: (@vimState) ->
    qtop = VimGlobals.current_editor.getScrollTop()
    qbottom = VimGlobals.current_editor.getScrollBottom()

    @rows = Math.floor((qbottom - qtop)/lineSpacing()+1)

    nrows = @rows
    #console.log 'rows:', @rows

    height = Math.floor(30+(@rows) * lineSpacing())

    atom.setWindowDimensions ('width': 1400, 'height': height)

    qleft = VimGlobals.current_editor.getScrollLeft()
    qright= VimGlobals.current_editor.getScrollRight()

    @cols = Math.floor((qright-qleft)/lineSpacingHorizontal())-1

    COLS = @cols
    @rows = Math.floor((qbottom - qtop)/lineSpacing()+1)
    screen = ((' ' for ux in [1..@cols])  for uy in [1..@rows+2])
    @command_mode = true

  handleEvent: (event, q) =>
    if q.length is 0
      return
    if VimGlobals.updating
      return

    VimGlobals.internal_change = true
    dirty = (false for i in [0..@rows-1])

    if event is "redraw" and subscriptions['redraw']
        #console.log "eventInfo", eventInfo
      for x in q
        if not x
          continue
        #x[0] = VimUtils.buf2str(x[0])
        if x[0] is "cursor_goto"
          for v in x[1..]
            try
              v[0] = util.inspect(v[0])
              @vimState.location[0] = parseInt(v[0])
            catch
              @vimState.location[0] = 0
              console.log 'problem in goto'

            try
              v[1] = util.inspect(v[1])
              @vimState.location[1] = parseInt(v[1])
            catch
              @vimState.location[1] = 0
              console.log 'problem in goto'
                
        else if x[0] is 'set_scroll_region'
          @screen_top = parseInt(util.inspect(x[1][0]))
          @screen_bot = parseInt(util.inspect(x[1][1]))
          @screen_left = parseInt(util.inspect(x[1][2]))
          @screen_right = parseInt(util.inspect(x[1][3]))

        else if x[0] is "mode_change"
          if x[1][0] is 'insert'
            @vimState.activateInsertMode()
            @command_mode = false
          else if x[1][0] is 'normal'
            @vimState.activateCommandMode()
            @command_mode = true
          else if x[1][0] is 'replace'
            @vimState.activateReplaceMode()
            @command_mode = true
          else
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

              if not v
                console.log 'not v'
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
                stop = top - count - 1
                step = -1


              if count > 0
                for row in VimUtils.range(start,stop,step)
                  dirty[row] = true
                  target_row = screen[row]
                  source_row = screen[row + count]
                  for col in VimUtils.range(left,right+1)
                    target_row[col] = source_row[col]

                for row in  VimUtils.range(stop, stop+count,step)
                  for col in  VimUtils.range(left,right+1)
                    if screen[row]
                      screen[row][col] = ' '
                      dirty[row] = true
              else
                for row in VimUtils.range(start,stop,step)
                  dirty[row] = true
                  target_row = screen[row]

                  source_row = screen[row + count]
                  for col in VimUtils.range(left,right+1)
                    target_row[col] = source_row[col]

                for row in  VimUtils.range(stop, stop+count-1,step)
                  for col in  VimUtils.range(left,right+1)
                    if screen[row]
                      screen[row][col] = ' '
                      dirty[row] = true

              scrolled = true
              if count > 0
                @vimState.scrolled_down = true
              else
                @vimState.scrolled_down = false
            catch error

                
              console.log 'problem scrolling:',error
              console.log 'stack:',error.stack

        else if x[0] is "put"
          for v in x[1..]
            try
              ly = @vimState.location[0]
              lx = @vimState.location[1]
              if 0<=ly and ly < @rows-1
                if v
                  qq = v[0]
                  if qq and qq[0]
                    screen[ly][lx] = qq[0]
                    @vimState.location[1] = lx + 1
                    dirty[ly] = true
              else if ly == @rows - 1
                if v
                  qq = v[0]
                  if qq
                    @vimState.status_bar[lx] = qq[0]
                    @vimState.location[1] = lx + 1
              else if ly > @rows - 1
                console.log 'over the max'
            catch err
              console.log 'problem putting',err

        else if x[0] is "clear"
            #console.log 'clear'
          for posj in [0..@cols-1]
            for posi in [0..@rows-2]
              if screen and screen[posi]
                screen[posi][posj] = ' '
                dirty[posi] = true

            @vimState.status_bar[posj] = ' '

        else if x[0] is "eol_clear"
          ly = @vimState.location[0]
          lx = @vimState.location[1]
          if ly < @rows - 1
            for posj in [lx..@cols-1]
              for posi in [ly..ly]
                if screen and screen[posi]
                  if posj >= 0
                    dirty[posi] = true
                    screen[posi][posj] = ' '

          else if ly == @rows - 1
            for posj in [lx..@cols-1]
              @vimState.status_bar[posj] = ' '
          else if ly > @rows - 1
            console.log 'over the max'

    @vimState.redraw_screen(@rows, dirty)

    options =  { normalizeLineEndings: false, undo: 'skip' }
    if VimGlobals.current_editor
      VimGlobals.current_editor.buffer.setTextInRange(new Range(
        new Point(VimGlobals.current_editor.buffer.getLastRow(),0),
        new Point(VimGlobals.current_editor.buffer.getLastRow(),COLS-8)),'',
        options)

    VimGlobals.internal_change = false


module.exports =
class VimState
  editor: null

  constructor: (@editorView) ->
    @editor = @editorView.getModel()
    editor_views[@editor.getURI()] = @editorView
    @editorView.component.setInputEnabled(false)
    mode = 'command'
    @cursor_visible = true
    @scrolled_down = false
    VimGlobals.tlnumber = 0
    @status_bar = []
    @location = []


    if not VimGlobals.current_editor
      VimGlobals.current_editor = @editor
    @changeModeClass('command-mode')
    @activateCommandMode()

    atom.packages.onDidActivatePackage(  ->
      element.innerHTML = ''
      @statusbar =
          document.querySelector('status-bar').addLeftTile(item:element,
          priority:10 )
    )

    if not buffer_change_subscription
      buffer_change_subscription =
          atom.workspace.onDidChangeActivePaneItem activePaneChanged
    if not buffer_destroy_subscription
      buffer_destroy_subscription =
          atom.workspace.onDidDestroyPaneItem destroyPaneItem

    atom.commands.add 'atom-text-editor', 'core:save', (e) ->
      VimGlobals.internal_change = true
      VimGlobals.updating = true
      e.preventDefault()
      e.stopPropagation()
      vim_mode_save_file()


    @editorView.onkeypress = (e) =>
      deactivate_timer()
      q1 = @editorView.classList.contains('is-focused')
      q2 = @editorView.classList.contains('autocomplete-active')
      q3 = VimGlobals.current_editor.getSelectedBufferRange().isEmpty()
      if q1 and not q2 and q3
        @editorView.component.setInputEnabled(false)
        q =  String.fromCharCode(e.which)
        neovim_send_message(['vim_input',[q]])
        activate_timer()
        false
      else if q1 and not q2 and not q3
        @editorView.component.setInputEnabled(true)
        activate_timer()
        true
      else
        VimGlobals.internal_change = false
        VimGlobals.updating = false
        q =  String.fromCharCode(e.which)
        neovim_send_message(['vim_input',[q]])
        activate_timer()
        true

    @editorView.onkeydown = (e) =>
      deactivate_timer()
      q1 = @editorView.classList.contains('is-focused')
      q2 = @editorView.classList.contains('autocomplete-active')
      q3 = VimGlobals.current_editor.getSelectedBufferRange().isEmpty()
      if q1 and not q2 and not e.altKey and q3
        @editorView.component.setInputEnabled(false)
        translation = @translateCode(e.which, e.shiftKey, e.ctrlKey)
        if translation != ""
          neovim_send_message(['vim_input',[translation]])
          activate_timer()
          false
      else if q1 and not q2 and not q3
        @editorView.component.setInputEnabled(true)
        activate_timer()
        true
      else
        VimGlobals.internal_change = false
        VimGlobals.updating = false
        activate_timer()
        true



  translateCode: (code, shift, control) ->
    #console.log 'code:',code
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

  afterOpen: =>
    #console.log 'in after open'
    neovim_send_message(['vim_command',['set scrolloff=2']])
    neovim_send_message(['vim_command',['set nocompatible']])
    neovim_send_message(['vim_command',['set noswapfile']])
    neovim_send_message(['vim_command',['set nowrap']])
    neovim_send_message(['vim_command',['set numberwidth=8']])
    neovim_send_message(['vim_command',['set nu']])
    neovim_send_message(['vim_command',['set autochdir']])
    neovim_send_message(['vim_command',['set autoindent']])
    neovim_send_message(['vim_command',['set smartindent']])
    neovim_send_message(['vim_command',['set hlsearch']])
    neovim_send_message(['vim_command',['set tabstop=4']])
    neovim_send_message(['vim_command',['set encoding=utf-8']])
    neovim_send_message(['vim_command',['set shiftwidth=4']])
    neovim_send_message(['vim_command',['set shortmess+=I']])
    neovim_send_message(['vim_command',['set expandtab']])
    neovim_send_message(['vim_command',['set hidden']])
    neovim_send_message(['vim_command',['set listchars=eol:$']])
    neovim_send_message(['vim_command',['set list']])
    neovim_send_message(['vim_command',['set wildmenu']])
    neovim_send_message(['vim_command',['set showcmd']])
    neovim_send_message(['vim_command',['set incsearch']])
    neovim_send_message(['vim_command',['set autoread']])
    neovim_send_message(['vim_command',['set laststatus=2']])
    neovim_send_message(['vim_command',['set rulerformat=%L']])
    neovim_send_message(['vim_command',['set ruler']])
    #neovim_send_message(['vim_command',['set visualbell']])


    neovim_send_message(['vim_command',
        ['set backspace=indent,eol,start']])

    neovim_send_message(['vim_input',['<Esc>']])
    @activateCommandMode()

    if not subscriptions['redraw']
      #console.log 'subscribing, after open'
      @neovim_subscribe()
    #else
      #console.log 'NOT SUBSCRIBING, problem'
      #

    #last_text = VimGlobals.current_editor.getText()

  postprocess: (rows, dirty) ->
    screen_f = []
    for posi in [0..rows-1]
      line = undefined
      if screen[posi] and dirty[posi]
        line = []
        for posj in [0..COLS-8]
          if screen[posi][posj]=='$' and screen[posi][posj+1]==' ' and \
            screen[posi][posj+2]==' '
              break
          line.push screen[posi][posj]
      else
        if screen[posi]
          line = screen[posi]
      screen_f.push line

  redraw_screen:(rows, dirty) =>

    VimGlobals.current_editor = atom.workspace.getActiveTextEditor()
    if VimGlobals.current_editor

      if DEBUG
        initial = 0
      else
        initial = 8

      sbr = VimGlobals.current_editor.getSelectedBufferRange()
      @postprocess(rows, dirty)
      tlnumberarr = []
      for posi in [0..rows-3]
        try
          pos = parseInt(screen_f[posi][0..8].join(''))
          #if not isNaN(pos)
          tlnumberarr.push (  (pos - 1) - posi  )
          #else
          #    tlnumberarr.push -1
        catch err
          tlnumberarr.push -9999

      VimGlobals.tlnumber = NaN
      array = []
      for i in [0..rows-3]
        if not isNaN(tlnumberarr[i]) and tlnumberarr[i] >= 0
          array.push(tlnumberarr[i])
      #console.log array

      VimGlobals.tlnumber = getMaxOccurrence(array)
      #console.log 'TLNUMBERarr********************',tlnumberarr
      #console.log 'TLNUMBER********************',VimGlobals.tlnumber

      if dirty

        options =  { normalizeLineEndings: false, undo: 'skip' }
        for posi in [0..rows-3]
          if not isNaN(VimGlobals.tlnumber) and (VimGlobals.tlnumber isnt -9999)
            if (tlnumberarr[posi] + posi == VimGlobals.tlnumber + posi) and \
                dirty[posi]
              qq = screen_f[posi]
              qq = qq[initial..].join('')
              linerange = new Range(new Point(VimGlobals.tlnumber+posi,0),
                                      new Point(VimGlobals.tlnumber + posi,
                                      COLS-initial))

              txt = VimGlobals.current_editor.buffer.getTextInRange(linerange)
              if qq isnt txt
                console.log 'qq:',qq
                console.log 'txt:',txt
                VimGlobals.current_editor.buffer.setTextInRange(linerange,
                    qq, options)
              dirty[posi] = false

      sbt = @status_bar.join('')
      @updateStatusBarWithText(sbt, (rows - 1 == @location[0]), @location[1])
      
      q = screen[rows-2]
      text = q[q.length/2..q.length-1].join('')
      text = text.split(' ').join('')
      num_lines = parseInt(text, 10)

      if VimGlobals.current_editor.buffer.getLastRow() < num_lines
        nl = num_lines - VimGlobals.current_editor.buffer.getLastRow()
        diff = ''
        for i in [0..nl-2]
          diff = diff + '\n'
        append_options = {normalizeLineEndings: false}
        VimGlobals.current_editor.buffer.append(diff, append_options)

      else if VimGlobals.current_editor.buffer.getLastRow() > num_lines
        for i in [num_lines..\
            VimGlobals.current_editor.buffer.getLastRow()-1]
          VimGlobals.current_editor.buffer.deleteRow(i)


      if not isNaN(VimGlobals.tlnumber) and (VimGlobals.tlnumber isnt -9999)

        if @cursor_visible and @location[0] <= rows - 2
          if not DEBUG
            VimGlobals.current_editor.setCursorBufferPosition(
              new Point(VimGlobals.tlnumber + @location[0],
              @location[1]-initial),{autoscroll:false})
          else
            VimGlobals.current_editor.setCursorBufferPosition(
              new Point(VimGlobals.tlnumber + @location[0],
              @location[1]),{autoscroll:false})

        if VimGlobals.current_editor
          VimGlobals.current_editor.setScrollTop(lineSpacing()*\
            VimGlobals.tlnumber)

      #console.log 'sbr:',sbr
      if not sbr.isEmpty()
        VimGlobals.current_editor.setSelectedBufferRange(sbr,
          {reversed:reversed_selection})

  neovim_unsubscribe: ->
    message = ['ui_detach',[]]
    neovim_send_message(message)
    subscriptions['redraw'] = false

  neovim_resize:(cols, rows) =>

    VimGlobals.internal_change = true
    VimGlobals.updating = true
    qtop = 10
    qbottom =0
    @rows = 0

    qtop = VimGlobals.current_editor.getScrollTop()
    qbottom = VimGlobals.current_editor.getScrollBottom()

    qleft = VimGlobals.current_editor.getScrollLeft()
    qright= VimGlobals.current_editor.getScrollRight()

    @cols = Math.floor((qright-qleft)/lineSpacingHorizontal())-1

    COLS = @cols
    @rows = Math.floor((qbottom - qtop)/lineSpacing()+1)

    eventHandler.cols = @cols
    eventHandler.rows= @rows+2
    message = ['ui_try_resize',[@cols,@rows+2]]
    neovim_send_message(message)

    screen = ((' ' for ux in [1..@cols])  for uy in [1..@rows+2])
    @location = [0,0]
    neovim_send_message(['vim_command',['redraw!']],
        (() ->
          VimGlobals.internal_change = false
        )
    )
    VimGlobals.internal_change = false
    VimGlobals.updating = false


  neovim_subscribe: =>
    #console.log 'neovim_subscribe'

    eventHandler = new EventHandler this

    message = ['ui_attach',[eventHandler.cols,eventHandler.rows,true]]
    neovim_send_message(message)

    VimGlobals.session.on('notification', eventHandler.handleEvent)
    #rows = @editor.getScreenLineCount()
    @location = [0,0]
    @status_bar = (' ' for ux in [1..eventHandler.cols])

    subscriptions['redraw'] = true

  #Used to enable command mode.
  activateCommandMode: ->
    mode = 'command'
    @changeModeClass('command-mode')
    @updateStatusBar()

  #Used to enable insert mode.
  activateInsertMode: (transactionStarted = false)->
    mode = 'insert'
    @changeModeClass('insert-mode')
    @updateStatusBar()

  activateReplaceMode: ()->
    mode = 'replace'
    @changeModeClass('command-mode')

  activateInvisibleMode: (transactionStarted = false)->
    mode = 'insert'
    @changeModeClass('invisible-mode')
    @updateStatusBar()

  changeModeClass: (targetMode) ->
    if VimGlobals.current_editor
      editorview = editor_views[VimGlobals.current_editor.getURI()]
      if editorview
        for qmode in ['command-mode', 'insert-mode', 'visual-mode',\
                    'operator-pending-mode', 'invisible-mode']
          if qmode is targetMode
            editorview.classList.add(qmode)
          else
            editorview.classList.remove(qmode)

  updateStatusBarWithText:(text, addcursor, loc) ->
    if addcursor
      text = text[0..loc-1].concat('&#9632').concat(text[loc+1..])
    text = text.split(' ').join('&nbsp;')
    q = '<samp>'
    qend = '</samp>'
    element.innerHTML = q.concat(text).concat(qend)

  updateStatusBar: ->
    element.innerHTML = mode

