
MsgPack = require 'msgpack5rpc'
os = require 'os'
net = require 'net'

if os.platform() is 'win32'
  CONNECT_TO = '\\\\.\\pipe\\neovim'
else
  CONNECT_TO = '/tmp/neovim/neovim'

socket2 = new net.Socket()
socket2.connect(CONNECT_TO)
socket2.on('error', (error) ->
  console.log 'error communicating (send message): ' + error
  socket2.destroy()
)
tmpsession = new MsgPack()
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

# Actual persisted session
session = undefined

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

  session = new MsgPack(types)
  session.attach(socket, socket)
)

module.exports = {
  sendMessage: (message,f = undefined) ->
    try
      if message[0] and message[1]
        session.request(message[0], message[1], (err, res) ->
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

  addNotificationListener: (callback) ->
    session.on('notification', callback)
}

