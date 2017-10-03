
MsgPack = require 'msgpack5rpc'
os = require 'os'
net = require 'net'
cp = require 'child_process'

socket_address = () ->
  if os.platform() is 'win32'
    '\\\\.\\pipe\\neovim'
  else
    '/tmp/neovim/neovim'

nvim_proc = undefined

input = undefined
output = undefined

if atom.config.get('vim-mode.embed')
  nvim_proc = cp.spawn(
    atom.config.get('vim-mode.neovim-path'),
    ['--embed', '-u', 'NONE', '-N'],
    {})
  console.log('Spawning nvim instance')
  input = nvim_proc.stdin
  output = nvim_proc.stdout
else
  tmp_socket = new net.Socket()
  tmp_socket.connect(socket_address())
  tmp_socket.on('error', (error) ->
    console.log 'error communicating (send message): ' + error
    tmp_socket.destroy()
  )
  console.log('Connecting to existing nvim instance')
  input = tmp_socket
  output = tmp_socket

tmpsession = new MsgPack()
tmpsession.attach(input, output)

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

  if !atom.config.get('vim-mode.embed')
    socket = new net.Socket()
    socket.connect(socket_address())
    input = socket
    output = socket

  session = new MsgPack(types)
  session.attach(input, output)
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

