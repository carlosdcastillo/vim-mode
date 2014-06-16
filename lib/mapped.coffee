no_weakmap_get = (target) ->
  new DataView(target, 0)
get = (target) ->
  out = map.get(target.buffer)
  map.set target.buffer, out = new DataView(target.buffer, 0)  unless out
  out
proto = undefined
map = undefined
module.exports = proto = {}
map = (if typeof WeakMap is "undefined" then null else new WeakMap)
proto.get = (if not map then no_weakmap_get else get)
