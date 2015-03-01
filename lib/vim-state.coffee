_ = require 'underscore-plus'
$ = require  'jquery'
{Point, Range} = require 'atom'
Marker = require 'atom'
net = require 'net'
map = require './mapped'
Buffer = require("buffer").Buffer
MarkerView = require './marker-view'

CONNECT_TO = '/Users/carlos/tmp/neovim577'
MESSAGE_COUNTER = 1

DEBUG = true
subscriptions = {}
subscriptions['redraw'] = false
socket_subs = null
collected = new Buffer(0)
screen = []
tlnumber = 0
cursor_visible = true
command_mode = true
scrolled = false
scrolled_down = false
status_bar = []
location = []
current_editor = undefined
editor_views = {}
element = document.createElement("item-view")

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



bops_readUInt8 = (target, at) ->
  target[at]

bops_readInt8 = (target, at) ->
  v = target[at]
  (if v < 0x80 then v else v - 0x100)

bops_readUInt16LE = (target, at) ->
  dv = map.get(target)
  dv.getUint16 at + target.byteOffset, true

bops_readUInt32LE = (target, at) ->
  dv = map.get(target)
  dv.getUint32 at + target.byteOffset, true

bops_readInt16LE = (target, at) ->
  dv = map.get(target)
  dv.getInt16 at + target.byteOffset, true

bops_readInt32LE = (target, at) ->
  dv = map.get(target)
  dv.getInt32 at + target.byteOffset, true

bops_readFloatLE = (target, at) ->
  dv = map.get(target)
  dv.getFloat32 at + target.byteOffset, true

bops_readDoubleLE = (target, at) ->
  dv = map.get(target)
  dv.getFloat64 at + target.byteOffset, true

bops_readUInt16BE = (target, at) ->
  dv = map.get(target)
  #if at+target.byteOffset + 2 <= dv.byteLength
  dv.getUint16(at + target.byteOffset, false)
  #else
    #undefined

bops_readUInt32BE = (target, at) ->
  dv = map.get(target)
  #if at+target.byteOffset + 4 <= dv.byteLength
  dv.getUint32(at + target.byteOffset, false)
  #else
    #undefined

bops_readInt16BE = (target, at) ->
  dv = map.get(target)
  dv.getInt16 at + target.byteOffset, false

bops_readInt32BE = (target, at) ->
  dv = map.get(target)
  dv.getInt32 at + target.byteOffset, false

bops_readFloatBE = (target, at) ->
  dv = map.get(target)
  dv.getFloat32 at + target.byteOffset, false

bops_readDoubleBE = (target, at) ->
  dv = map.get(target)
  dv.getFloat64 at + target.byteOffset, false

bops_writeUInt8 = (target, value, at) ->
  target[at] = value

bops_writeInt8 = (target, value, at) ->
  target[at] = (if value < 0 then value + 0x100 else value)

bops_writeUInt16LE = (target, value, at) ->
  dv = map.get(target)
  dv.setUint16 at + target.byteOffset, value, true

bops_writeUInt32LE = (target, value, at) ->
  dv = map.get(target)
  dv.setUint32 at + target.byteOffset, value, true

bops_writeInt16LE = (target, value, at) ->
  dv = map.get(target)
  dv.setInt16 at + target.byteOffset, value, true

bops_writeInt32LE = (target, value, at) ->
  dv = map.get(target)
  dv.setInt32 at + target.byteOffset, value, true

bops_writeFloatLE = (target, value, at) ->
  dv = map.get(target)
  dv.setFloat32 at + target.byteOffset, value, true

bops_writeDoubleLE = (target, value, at) ->
  dv = map.get(target)
  dv.setFloat64 at + target.byteOffset, value, true

bops_writeUInt16BE = (target, value, at) ->
  dv = map.get(target)
  dv.setUint16 at + target.byteOffset, value, false

bops_writeUInt32BE = (target, value, at) ->
  dv = map.get(target)
  dv.setUint32 at + target.byteOffset, value, false

bops_writeInt16BE = (target, value, at) ->
  dv = map.get(target)
  dv.setInt16 at + target.byteOffset, value, false

bops_writeInt32BE = (target, value, at) ->
  dv = map.get(target)
  dv.setInt32 at + target.byteOffset, value, false

bops_writeFloatBE = (target, value, at) ->
  dv = map.get(target)
  dv.setFloat32 at + target.byteOffset, value, false

bops_writeDoubleBE = (target, value, at) ->
  dv = map.get(target)
  dv.setFloat64 at + target.byteOffset, value, false

bops_create = (size) ->
  new Buffer(size)

bops_copy = (source, target, target_start, source_start, source_end) ->
  source.copy target, target_start, source_start, source_end

bops_subarray = (source, from, to) ->
  (source.subarray(from, to))

bops_to = (source, encoding) ->
  source.toString encoding

bops_from = (source, encoding) ->
  new Buffer(source, encoding)

bops_is = (buffer) ->
  Buffer.isBuffer buffer

encode_pub = (value) ->
  toJSONed = []
  size = sizeof(value)
  return `undefined`  if size is 0
  buffer = bops_create(size)
  encode value, buffer, 0
  buffer

Decoder = (buffer, offset) ->
  @offset = offset or 0
  @buffer = buffer
  return

Decoder::map = (length) ->
  value = {}
  i = 0

  while i < length
    key = @parse()
    value[key] = @parse()
    i++
  value

Decoder::bin = (length) ->
#  value = bops_subarray(@buffer, @offset, @offset + length)
#  @offset += length
#  value
  res = ''
  i = 0
  while i < length
    res = res + String.fromCharCode(@buffer[@offset+i])
    i++
  @offset += length
  res

Decoder::str = (length) ->
  res = ''
  i = 0
  while i < length
    res = res + String.fromCharCode(@buffer[@offset+i])
    i++
  @offset += length
  res

#  value = bops_to(bops_subarray(@buffer, @offset, @offset + length), 'utf8')
#  @offset += length
#  value

Decoder::array = (length) ->
  value = new Array(length)
  i = 0

  while i < length
    value[i] = @parse()
    i++
  value

Decoder::parse = ->
  type = @buffer[@offset]
  value = undefined
  length = undefined
  extType = undefined

  # Positive FixInt
  if (type & 0x80) is 0x00
    @offset++
    return type

  # FixMap
  if (type & 0xf0) is 0x80
    length = type & 0x0f
    @offset++
    return @map(length)

  # FixArray
  if (type & 0xf0) is 0x90
    length = type & 0x0f
    @offset++
    return @array(length)

  # FixStr
  if (type & 0xe0) is 0xa0
    length = type & 0x1f
    @offset++
    return @str(length)

  # Negative FixInt
  if (type & 0xe0) is 0xe0
    value = bops_readInt8(@buffer, @offset)
    @offset++
    return value
  switch type

    # nil
    when 0xc0
      @offset++
      return null

    # 0xc1: (never used)
    # false
    when 0xc2
      @offset++
      return false

    # true
    when 0xc3
      @offset++
      return true

    # bin 8
    when 0xc4
      length = bops_readUInt8(@buffer, @offset + 1)
      @offset += 2
      return @bin(length)

    # bin 16
    when 0xc5
      length = bops_readUInt16BE(@buffer, @offset + 1)
      @offset += 3
      return @bin(length)

    # bin 32
    when 0xc6
      length = bops_readUInt32BE(@buffer, @offset + 1)
      @offset += 5
      return @bin(length)

    # ext 8
    when 0xc7
      length = bops_readUInt8(@buffer, @offset + 1)
      extType = bops_readUInt8(@buffer, @offset + 2)
      @offset += 3
      return [
        extType
        @bin(length)
      ]

    # ext 16
    when 0xc8
      length = bops_readUInt16BE(@buffer, @offset + 1)
      extType = bops_readUInt8(@buffer, @offset + 3)
      @offset += 4
      return [
        extType
        @bin(length)
      ]

    # ext 32
    when 0xc9
      length = bops_readUInt32BE(@buffer, @offset + 1)
      extType = bops_readUInt8(@buffer, @offset + 5)
      @offset += 6
      return [
        extType
        @bin(length)
      ]

    # float 32
    when 0xca
      value = bops_readFloatBE(@buffer, @offset + 1)
      @offset += 5
      return value

    # float 64 / double
    when 0xcb
      value = bops_readDoubleBE(@buffer, @offset + 1)
      @offset += 9
      return value

    # uint8
    when 0xcc
      value = @buffer[@offset + 1]
      @offset += 2
      return value

    # uint 16
    when 0xcd
      value = bops_readUInt16BE(@buffer, @offset + 1)
      @offset += 3
      return value

    # uint 32
    when 0xce
      value = bops_readUInt32BE(@buffer, @offset + 1)
      @offset += 5
      return value

    # uint64
    when 0xcf
      value = bops_readUInt64BE(@buffer, @offset + 1)
      @offset += 9
      return value

    # int 8
    when 0xd0
      value = bops_readInt8(@buffer, @offset + 1)
      @offset += 2
      return value

    # int 16
    when 0xd1
      value = bops_readInt16BE(@buffer, @offset + 1)
      @offset += 3
      return value

    # int 32
    when 0xd2
      value = bops_readInt32BE(@buffer, @offset + 1)
      @offset += 5
      return value

    # int 64
    when 0xd3
      value = bops_readInt64BE(@buffer, @offset + 1)
      @offset += 9
      return value

    # fixext 1 / undefined
    when 0xd4
      extType = bops_readUInt8(@buffer, @offset + 1)
      value = bops_readUInt8(@buffer, @offset + 2)
      @offset += 3
      return (if (extType is 0 and value is 0) then `undefined` else [
        extType
        value
      ])

    # fixext 2
    when 0xd5
      extType = bops_readUInt8(@buffer, @offset + 1)
      @offset += 2
      return [
        extType
        @bin(2)
      ]

    # fixext 4
    when 0xd6
      extType = bops_readUInt8(@buffer, @offset + 1)
      @offset += 2
      return [
        extType
        @bin(4)
      ]

    # fixext 8
    when 0xd7
      extType = bops_readUInt8(@buffer, @offset + 1)
      @offset += 2
      return [
        extType
        @bin(8)
      ]

    # fixext 16
    when 0xd8
      extType = bops_readUInt8(@buffer, @offset + 1)
      @offset += 2
      return [
        extType
        @bin(16)
      ]

    # str 8
    when 0xd9
      length = bops_readUInt8(@buffer, @offset + 1)
      @offset += 2
      return @str(length)

    # str 16
    when 0xda
      length = bops_readUInt16BE(@buffer, @offset + 1)
      @offset += 3
      return @str(length)

    # str 32
    when 0xdb
      length = bops_readUInt32BE(@buffer, @offset + 1)
      if length
        @offset += 5
      else
        @offset += read + 1
      return @str(length)

    # array 16
    when 0xdc
      length = bops_readUInt16BE(@buffer, @offset + 1)
      @offset += 3
      return @array(length)

    # array 32
    when 0xdd
      length = bops_readUInt32BE(@buffer, @offset + 1)
      if length
        @offset += 5
      else
        @offset += read + 1
      return @array(length)

    # map 16:
    when 0xde
      length = bops_readUInt16BE(@buffer, @offset + 1)
      @offset += 3
      return @map(length)

    # map 32
    when 0xdf
      length = bops_readUInt32BE(@buffer, @offset + 1)
      @offset += 5
      return @map(length)

    # buffer 16
    when 0xd8
      length = bops_readUInt16BE(@buffer, @offset + 1)
      @offset += 3
      return @buf(length)

    # buffer 32
    when 0xd9
      length = bops_readUInt32BE(@buffer, @offset + 1)
      @offset += 5
      return @buf(length)
  throw new Error("Unknown type 0x" + type.toString(16))
  return

decode_pub = (buffer) ->
  decoder = new Decoder(buffer)
  value = decoder.parse()
  #throw new Error((buffer.length - decoder.offset) + " trailing bytes")  if decoder.offset isnt buffer.length
  {value:value, trailing:buffer.length - decoder.offset}

encodeableKeys = (value) ->
  Object.keys(value).filter (e) ->
    "function" isnt typeof value[e] or !!value[e].toJSON

encode = (value, buffer, offset) ->
  type = typeof value
  length = undefined
  size = undefined

  # Strings Bytes
  if type is "string"
    value = bops_from(value)
    length = value.length

    # fixstr
    if length < 0x20
      buffer[offset] = length | 0xa0
      bops_copy value, buffer, offset + 1
      return 1 + length

    # str 8
    if length < 0x100
      buffer[offset] = 0xd9
      bops_writeUInt8 buffer, length, offset + 1
      bops_copy value, buffer, offset + 2
      return 2 + length

    # str 16
    if length < 0x10000
      buffer[offset] = 0xda
      bops_writeUInt16BE buffer, length, offset + 1
      bops_copy value, buffer, offset + 3
      return 3 + length

    # str 32
    if length < 0x100000000
      buffer[offset] = 0xdb
      bops_writeUInt32BE buffer, length, offset + 1
      bops_copy value, buffer, offset + 5
      return 5 + length
  if bops_is(value)
    length = value.length

    # bin 8
    if length < 0x100
      buffer[offset] = 0xc4
      bops_writeUInt8 buffer, length, offset + 1
      bops_copy value, buffer, offset + 2
      return 2 + length

    # bin 16
    if length < 0x10000
      buffer[offset] = 0xd8
      bops_writeUInt16BE buffer, length, offset + 1
      bops_copy value, buffer, offset + 3
      return 3 + length

    # bin 32
    if length < 0x100000000
      buffer[offset] = 0xd9
      bops_writeUInt32BE buffer, length, offset + 1
      bops_copy value, buffer, offset + 5
      return 5 + length
  if type is "number"

    # Floating Point
    if (value << 0) isnt value
      buffer[offset] = 0xcb
      bops_writeDoubleBE buffer, value, offset + 1
      return 9

    # Integers
    if value >= 0

      # positive fixnum
      if value < 0x80
        buffer[offset] = value
        return 1

      # uint 8
      if value < 0x100
        buffer[offset] = 0xcc
        buffer[offset + 1] = value
        return 2

      # uint 16
      if value < 0x10000
        buffer[offset] = 0xcd
        bops_writeUInt16BE buffer, value, offset + 1
        return 3

      # uint 32
      if value < 0x100000000
        buffer[offset] = 0xce
        bops_writeUInt32BE buffer, value, offset + 1
        return 5

      # uint 64
      if value < 0x10000000000000000
        buffer[offset] = 0xcf
        bops_writeUInt64BE buffer, value, offset + 1
        return 9
      throw new Error("Number too big 0x" + value.toString(16))

    # negative fixnum
    if value >= -0x20
      bops_writeInt8 buffer, value, offset
      return 1

    # int 8
    if value >= -0x80
      buffer[offset] = 0xd0
      bops_writeInt8 buffer, value, offset + 1
      return 2

    # int 16
    if value >= -0x8000
      buffer[offset] = 0xd1
      bops_writeInt16BE buffer, value, offset + 1
      return 3

    # int 32
    if value >= -0x80000000
      buffer[offset] = 0xd2
      bops_writeInt32BE buffer, value, offset + 1
      return 5

    # int 64
    if value >= -0x8000000000000000
      buffer[offset] = 0xd3
      bops_writeInt64BE buffer, value, offset + 1
      return 9
    throw new Error("Number too small -0x" + value.toString(16).substr(1))
  if type is "undefined"
    buffer[offset] = 0xd4
    buffer[offset + 1] = 0x00 # fixext special type/value
    buffer[offset + 2] = 0x00
    return 1

  # null
  if value is null
    buffer[offset] = 0xc0
    return 1

  # Boolean
  if type is "boolean"
    buffer[offset] = (if value then 0xc3 else 0xc2)
    return 1
  return encode(value.toJSON(), buffer, offset)  if "function" is typeof value.toJSON

  # Container Types
  if type is "object"
    size = 0
    isArray = Array.isArray(value)
    if isArray
      length = value.length
    else
      keys = encodeableKeys(value)
      length = keys.length

    # fixarray
    if length < 0x10
      buffer[offset] = length | ((if isArray then 0x90 else 0x80))
      size = 1

    # array 16 / map 16
    else if length < 0x10000
      buffer[offset] = (if isArray then 0xdc else 0xde)
      bops_writeUInt16BE buffer, length, offset + 1
      size = 3

    # array 32 / map 32
    else if length < 0x100000000
      buffer[offset] = (if isArray then 0xdd else 0xdf)
      bops_writeUInt32BE buffer, length, offset + 1
      size = 5
    if isArray
      i = 0

      while i < length
        size += encode(value[i], buffer, offset + size)
        i++
    else
      i = 0

      while i < length
        key = keys[i]
        size += encode(key, buffer, offset + size)
        size += encode(value[key], buffer, offset + size)
        i++
    return size
  return `undefined`  if type is "function"
  throw new Error("Unknown type " + type)
  return

sizeof = (value) ->
  type = typeof value
  length = undefined
  size = undefined

  # Raw Bytes
  if type is "string"

    # TODO: this creates a throw-away buffer which is probably expensive on browsers.
    length = bops_from(value).length
    return 1 + length  if length < 0x20
    return 2 + length  if length < 0x100
    return 3 + length  if length < 0x10000
    return 5 + length  if length < 0x100000000
  if bops_is(value)
    length = value.length
    return 2 + length  if length < 0x100
    return 3 + length  if length < 0x10000
    return 5 + length  if length < 0x100000000
  if type is "number"

    # Floating Point
    # double
    return 9  if value << 0 isnt value

    # Integers
    if value >= 0

      # positive fixnum
      return 1  if value < 0x80

      # uint 8
      return 2  if value < 0x100

      # uint 16
      return 3  if value < 0x10000

      # uint 32
      return 5  if value < 0x100000000

      # uint 64
      return 9  if value < 0x10000000000000000
      throw new Error("Number too big 0x" + value.toString(16))

    # negative fixnum
    return 1  if value >= -0x20

    # int 8
    return 2  if value >= -0x80

    # int 16
    return 3  if value >= -0x8000

    # int 32
    return 5  if value >= -0x80000000

    # int 64
    return 9  if value >= -0x8000000000000000
    throw new Error("Number too small -0x" + value.toString(16).substr(1))

  # Boolean, null
  return 1  if type is "boolean" or value is null
  return 3  if type is "undefined"
  return sizeof(value.toJSON())  if "function" is typeof value.toJSON

  # Container Types
  if type is "object"
    value = value.toJSON()  if "function" is typeof value.toJSON
    size = 0
    if Array.isArray(value)
      length = value.length
      i = 0

      while i < length
        size += sizeof(value[i])
        i++
    else
      keys = encodeableKeys(value)
      length = keys.length
      i = 0

      while i < length
        key = keys[i]
        size += sizeof(key) + sizeof(value[key])
        i++
    return 1 + size  if length < 0x10
    return 3 + size  if length < 0x10000
    return 5 + size  if length < 0x100000000
    throw new Error("Array or object too long 0x" + length.toString(16))
  return 0  if type is "function"
  throw new Error("Unknown type " + type)
  return

to_uint8array = (str) ->
  new Uint8Array(str);

str2ab = (str) ->
  bufView = new Uint8Array(str.length)
  i = 0
  strLen = str.length

  while i < strLen
    bufView[i] = str.charCodeAt(i)
    i++
  bufView

HighlightedAreaView = require './highlighted-area-view'

module.exports =
class VimState
  editor: null
  opStack: null
  mode: null
  submode: null

  constructor: (@editorView) ->
    @editor = @editorView.getModel()
    editor_views[@editor.getURI()] = @editorView
    #console.log '*****************************************editor uri:',@editor.getURI()
    @opStack = []
    @history = []
    @marks = {}
    params = {}
    params.manager = this
    params.id = 0
    @editorView.component.setInputEnabled(false);
    @mode = 'command'
    #
    #
    #@area = new HighlightedAreaView(@editorView)
    #@area.attach()
    #
    @linelen = 5

    if not current_editor
        current_editor = @editor
    @changeModeClass('command-mode')
    @activateCommandMode()


    atom.packages.once 'activated', ->
        element.innerHTML = ''
        @statusbar = document.querySelector('status-bar').addLeftTile(item:element,priority:10 )

    #@setupCommandMode()
    #@registerInsertIntercept()
    #@registerInsertTransactionResets()
    #if atom.config.get 'vim-mode.startInInsertMode'
    #  @activateInsertMode()
    #else
    #  @activateCommandMode()


#    atom.workspaceView.on 'focusout', ".editor:not(.mini)", (event) =>
#      editor = $(event.target).closest('.editor').view()?.getModel()
#      @destroy_sockets(editor)

#    atom.workspaceView.on 'pane:before-item-destroyed', (event, paneItem) =>
#      @destroy_sockets(paneItem)

#    $(window).preempt 'beforeunload', =>
#      for pane in atom.workspaceView.getPanes()
#        @destroy_sockets(paneItem) for paneItem in pane.getItems()

    @height = 100
    @line0 = 1

    @range_list = []
    @range_line_list = []

    socket = new net.Socket()
    socket.connect(CONNECT_TO)

    socket.on('data', (data) =>
        {value:q,trailing} = decode_pub(to_uint8array(data))
        #console.log q
        #console.log trailing
        qq = q[3][1]
        #console.log 'data:',qq
        socket.end()
        socket.destroy()
    )
    msg = encode_pub([0,1,'vim_get_api_info',[]])
    socket.write(msg)

    #if not subscriptions['redraw']
    #@neovim_subscribe()

    #atom.project.eachBuffer (buffer) =>
      #@registerChangeHandler(buffer)

    #@editorView.on 'editor:min-width-changed', @editorSizeChanged
    #
    #atom.workspaceView.on 'pane-container:active-pane-item-changed', @activePaneChanged
    atom.workspace.onDidChangeActivePaneItem @activePaneChanged

    @editorView.onkeypress = (e) =>
        if @editorView.classList.contains('is-focused')
            q =  String.fromCharCode(e.which)
            console.log "pressed:"+q
            q = q.replace '\<', '<lt>'
            @neovim_send_message([0,1,'vim_input',[q]])
            false
        else
            true

    @editorView.onkeydown = (e) =>
        if @editorView.classList.contains('is-focused') and not e.altKey
            translation = @translateCode(e.which, e.shiftKey, e.ctrlKey)
            console.log "pressed down:",translation
            if translation != ""
                @neovim_send_message([0,1,'vim_input',[translation]])
                false
        else
            true

  translateCode: (code, shift, control) ->
    console.log code
    if control && code>=65 && code<=90
      String.fromCharCode(code-64)
    else if code>=8 && code<=10 || code==13 || code==27
      String.fromCharCode(code)
    else if code==37
      '<left>'
    else if code==38
      '<up>'
    else if code==39
      '<right>'
    else if code==40
      '<down>'
      #String.fromCharCode(27)+'[B'
    else if code==188
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

        #if @editor.getURI() is atom.workspaceView.getActiveView().getEditor().getURI()
            #console.log 'active pane changed',atom.workspace.getActiveTextEditor().getURI()
            @neovim_send_message([0,1,'vim_command',['e '+atom.workspace.getActiveTextEditor().getURI()]],(x) =>
                current_editor = atom.workspace.getActiveTextEditor()
                #@editor
                tlnumber = 0
                @afterOpen()
                #@editorView.on 'editor:min-width-changed', @editorSizeChanged
            )
        #else
            #console.log 'active pane changed',atom.workspaceView.getActiveView().getEditor().getURI()
            #console.log '@editor.geturi',@editor.getURI()

            #@destroy_sockets(@editor)
    catch err
        console.log 'problem changing panes'

  afterOpen: =>

    #console.log 'in after open'
    @neovim_send_message([0,1,'vim_command',['set scrolloff=5']])
    @neovim_send_message([0,1,'vim_command',['set noswapfile']])
    @neovim_send_message([0,1,'vim_command',['set nowrap']])
    @neovim_send_message([0,1,'vim_command',['set nu']])
    @neovim_send_message([0,1,'vim_command',['set autochdir']])
    @neovim_send_message([0,1,'vim_command',['set hlsearch']])
    @neovim_send_message([0,1,'vim_command',['set tabstop=4']])
    @neovim_send_message([0,1,'vim_command',['set shiftwidth=4']])
    @neovim_send_message([0,1,'vim_command',['set expandtab']])
    @neovim_send_message([0,1,'vim_command',['set hidden']])
    @neovim_send_message([0,1,'vim_command',['redraw!']])


    if not subscriptions['redraw']
        #console.log 'subscribing, after open'
        @neovim_subscribe()
    #else
        #console.log 'NOT SUBSCRIBING, problem'
        #

  ns_redraw_background_color:(q) =>

  ns_redraw_foreground_color:(q) =>

  ns_redraw_layout:(q) =>
    console.log 'redraw layout'
    console.log q

  ns_redraw_cursor:(q) =>
      try
        #console.log 'redraw cursor q:'
        #console.log q
        #console.log @linelen

        @editor.setCursorBufferPosition(new Point(parseInt(q.lnum-1),parseInt(q.col)-@linelen),{autoscroll:false})
        allempty = true
        for rng in @range_list
          if not rng.isEmpty()
            allempty = false
            break
        if not allempty
          final_range_list = []
          for item in @range_list
            s = item.start.toArray()
            if s[0] == parseInt(q.row)
              radd = new Range([parseInt(q.row), parseInt(q.col)],[parseInt(q.row), parseInt(q.col)+1])
              final_range_list.push(item.union(radd))
            else
              final_range_list.push(item)
          @editor.setSelectedBufferRanges(final_range_list)

        lineHeightInPixels = 19;
        @editor.setScrollTop((@line0-1)*lineHeightInPixels);

      catch err
        console.log 'redraw cursor error:'+err

  ns_redraw_update_line:(q) =>
      try
        #console.log 'redraw line q'
        #console.log q
        qline = q['line']
        lineno = parseInt(qline[0]['content'])
        if qline.length > 1
          @linelen = qline[0]['content'].length - qline[1]['content'].length
        else
          @linelen = qline[0]['content'].length
        qrow = parseInt(q['row'])
        @line0 = lineno - qrow

        if qline.length > 1
          qlen = qline[1]['content'].length
          qlinecontents = qline[1]['content']
        else
          qlen = 0
          qlinecontents = ''

        linerange = new Range(new Point(qrow+@line0-1,0),new Point(qrow+@line0-1,1024))
        currenttext = @editor.getTextInBufferRange(linerange)

        if currenttext isnt qlinecontents and subscriptions['redraw:update_line']
          @neovim_send_message([0,1,'vim_eval',["expand('%:p')"]], (filename) =>
            if filename == @editor.getURI()
              @editor.setTextInBufferRange(linerange,qlinecontents)
          )
            # console.log 'setting text in:'+qrow
            # console.log currenttext
            # console.log currenttext.length
            # console.log qline[1]['content']
            # console.log  qline[1]['content'].length

        rng = (new Range(new Point(0,0), new Point(0,0)))

        highlight_case = 0
        if 'attributes' of q
          r = q['attributes']
          # console.log r
          for key of r
            if key.indexOf('bg:#ff') == 0      #hlsearch todo more robust detection

              highlight_case = 1
              s = r[key]
              s0 = parseInt(s[0][0])
              if s[0].length > 1
                s1 = parseInt(s[0][1])
                rng = new Range(new Point(qrow+@line0-1,s0-@linelen), new Point(qrow+@line0-1,s1-@linelen))
              else
                s0 = parseInt(s[0])
                rng = new Range(new Point(qrow+@line0-1,s0-@linelen), new Point(qrow+@line0-1,s0-@linelen+1))

              break

            if key.indexOf('bg') == 0        #visual selection -> maps to Atom selection
              highlight_case = 2
              s = r[key]
              s0 = parseInt(s[0][0])
              if s[0].length > 1
                s1 = parseInt(s[0][1])
                rng = new Range(new Point(qrow+@line0-1,s0-@linelen), new Point(qrow+@line0-1,s1-@linelen))
              else
                s0 = parseInt(s[0])
                rng = new Range(new Point(qrow+@line0-1,s0-@linelen), new Point(qrow+@line0-1,s0-@linelen+1))
              break


        index = @range_line_list.indexOf(qrow+@line0)
        if index isnt -1
          @range_line_list.splice(index,1)
          @range_list.splice(index,1)

        if not rng.isEmpty() and highlight_case == 2
          @range_line_list.push qrow+@line0
          @range_list.push rng

        index = @editorView.vimState.area.indexOf(qrow+@line0-1)

        while index isnt -1
          @editorView.vimState.area.remove(index)
          index = @editorView.vimState.area.indexOf(qrow+@line0-1)

        if not rng.isEmpty() and highlight_case == 1
          marker = new MarkerView(rng,@editorView,this)
          @editorView.vimState.area.appendMarker(marker)

        if @range_list.length > 0
          @editor.setSelectedBufferRanges(@range_list,{})
      catch err
        console.log 'el error:'+err

  ns_redraw_insert_line:(q) =>
    #console.log "redraw insert line:"
    #console.log q

  ns_redraw_delete_line:(q) =>
    #console.log "redraw delete line:"
    #console.log q

  ns_redraw_start:(q) =>
    console.log "redraw start:"
    console.log q

  ns_redraw_end:(q) =>
    console.log "redraw end:"
    console.log q

  ns_redraw_win_start:(q) =>
    console.log "redraw win start:"
    console.log q

  ns_redraw_win_end:(q) =>
    #console.log "redraw win end:"
    #console.log q

    @neovim_send_message([0,1,'vim_eval',["expand('%:p')"]], (filename) =>
        #console.log 'filename reported by vim:',filename
        #console.log 'current editor uri:',current_editor.getURI()
        if filename isnt current_editor.getURI()
            console.log 'trying to open using atom'
            atom.workspace.open(filename)
        else
            @neovim_send_message([0,1,'vim_eval',["line('$')"]], (nLines) =>
                if current_editor.buffer.getLastRow() < parseInt(nLines)
                    nl = parseInt(nLines) - current_editor.buffer.getLastRow()
                    diff = ''
                    for i in [0..nl-1]
                        diff = diff + '\n'
                    current_editor.buffer.append(diff, true)

                if current_editor.buffer.getLastRow() > parseInt(nLines)
                    for i in [parseInt(nLines)+1..current_editor.buffer.getLastRow()-1]
                        current_editor.buffer.deleteRow(i)

                lines = current_editor.buffer.getLines()
                pos = 0
                for item in lines
                    if item.length > 100
                        options =  { normalizeLineEndings:false, undo: 'skip' }
                        current_editor.buffer.setTextInRange(new Range(new Point(pos,100),new Point(pos,item.length)),'',options)
                    pos = pos + 1

            )
        )


#    @neovim_send_message([0,1,25,["line('w$')"]], (lastLine) =>
#      @height = Math.max(@editorView.getPageRows(),20)
#      if (lastLine - @line0) < @height
#        @neovim_send_message([0,1,23,['set lines='+@height]])
#    )

  editorSizeChanged: =>
    @height = 40
    @line0 = 1
    #@neovim_send_message([0,1,'vim_command',['set lines='+@height]])
    #console.log 'HEIGHT:',@height

  redraw_screen:(dirty,rows) =>
    #get top left from screen
    #console.log 'initial tlnumber',tlnumber
    tlnumberarr = []
    for posi in [0..rows-1]
        try
            pos = parseInt(screen[posi][0..3].join(''))
            if not isNaN(pos)
                tlnumberarr.push (  (pos - 1) - posi  )
            else
                tlnumberarr.push -1
        catch err
            tlnumberarr.push -1
    #console.log 'tlnumberarr:',tlnumberarr

    if scrolled and scrolled_down
        tlnumber = tlnumberarr[tlnumberarr.length-2]
    else if scrolled and not scrolled_down
        tlnumber = tlnumberarr[0]
    else
        tlnumber = tlnumberarr[0]

    for posi in [0..rows-2]
        qq = screen[posi]
        pos = parseInt(qq[0..3].join(''))
        if not isNaN(pos)
            if (pos-1 == tlnumber + posi) and dirty[posi]

                if not DEBUG
                    qq = qq[4..].join('')
                else
                    qq = qq[..].join('')   #this is for debugging

                #console.log 'qq:',qq

                linerange = new Range(new Point(tlnumber+posi,0),new Point(tlnumber + posi, qq.length))
                options =  { normalizeLineEndings:false, undo: 'skip' }
                current_editor.buffer.setTextInRange(linerange, qq, options)
                #console.log 'printing line:',posi

                dirty[posi] = false
            #else
                #console.log 'comparison:',parseInt(qq[0..3].join('')) ,tlnumber + posi


    #n = lf[lf.length-1].length
    #qq = lf.join('\n')

    sbt = status_bar.join('').trim()
    @updateStatusBarWithText(sbt)

    #if location[1] >= 4
    if cursor_visible and location[0] <= rows - 2
        if not DEBUG
            current_editor.setCursorBufferPosition(new Point(tlnumber + location[0], location[1]-4),{autoscroll:true})
        else
            current_editor.setCursorBufferPosition(new Point(tlnumber + location[0], location[1]),{autoscroll:true})

    return dirty


  neovim_subscribe: =>
    console.log 'neovim_subscribe'
    if socket_subs == null
        socket_subs = new net.Socket()
        socket_subs.connect(CONNECT_TO)
        collected = new Buffer(0)

    socket_subs.on('error', (error) =>
      console.log 'error communicating (subscribe)'
    )

    socket_subs.on('data', (data) =>
        dirty = (false for i in [0..rows-2])
        collected = Buffer.concat([collected, data])
        i = collected.length
        #if (collected.length % 8192 isnt 0) or (collected.length < 8192)
        #console.log 'collected.length',collected.length
        while i >= 1
            try
                v = collected.slice(0,i)
                {value:q,trailing} = decode_pub(to_uint8array(v))
                if trailing >= 0
                    #console.log 'subscribe',q
                    [bufferId, eventName, eventInfo] = q
                    if eventName is "redraw"
                        #console.log "eventInfo", eventInfo
                        for x in eventInfo
                            if x[0] is "cursor_goto"
                                for v in x[1..]
                                    location[0] = parseInt(v[0])
                                    location[1] = parseInt(v[1])

                            if x[0] is 'set_scroll_region'
                                #console.log x
                                screen_top = parseInt(x[1][0])
                                screen_bot = parseInt(x[1][1])
                                screen_left = parseInt(x[1][2])
                                screen_right = parseInt(x[1][3])
                                #console.log "set_scroll_region",screen_top,screen_bot,screen_left,screen_right

                            if x[0] is "insert_mode"
                                @activateInsertMode()
                                command_mode = false

                            if x[0] is "normal_mode"
                                @activateCommandMode()
                                command_mode = true

                            if x[0] is "bell"
                                atom.beep()

                            if x[0] is "cursor_on"
                                if command_mode
                                    @activateCommandMode()
                                else
                                    @activateInsertMode()
                                cursor_visible = true

                            if x[0] is "cursor_off"
                                @activateInvisibleMode()
                                cursor_visible = false

                            if x[0] is "scroll"
                                for v in x[1..]
                                    top = screen_top
                                    bot = screen_bot + 1

                                    left = screen_left
                                    right = screen_right + 1

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

                                    top = screen_top
                                    bottom = screen_bot
                                    left = screen_left
                                    right = screen_right
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
                                        scrolled_down = true
                                    else
                                        scrolled_down = false


                            if x[0] is "put"
                                cnt = 0
                                #console.log 'put:',x[1..]
                                for v in x[1..]
                                    if 0<=location[0] and location[0] < rows-1
                                        if location[1]>=0 and location[1]<100
                                            try
                                                qq = v[0]
                                                screen[location[0]][location[1]] = qq[0]
                                                location[1] = location[1] + 1
                                                dirty[location[0]] = true
                                            catch  puterr
                                                console.log 'put err, but no big deal'
                                    else if location[0] == rows - 1
                                        status_bar[location[1]] = v[0]
                                        location[1] = location[1] + 1

                                    else if location[0] > rows - 1
                                        console.log 'over the max'


                            if x[0] is "clear"
                                #console.log 'clear'
                                for posj in [0..cols-1]
                                    for posi in [0..rows-2]
                                        screen[posi][posj] = ' '
                                        dirty[posi] = true

                            if x[0] is "eol_clear"
                                #console.log 'eol_clear'
                                if location[0] < rows - 1
                                    for posj in [location[1]..cols-1]
                                        for posi in [location[0]..location[0]]
                                            if posj >= 0
                                                dirty[posi] = true
                                                screen[posi][posj] = ' '

                                else if location[0] == rows - 1
                                    for posj in [location[1]..cols-1]
                                        status_bar[posj] = ' '
                                else if location[0] > rows - 1
                                    console.log 'over the max'

                    dirty = @redraw_screen(dirty,rows)

                    i = i - trailing
                    #console.log 'found message at:',i
                    collected = collected.slice(i,collected.length)
                    i = collected.length


                else

                    @redraw_screen(dirty,rows)
                    break



            catch err
                #console.log err,i,collected.length
                #console.log 'stack:',err.stack
                @redraw_screen(dirty,rows)
                break
        if scrolled
            @neovim_send_message([0,1,'vim_command',['redraw!']])
            scrolled = false
        @ns_redraw_win_end([])
        #@redrawScreen(dirty,rows)

    )

    rows = 20
    cols = 100
    message = [0,1,'ui_attach',[cols,rows,true]]
    #rows = @editor.getScreenLineCount()
    location = [0,0]
    status_bar = (' ' for ux in [1..cols])
    screen = ((' ' for ux in [1..cols])  for uy in [1..rows-1])


    message[1] = MESSAGE_COUNTER
    MESSAGE_COUNTER = (MESSAGE_COUNTER + 1) % 256
    console.log 'MESSAGE_COUNTER',MESSAGE_COUNTER
    msg2 = encode_pub(message)
    socket_subs.write(msg2)
    subscriptions['redraw'] = true



  neovim_send_message:(message,f = undefined) ->
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
        {value:q, trailing:t} = decode_pub(to_uint8array(data))
        if t isnt 0
            console.log 'not reliable'
        if f
            f(q[3])
        socket2.destroy()
      )
      message[1] = MESSAGE_COUNTER
      MESSAGE_COUNTER = (MESSAGE_COUNTER + 1) % 256
      msg2 = encode_pub(message)
      #socket2.write(msg2, => socket2.end())
      socket2.write(msg2)
    catch err
      console.log 'error in neovim_send_message '+err


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
    #try
        #@editor.commitTransaction()
    #catch err
        #console.log 'cannot commit transaction'
    @submode = null

    #if @editorView.is(".insert-mode")
      #cursor = @editor.getCursor()
      #cursor.moveLeft() unless cursor.isAtBeginningOfLine()

    @changeModeClass('command-mode')

    #@clearOpStack()
    #@editor.clearSelections()

    @updateStatusBar()

  # Private: Used to enable insert mode.
  #
  # Returns nothing.
  activateInsertMode: (transactionStarted = false)->
    @mode = 'insert'
    #@editor.beginTransaction() unless transactionStarted
    @submode = null
    @changeModeClass('insert-mode')
    @updateStatusBar()

  activateInvisibleMode: (transactionStarted = false)->
    @mode = 'insert'
    #@editor.beginTransaction() unless transactionStarted
    @submode = null
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
    @submode = type
    @changeModeClass('visual-mode')

    if @submode == 'linewise'
      @editor.selectLine()

    @updateStatusBar()

  # Private: Used to enable operator-pending mode.
  activateOperatorPendingMode: ->
    @deactivateInsertMode()
    @mode = 'operator-pending'
    @submodule = null
    @changeModeClass('operator-pending-mode')

    @updateStatusBar()

  changeModeClass: (targetMode) ->
    console.log 'query time:',current_editor.getURI()
    console.log 'editor_views:',editor_views
    editorview = editor_views[current_editor.getURI()]
    for mode in ['command-mode', 'insert-mode', 'visual-mode', 'operator-pending-mode', 'invisible-mode']
        if mode is targetMode
            editorview.classList.add(mode)
        else
            editorview.classList.remove(mode)

  updateStatusBarWithText:(text) ->
    element.innerHTML = text

  updateStatusBar: ->
    element.innerHTML = @mode

