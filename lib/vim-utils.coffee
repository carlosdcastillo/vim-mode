

module.exports =
    
normalize_filename: (filename) ->
  if filename
    filename = filename.split('\\').join('/')
  return filename

range: (start, stop, step) ->
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
    

buf2str: (buffer) ->
  if not buffer
    return ''
  res = ''
  i = 0
  while i < buffer.length
    res = res + String.fromCharCode(buffer[i])
    i++
  res

