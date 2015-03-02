map = require './mapped'
Buffer = require("buffer").Buffer

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

module.exports = proto={}

proto.encode_pub = (value) ->
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


proto.decode_pub = (buffer) ->
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

proto.to_uint8array = (str) ->
  new Uint8Array(str);

str2ab = (str) ->
  bufView = new Uint8Array(str.length)
  i = 0
  strLen = str.length

  while i < strLen
    bufView[i] = str.charCodeAt(i)
    i++
  bufView

