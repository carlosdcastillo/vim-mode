_ = require 'underscore-plus'
{$} = require 'atom'

Operators = require './operators/index'
Prefixes = require './prefixes'
Motions = require './motions/index'

TextObjects = require './text-objects'
Utils = require './utils'
Panes = require './panes'
Scroll = require './scroll'
{$$, Point, Range} = require 'atom'
Marker = require 'atom'
net = require 'net'


class MsgPack


  # --- init ---
  constructor: () ->
    @_bin2num = {}
    @_num2bin = {}
    @_buf = []
    @_idx = 0
    @_error = 0
    @_isArray = Array.isArray or ((mix) ->
      Object::toString.call(mix) is "[object Array]"
    )
    @_toString = String.fromCharCode
    @_MAX_DEPTH = 512
    i = 0
    v = undefined
    while i < 0x100
      v = @_toString(i)
      @_bin2num[v] = i # "\00" -> 0x00
      @_num2bin[i] = v #     0 -> "\00"
      ++i

    # http://twitter.com/edvakf/statuses/15576483807
    i = 0x80 # [Webkit][Gecko]
    while i < 0x100
      @_bin2num[@_toString(0xf700 + i)] = i # "\f780" -> 0x80
      ++i

  msgpackpack: (data, toString) -> # @param Mix:
    # @param Boolean(= false):
    # @return ByteArray/BinaryString/false:
    #     false is error return
    #  [1][mix to String]    msgpack.pack({}, true) -> "..."
    #  [2][mix to ByteArray] msgpack.pack({})       -> [...]
    @_error = 0
    byteArray = @encode([], data, 0)
    (if @_error then false else (if toString then @byteArrayToByteString(byteArray) else byteArray))

  # msgpack.unpack
  msgpackunpack: (data) -> # @param BinaryString/ByteArray:
    # @return Mix/undefined:
    #       undefined is error return
    #  [1][String to mix]    msgpack.unpack("...") -> {}
    #  [2][ByteArray to mix] msgpack.unpack([...]) -> {}
    @_buf = (if typeof data is "string" then @toByteArray(data) else data)
    @_idx = -1
    @decode() # mix or undefined

  # inner - encoder
  encode: (rv, mix, depth) -> # @param ByteArray: result
    # @param Mix: source data
    # @param Number: depth
    size = undefined # for UTF8.encode, Array.encode, Hash.encode
    i = undefined
    iz = undefined
    c = undefined
    pos = undefined
    high = undefined
    low = undefined
    sign = undefined
    exp = undefined
    frac = undefined
    # for IEEE754
    unless mix? # null or undefined -> 0xc0 ( null )
      rv.push 0xc0
    else if mix is false # false -> 0xc2 ( false )
      rv.push 0xc2
    else if mix is true # true  -> 0xc3 ( true  )
      rv.push 0xc3
    else
      switch typeof mix
        when "number"
          if mix isnt mix # isNaN
            rv.push 0xcb, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff # quiet NaN
          else if mix is Infinity
            rv.push 0xcb, 0x7f, 0xf0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 # positive infinity
          else if Math.floor(mix) is mix # int or uint
            if mix < 0

              # int
              if mix >= -32 # negative fixnum
                rv.push 0xe0 + mix + 32
              else if mix > -0x80
                rv.push 0xd0, mix + 0x100
              else if mix > -0x8000
                mix += 0x10000
                rv.push 0xd1, mix >> 8, mix & 0xff
              else if mix > -0x80000000
                mix += 0x100000000
                rv.push 0xd2, mix >>> 24, (mix >> 16) & 0xff, (mix >> 8) & 0xff, mix & 0xff
              else
                high = Math.floor(mix / 0x100000000)
                low = mix & 0xffffffff
                rv.push 0xd3, (high >> 24) & 0xff, (high >> 16) & 0xff, (high >> 8) & 0xff, high & 0xff, (low >> 24) & 0xff, (low >> 16) & 0xff, (low >> 8) & 0xff, low & 0xff
            else

              # uint
              if mix < 0x80
                rv.push mix # positive fixnum
              else if mix < 0x100 # uint 8
                rv.push 0xcc, mix
              else if mix < 0x10000 # uint 16
                rv.push 0xcd, mix >> 8, mix & 0xff
              else if mix < 0x100000000 # uint 32
                rv.push 0xce, mix >>> 24, (mix >> 16) & 0xff, (mix >> 8) & 0xff, mix & 0xff
              else
                high = Math.floor(mix / 0x100000000)
                low = mix & 0xffffffff
                rv.push 0xcf, (high >> 24) & 0xff, (high >> 16) & 0xff, (high >> 8) & 0xff, high & 0xff, (low >> 24) & 0xff, (low >> 16) & 0xff, (low >> 8) & 0xff, low & 0xff
          else # double
            # THX!! @edvakf
            # http://javascript.g.hatena.ne.jp/edvakf/20101128/1291000731
            sign = mix < 0
            sign and (mix *= -1)

            # add offset 1023 to ensure positive
            # 0.6931471805599453 = Math.LN2;
            exp = ((Math.log(mix) / 0.6931471805599453) + 1023) | 0

            # shift 52 - (exp - 1023) bits to make integer part exactly 53 bits,
            # then throw away trash less than decimal point
            frac = mix * Math.pow(2, 52 + 1023 - exp)

            #  S+-Exp(11)--++-----------------Fraction(52bits)-----------------------+
            #  ||          ||                                                        |
            #  v+----------++--------------------------------------------------------+
            #  00000000|00000000|00000000|00000000|00000000|00000000|00000000|00000000
            #  6      5    55  4        4        3        2        1        8        0
            #  3      6    21  8        0        2        4        6
            #
            #  +----------high(32bits)-----------+ +----------low(32bits)------------+
            #  |                                 | |                                 |
            #  +---------------------------------+ +---------------------------------+
            #  3      2    21  1        8        0
            #  1      4    09  6
            low = frac & 0xffffffff
            sign and (exp |= 0x800)
            high = ((frac / 0x100000000) & 0xfffff) | (exp << 20)
            rv.push 0xcb, (high >> 24) & 0xff, (high >> 16) & 0xff, (high >> 8) & 0xff, high & 0xff, (low >> 24) & 0xff, (low >> 16) & 0xff, (low >> 8) & 0xff, low & 0xff
        when "string"

          # http://d.hatena.ne.jp/uupaa/20101128
          iz = mix.length
          pos = rv.length # keep rewrite position
          rv.push 0 # placeholder

          # utf8.encode
          i = 0
          while i < iz
            c = mix.charCodeAt(i)
            if c < 0x80 # ASCII(0x00 ~ 0x7f)
              rv.push c & 0x7f
            else if c < 0x0800
              rv.push ((c >>> 6) & 0x1f) | 0xc0, (c & 0x3f) | 0x80
            else rv.push ((c >>> 12) & 0x0f) | 0xe0, ((c >>> 6) & 0x3f) | 0x80, (c & 0x3f) | 0x80  if c < 0x10000
            ++i
          size = rv.length - pos - 1
          if size < 32
            rv[pos] = 0xa0 + size # rewrite
          else if size < 0x10000 # 16
            rv.splice pos, 1, 0xda, size >> 8, size & 0xff
          # 32
          else rv.splice pos, 1, 0xdb, size >>> 24, (size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff  if size < 0x100000000
        else # array or hash
          if ++depth >= @_MAX_DEPTH
            @_error = 1 # CYCLIC_REFERENCE_ERROR
            return rv = [] # clear
          if @_isArray(mix)
            size = mix.length
            if size < 16
              rv.push 0x90 + size
            else if size < 0x10000 # 16
              rv.push 0xdc, size >> 8, size & 0xff
            # 32
            else rv.push 0xdd, size >>> 24, (size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff  if size < 0x100000000
            i = 0
            while i < size
              @encode rv, mix[i], depth
              ++i
          else # hash
            # http://d.hatena.ne.jp/uupaa/20101129
            pos = rv.length # keep rewrite position
            rv.push 0 # placeholder
            size = 0
            for i of mix
              ++size
              encode rv, i, depth
              encode rv, mix[i], depth
            if size < 16
              rv[pos] = 0x80 + size # rewrite
            else if size < 0x10000 # 16
              rv.splice pos, 1, 0xde, size >> 8, size & 0xff
            # 32
            else rv.splice pos, 1, 0xdf, size >>> 24, (size >> 16) & 0xff, (size >> 8) & 0xff, size & 0xff  if size < 0x100000000
    rv

  # inner - decoder
  decode: -> # @return Mix:
    size = undefined
    i = undefined
    iz = undefined
    c = undefined
    num = 0
    sign = undefined
    exp = undefined
    frac = undefined
    ary = undefined
    hash = undefined
    buf = @_buf
    type = buf[++@_idx]
    # alert buf
    # alert @_idx
    # alert type
    console.log 'type:'+type
    # Negative FixNum (111x xxxx) (-32 ~ -1)
    return type - 0x100  if type >= 0xe0
    if type < 0xc0
      # Positive FixNum (0xxx xxxx) (0 ~ 127)
      return type  if type < 0x80
      if type < 0x90 # FixMap (1000 xxxx)
        num = type - 0x80
        type = 0x80
      else if type < 0xa0 # FixArray (1001 xxxx)
        num = type - 0x90
        type = 0x90
      else # if (type < 0xc0) {   // FixRaw (101x xxxx)
        num = type - 0xa0
        type = 0xa0
    switch type
      when 0xc0
        return null
      when 0xc2
        return false
      when 0xc3
        return true
      when 0xca # float
        num = buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16) + (buf[++@_idx] << 8) + buf[++@_idx]
        sign = num & 0x80000000 #  1bit
        exp = (num >> 23) & 0xff #  8bits
        frac = num & 0x7fffff # 23bits
        # 0.0 or -0.0
        return 0  if not num or num is 0x80000000
        # NaN or Infinity
        return (if frac then NaN else Infinity)  if exp is 0xff
        return ((if sign then -1 else 1)) * (frac | 0x800000) * Math.pow(2, exp - 127 - 23) # 127: bias
      when 0xcb # double
        num = buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16) + (buf[++@_idx] << 8) + buf[++@_idx]
        sign = num & 0x80000000 #  1bit
        exp = (num >> 20) & 0x7ff # 11bits
        frac = num & 0xfffff # 52bits - 32bits (high word)
        if not num or num is 0x80000000 # 0.0 or -0.0
          @_idx += 4
          return 0
        if exp is 0x7ff # NaN or Infinity
          @_idx += 4
          return (if frac then NaN else Infinity)
        num = buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16) + (buf[++@_idx] << 8) + buf[++@_idx]
        # 1023: bias
        return ((if sign then -1 else 1)) * ((frac | 0x100000) * Math.pow(2, exp - 1023 - 20) + num * Math.pow(2, exp - 1023 - 52))

      # 0xcf: uint64, 0xce: uint32, 0xcd: uint16
      when 0xcf
        num = buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16) + (buf[++@_idx] << 8) + buf[++@_idx]
        return num * 0x100000000 + buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16) + (buf[++@_idx] << 8) + buf[++@_idx]
      when 0xce
        num += buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16)
      when 0xcd
        num += buf[++@_idx] << 8
      when 0xcc
        return num + buf[++@_idx]

      # 0xd3: int64, 0xd2: int32, 0xd1: int16, 0xd0: int8
      when 0xd3
        num = buf[++@_idx]
        # sign -> avoid overflow
        return ((num ^ 0xff) * 0x100000000000000 + (buf[++@_idx] ^ 0xff) * 0x1000000000000 + (buf[++@_idx] ^ 0xff) * 0x10000000000 + (buf[++@_idx] ^ 0xff) * 0x100000000 + (buf[++@_idx] ^ 0xff) * 0x1000000 + (buf[++@_idx] ^ 0xff) * 0x10000 + (buf[++@_idx] ^ 0xff) * 0x100 + (buf[++@_idx] ^ 0xff) + 1) * -1  if num & 0x80
        return num * 0x100000000000000 + buf[++@_idx] * 0x1000000000000 + buf[++@_idx] * 0x10000000000 + buf[++@_idx] * 0x100000000 + buf[++@_idx] * 0x1000000 + buf[++@_idx] * 0x10000 + buf[++@_idx] * 0x100 + buf[++@_idx]
      when 0xd2
        num = buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16) + (buf[++@_idx] << 8) + buf[++@_idx]
        return (if num < 0x80000000 then num else num - 0x100000000) # 0x80000000 * 2
      when 0xd1
        num = (buf[++@_idx] << 8) + buf[++@_idx]
        return (if num < 0x8000 then num else num - 0x10000) # 0x8000 * 2
      when 0xd0
        num = buf[++@_idx]
        return (if num < 0x80 then num else num - 0x100) # 0x80 * 2
      # 0xdb: raw32, 0xda: raw16, 0xa0: raw ( string )
      when 0xdb
        num += buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16)
      when 0xda
        num += (buf[++@_idx] << 8) + buf[++@_idx]
      when 0xa0 # utf8.decode
        ary = []
        i = @_idx
        iz = i + num

        while i < iz
          c = buf[++i] # lead byte
          # ASCII(0x00 ~ 0x7f)
          ary.push (if c < 0x80 then c else (if c < 0xe0 then ((c & 0x1f) << 6 | (buf[++i] & 0x3f)) else ((c & 0x0f) << 12 | (buf[++i] & 0x3f) << 6 | (buf[++i] & 0x3f))))
        @_idx = i
        return (if ary.length < 10240 then @_toString.apply(null, ary) else @byteArrayToByteString(ary))

      # 0xdf: map32, 0xde: map16, 0x80: map
      when 0xdf
        num += buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16)
      when 0xde
        num += (buf[++@_idx] << 8) + buf[++@_idx]
      when 0x80
        hash = {}
        while num--

          # make key/value pair
          size = buf[++@_idx] - 0xa0
          ary = []
          i = @_idx
          iz = i + size

          while i < iz
            c = buf[++i] # lead byte
            # ASCII(0x00 ~ 0x7f)
            ary.push (if c < 0x80 then c else (if c < 0xe0 then ((c & 0x1f) << 6 | (buf[++i] & 0x3f)) else ((c & 0x0f) << 12 | (buf[++i] & 0x3f) << 6 | (buf[++i] & 0x3f))))
          @_idx = i
          hash[@_toString.apply(null, ary)] = @decode()
        return hash

      # 0xdd: array32, 0xdc: array16, 0x90: array
      when 0xdd
        num += buf[++@_idx] * 0x1000000 + (buf[++@_idx] << 16)
      when 0xdc
        num += (buf[++@_idx] << 8) + buf[++@_idx]
      when 0x90
        ary = []
        ary.push @decode()  while num--
        return ary
    return

  # inner - byteArray To ByteString
  byteArrayToByteString: (byteArray) -> # @param ByteArray
    # @return String
    # http://d.hatena.ne.jp/uupaa/20101128
    try
      return @_toString.apply(this, byteArray) # toString
    # avoid "Maximum call stack size exceeded"
    rv = []
    i = 0
    iz = byteArray.length
    num2bin = @_num2bin
    while i < iz
      rv[i] = num2bin[byteArray[i]]
      ++i
    rv.join ""

  # inner - BinaryString To ByteArray
  toByteArray: (data) -> # @param BinaryString: "\00\01"
    # @return ByteArray: [0x00, 0x01]
    rv = []
    bin2num = @_bin2num
    remain = undefined
    ary = data.split("")
    i = -1
    iz = undefined
    iz = ary.length
    remain = iz % 8
    while remain--
      ++i
      rv[i] = bin2num[ary[i]]
    remain = iz >> 3
    rv.push bin2num[ary[++i]], bin2num[ary[++i]], bin2num[ary[++i]], bin2num[ary[++i]], bin2num[ary[++i]], bin2num[ary[++i]], bin2num[ary[++i]], bin2num[ary[++i]]  while remain--
    rv

module.exports =
class VimState
  editor: null
  opStack: null
  mode: null
  submode: null

  constructor: (@editorView) ->
    @editor = @editorView.editor
    @opStack = []
    @history = []
    @marks = {}
    params = {}
    params.manager = this;
    params.id = 0;

    @setupCommandMode()
    @registerInsertIntercept()
    @registerInsertTransactionResets()
    if atom.config.get 'vim-mode.startInInsertMode'
      @activateInsertMode()
    else
      @activateCommandMode()

    socket = new net.Socket()
    socket.connect('/Users/carlos/tmp/neovim');
    msgpack = new MsgPack()
    msg = msgpack.msgpackpack([0,1,0,[]])
    upa = msgpack.msgpackunpack(msg)
    console.log upa

    console.log msg
    socket.on('data', (data) =>
        console.log data.toString()
        dl = []
        i = 0
        while i < data.length
          dl.push data[i]
          ++i
        console.log dl
        q = msgpack.msgpackunpack(dl)
        console.log q
    )
    socket.write(new Buffer(msg))


    atom.project.eachBuffer (buffer) =>
      @registerChangeHandler(buffer)

  # Private: Creates a handle to block insertion while in command mode.
  #
  # This is currently a bit of a hack. If a user is in command mode they
  # won't be able to type in any of Atom's dialogs (such as the command
  # palette). This also doesn't block non-printable characters such as
  # backspace.
  #
  # There should probably be a better API on the editor to handle this
  # but the requirements aren't clear yet, so this will have to suffice
  # for now.
  #
  # Returns nothing.
  registerInsertIntercept: ->
    @editorView.preempt 'textInput', (e) =>
      return if $(e.currentTarget).hasClass('mini')

      if @mode == 'insert'
        true
      else
        @clearOpStack()
        false

  # Private: Reset transactions on input for undo/redo/repeat on several
  # core and vim-mode events
  registerInsertTransactionResets: ->
    events = [ 'core:move-up'
               'core:move-down'
               'core:move-right'
               'core:move-left' ]
    @editorView.on events.join(' '), =>
      @resetInputTransactions()


  # Private: Watches for any deletes on the current buffer and places it in the
  # last deleted buffer.
  #
  # Returns nothing.
  registerChangeHandler: (buffer) ->
    buffer.on 'changed', ({newRange, newText, oldRange, oldText}) =>
      return unless @setRegister?
      if newText == ''
        @setRegister('"', text: oldText, type: Utils.copyType(oldText))

  # Private: Creates the plugin's bindings
  #
  # Returns nothing.
  setupCommandMode: ->
    @registerCommands
      'activate-command-mode': => @activateCommandMode()
      'activate-linewise-visual-mode': => @activateVisualMode('linewise')
      'activate-characterwise-visual-mode': => @activateVisualMode('characterwise')
      'activate-blockwise-visual-mode': => @activateVisualMode('blockwise')
      'reset-command-mode': => @resetCommandMode()
      'repeat-prefix': (e) => @repeatPrefix(e)

    @registerOperationCommands
      'activate-insert-mode': => new Operators.Insert(@editor, @)
      'substitute': => new Operators.Substitute(@editor, @)
      'substitute-line': => new Operators.SubstituteLine(@editor, @)
      'insert-after': => new Operators.InsertAfter(@editor, @)
      'insert-after-end-of-line': => [new Motions.MoveToLastCharacterOfLine(@editor), new Operators.InsertAfter(@editor, @)]
      'insert-at-beginning-of-line': => [new Motions.MoveToFirstCharacterOfLine(@editor), new Operators.Insert(@editor, @)]
      'insert-above-with-newline': => new Operators.InsertAboveWithNewline(@editor, @)
      'insert-below-with-newline': => new Operators.InsertBelowWithNewline(@editor, @)
      'delete': => @linewiseAliasedOperator(Operators.Delete)
      'change': => @linewiseAliasedOperator(Operators.Change)
      'change-to-last-character-of-line': => [new Operators.Change(@editor, @), new Motions.MoveToLastCharacterOfLine(@editor)]
      'delete-right': => [new Operators.Delete(@editor, @), new Motions.MoveRight(@editor)]
      'delete-left': => [new Operators.Delete(@editor, @), new Motions.MoveLeft(@editor)]
      'delete-to-last-character-of-line': => [new Operators.Delete(@editor, @), new Motions.MoveToLastCharacterOfLine(@editor)]
      'toggle-case': => new Operators.ToggleCase(@editor, @)
      'yank': => @linewiseAliasedOperator(Operators.Yank)
      'yank-line': => [new Operators.Yank(@editor, @), new Motions.MoveToLine(@editor)]
      'put-before': => new Operators.Put(@editor, @, location: 'before')
      'put-after': => new Operators.Put(@editor, @, location: 'after')
      'join': => new Operators.Join(@editor, @)
      'indent': => @linewiseAliasedOperator(Operators.Indent)
      'outdent': => @linewiseAliasedOperator(Operators.Outdent)
      'auto-indent': => @linewiseAliasedOperator(Operators.Autoindent)
      'move-left': => new Motions.MoveLeft(@editor, @)
      'move-up': => new Motions.MoveUp(@editor, @)
      'move-down': => new Motions.MoveDown(@editor, @)
      'move-right': => new Motions.MoveRight(@editor, @)
      'move-to-next-word': => new Motions.MoveToNextWord(@editor)
      'move-to-next-whole-word': => new Motions.MoveToNextWholeWord(@editor)
      'move-to-end-of-word': => new Motions.MoveToEndOfWord(@editor)
      'move-to-end-of-whole-word': => new Motions.MoveToEndOfWholeWord(@editor)
      'move-to-previous-word': => new Motions.MoveToPreviousWord(@editor)
      'move-to-previous-whole-word': => new Motions.MoveToPreviousWholeWord(@editor)
      'move-to-next-paragraph': => new Motions.MoveToNextParagraph(@editor)
      'move-to-previous-paragraph': => new Motions.MoveToPreviousParagraph(@editor)
      'move-to-first-character-of-line': => new Motions.MoveToFirstCharacterOfLine(@editor)
      'move-to-last-character-of-line': => new Motions.MoveToLastCharacterOfLine(@editor)
      'move-to-beginning-of-line': (e) => @moveOrRepeat(e)
      'move-to-start-of-file': => new Motions.MoveToStartOfFile(@editor)
      'move-to-line': => new Motions.MoveToLine(@editor)
      'move-to-top-of-screen': => new Motions.MoveToTopOfScreen(@editor, @editorView)
      'move-to-bottom-of-screen': => new Motions.MoveToBottomOfScreen(@editor, @editorView)
      'move-to-middle-of-screen': => new Motions.MoveToMiddleOfScreen(@editor, @editorView)
      'scroll-down': => new Scroll.ScrollDown(@editorView, @editor)
      'scroll-up': => new Scroll.ScrollUp(@editorView, @editor)
      'select-inside-word': => new TextObjects.SelectInsideWord(@editor)
      'select-inside-double-quotes': => new TextObjects.SelectInsideQuotes(@editor, '"')
      'select-inside-single-quotes': => new TextObjects.SelectInsideQuotes(@editor, '\'')
      'select-inside-curly-brackets': => new TextObjects.SelectInsideBrackets(@editor, '{', '}')
      'select-inside-angle-brackets': => new TextObjects.SelectInsideBrackets(@editor, '<', '>')
      'select-inside-parentheses': => new TextObjects.SelectInsideBrackets(@editor, '(', ')')
      'register-prefix': (e) => @registerPrefix(e)
      'repeat': (e) => new Operators.Repeat(@editor, @)
      'repeat-search': (e) => currentSearch.repeat() if (currentSearch = Motions.Search.currentSearch)?
      'repeat-search-backwards': (e) => currentSearch.repeat(backwards: true) if (currentSearch = Motions.Search.currentSearch)?
      'focus-pane-view-on-left': => new Panes.FocusPaneViewOnLeft()
      'focus-pane-view-on-right': => new Panes.FocusPaneViewOnRight()
      'focus-pane-view-above': => new Panes.FocusPaneViewAbove()
      'focus-pane-view-below': => new Panes.FocusPaneViewBelow()
      'focus-previous-pane-view': => new Panes.FocusPreviousPaneView()
      'move-to-mark': (e) => new Motions.MoveToMark(@editorView, @)
      'move-to-mark-literal': (e) => new Motions.MoveToMark(@editorView, @, false)
      'mark': (e) => new Operators.Mark(@editorView, @)
      'find': (e) => new Motions.Find(@editorView, @)
      'find-backwards': (e) => new Motions.Find(@editorView, @).reverse()
      'till': (e) => new Motions.Till(@editorView, @)
      'till-backwards': (e) => new Motions.Till(@editorView, @).reverse()
      'replace': (e) => new Operators.Replace(@editorView, @)
      'search': (e) => new Motions.Search(@editorView, @)
      'reverse-search': (e) => (new Motions.Search(@editorView, @)).reversed()
      'search-current-word': (e) => new Motions.SearchCurrentWord(@editorView, @)
      'bracket-matching-motion': (e) => new Motions.BracketMatchingMotion(@editorView,@)
      'reverse-search-current-word': (e) => (new Motions.SearchCurrentWord(@editorView, @)).reversed()

  # Private: Register multiple command handlers via an {Object} that maps
  # command names to command handler functions.
  #
  # Prefixes the given command names with 'vim-mode:' to reduce redundancy in
  # the provided object.
  registerCommands: (commands) ->
    for commandName, fn of commands
      do (fn) =>
        @editorView.command "vim-mode:#{commandName}.vim-mode", fn

  # Private: Register multiple Operators via an {Object} that
  # maps command names to functions that return operations to push.
  #
  # Prefixes the given command names with 'vim-mode:' to reduce redundancy in
  # the given object.
  registerOperationCommands: (operationCommands) ->
    commands = {}
    for commandName, operationFn of operationCommands
      do (operationFn) =>
        commands[commandName] = (event) => @pushOperations(operationFn(event))
    @registerCommands(commands)

  # Private: Push the given operations onto the operation stack, then process
  # it.
  pushOperations: (operations) ->
    return unless operations?
    operations = [operations] unless _.isArray(operations)

    for operation in operations
      # Motions in visual mode perform their selections.
      if @mode is 'visual' and (operation instanceof Motions.Motion or operation instanceof TextObjects.TextObject)
        operation.execute = operation.select

      # if we have started an operation that responds to canComposeWith check if it can compose
      # with the operation we're going to push onto the stack
      if (topOp = @topOperation())? and topOp.canComposeWith? and not topOp.canComposeWith(operation)
        @editorView.trigger 'vim-mode:compose-failure'
        @resetCommandMode()
        break

      @opStack.push(operation)

      # If we've received an operator in visual mode, mark the current
      # selection as the motion to operate on.
      if @mode is 'visual' and operation instanceof Operators.Operator
        @opStack.push(new Motions.CurrentSelection(@))

      @processOpStack()

  # Private: Removes all operations from the stack.
  #
  # Returns nothing.
  clearOpStack: ->
    @opStack = []

  # Private: Processes the command if the last operation is complete.
  #
  # Returns nothing.
  processOpStack: ->
    unless @opStack.length > 0
      return

    unless @topOperation().isComplete()
      if @mode is 'command' and @topOperation() instanceof Operators.Operator
        @activateOperatorPendingMode()
      return

    poppedOperation = @opStack.pop()
    if @opStack.length
      try
        @topOperation().compose(poppedOperation)
        @processOpStack()
      catch e
        ((e instanceof Operators.OperatorError) or (e instanceof Motions.MotionError)) and @resetCommandMode() or throw e
    else
      @history.unshift(poppedOperation) if poppedOperation.isRecordable()
      poppedOperation.execute()

  # Private: Fetches the last operation.
  #
  # Returns the last operation.
  topOperation: ->
    _.last @opStack

  # Private: Fetches the value of a given register.
  #
  # name - The name of the register to fetch.
  #
  # Returns the value of the given register or undefined if it hasn't
  # been set.
  getRegister: (name) ->
    if name in ['*', '+']
      text = atom.clipboard.read()
      type = Utils.copyType(text)
      {text, type}
    else if name == '%'
      text = @editor.getUri()
      type = Utils.copyType(text)
      {text, type}
    else if name == "_" # Blackhole always returns nothing
      text = ''
      type = Utils.copyType(text)
      {text, type}
    else
      atom.workspace.vimState.registers[name]

  # Private: Fetches the value of a given mark.
  #
  # name - The name of the mark to fetch.
  #
  # Returns the value of the given mark or undefined if it hasn't
  # been set.
  getMark: (name) ->
    if @marks[name]
      @marks[name].getBufferRange().start
    else
      undefined


  # Private: Sets the value of a given register.
  #
  # name  - The name of the register to fetch.
  # value - The value to set the register to.
  #
  # Returns nothing.
  setRegister: (name, value) ->
    if name in ['*', '+']
      atom.clipboard.write(value.text)
    else if name == '_'
      # Blackhole register, nothing to do
    else
      atom.workspace.vimState.registers[name] = value

  # Private: Sets the value of a given mark.
  #
  # name  - The name of the mark to fetch.
  # pos {Point} - The value to set the mark to.
  #
  # Returns nothing.
  setMark: (name, pos) ->
    # check to make sure name is in [a-z] or is `
    if (charCode = name.charCodeAt(0)) >= 96 and charCode <= 122
      marker = @editor.markBufferRange(new Range(pos,pos),{invalidate:'never',persistent:false})
      @marks[name] = marker

  # Public: Append a search to the search history.
  #
  # Motions.Search - The confirmed search motion to append
  #
  # Returns nothing
  pushSearchHistory: (search) ->
    atom.workspace.vimState.searchHistory.unshift search

  # Public: Get the search history item at the given index.
  #
  # index - the index of the search history item
  #
  # Returns a search motion
  getSearchHistoryItem: (index) ->
    atom.workspace.vimState.searchHistory[index]

  resetInputTransactions: ->
    return unless @mode == 'insert' && @history[0]?.inputOperator?()
    @deactivateInsertMode()
    @activateInsertMode()

  ##############################################################################
  # Mode Switching
  ##############################################################################

  # Private: Used to enable command mode.
  #
  # Returns nothing.
  activateCommandMode: ->
    @deactivateInsertMode()
    @mode = 'command'
    @submode = null

    if @editorView.is(".insert-mode")
      cursor = @editor.getCursor()
      cursor.moveLeft() unless cursor.isAtBeginningOfLine()

    @changeModeClass('command-mode')

    @clearOpStack()
    @editor.clearSelections()

    @updateStatusBar()

  # Private: Used to enable insert mode.
  #
  # Returns nothing.
  activateInsertMode: (transactionStarted = false)->
    @mode = 'insert'
    @editor.beginTransaction() unless transactionStarted
    @submode = null
    @changeModeClass('insert-mode')
    @updateStatusBar()

  deactivateInsertMode: ->
    return unless @mode == 'insert'
    @editor.commitTransaction()
    transaction = _.last(@editor.buffer.history.undoStack)
    item = @inputOperator(@history[0])
    if item? and transaction?
      item.confirmTransaction(transaction)

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
    for mode in ['command-mode', 'insert-mode', 'visual-mode', 'operator-pending-mode']
      if mode is targetMode
        @editorView.addClass(mode)
      else
        @editorView.removeClass(mode)

  # Private: Resets the command mode back to it's initial state.
  #
  # Returns nothing.
  resetCommandMode: ->
    @activateCommandMode()

  # Private: A generic way to create a Register prefix based on the event.
  #
  # e - The event that triggered the Register prefix.
  #
  # Returns nothing.
  registerPrefix: (e) ->
    name = atom.keymap.keystrokeStringForEvent(e.originalEvent)
    new Prefixes.Register(name)

  # Private: A generic way to create a Number prefix based on the event.
  #
  # e - The event that triggered the Number prefix.
  #
  # Returns nothing.
  repeatPrefix: (e) ->
    num = parseInt(atom.keymap.keystrokeStringForEvent(e.originalEvent))
    if @topOperation() instanceof Prefixes.Repeat
      @topOperation().addDigit(num)
    else
      if num is 0
        e.abortKeyBinding()
      else
        @pushOperations(new Prefixes.Repeat(num))

  # Private: Figure out whether or not we are in a repeat sequence or we just
  # want to move to the beginning of the line. If we are within a repeat
  # sequence, we pass control over to @repeatPrefix.
  #
  # e - The triggered event.
  #
  # Returns new motion or nothing.
  moveOrRepeat: (e) ->
    if @topOperation() instanceof Prefixes.Repeat
      @repeatPrefix(e)
      null
    else
      new Motions.MoveToBeginningOfLine(@editor)

  # Private: A generic way to handle Operators that can be repeated for
  # their linewise form.
  #
  # constructor - The constructor of the operator.
  #
  # Returns nothing.
  linewiseAliasedOperator: (constructor) ->
    if @isOperatorPending(constructor)
      new Motions.MoveToLine(@editor)
    else
      new constructor(@editor, @)

  # Private: Check if there is a pending operation of a certain type
  #
  # constructor - The constructor of the object type you're looking for.
  #
  # Returns nothing.
  isOperatorPending: (constructor) ->
    for op in @opStack
      return op if op instanceof constructor
    false

  updateStatusBar: ->
    if !$('#status-bar-vim-mode').length
      atom.packages.once 'activated', ->
        atom.workspaceView.statusBar?.prependRight("<div id='status-bar-vim-mode' class='inline-block'>Command</div>")

    if @mode is "insert"
      $('#status-bar-vim-mode').html("Insert")
    else if @mode is "command"
      $('#status-bar-vim-mode').html("Command")
    else if @mode is "visual"
      $('#status-bar-vim-mode').html("Visual")
