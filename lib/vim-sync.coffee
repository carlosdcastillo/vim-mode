
util = require 'util'
VimGlobals = require './vim-globals'
VimUtils = require './vim-utils'

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

#This function changes the text between start and end changing the number
#of lines by delta. The change occurs directionaly from Atom -> Neovim.
#There is a bunch of bookkeeping to make sure the change is unidirectional.

neovim_set_text = (text, start, end, delta) ->
  lines_tmp = text.split('\n')
  lines = []
  for item in lines_tmp
    lines.push item.split('\r').join('')

  lines = lines[0..lines.length-1]
  cpos = VimGlobals.current_editor.getCursorBufferPosition()

  neovim_send_message(['vim_get_current_buffer',[]],
    ((buf) ->
        #console.log 'buff',buf
      neovim_send_message(['buffer_line_count',[buf]],
        ((vim_cnt) ->

          neovim_send_message(['buffer_get_line_slice', [buf, 0,
                                                        parseInt(vim_cnt),
                                                        true,
                                                        false]],
            ((vim_lines_r) ->
              vim_lines = []
              for item in vim_lines_r
                vim_lines.push item
              l = []
              pos = 0
              for pos in [0..vim_lines.length + delta-1]
                item = vim_lines[pos]
                if pos < start
                  l.push(item)

                if pos >= start and pos <= end + delta
                  l.push(lines[pos])

                if pos > end + delta
                  l.push(vim_lines[pos-delta])


              send_data(buf,l,-delta, cpos.row+1, cpos.column+1)

            )
          )
        )
      )
    )
  )

#This function sends the data and updates the the cursor location. It then
#calls a function to update the state to the syncing from Atom -> Neovim
#stops and the Neovim -> Atom change resumes.

send_data = (buf, l, i, r, c) ->
  lines = []
  l2 = []
  for item in l
    if item
      item2 = item.split('\\').join('\\\\')
      if item2
        item2 = item2.split('"').join('\\"')
        if item2
          l2.push '"'+item2+'"'
        else
          l2.push '""'
      else
        l2.push '""'
    else
      l2.push '""'

  #lines.push('undojoin')
  lines.push('cal setline(1, ['+l2.join()+'])')
  #lines.push('undojoin')

  if i > 0
    j = l.length + i
    while j > l.length
      lines.push(''+(j)+'d')
      #lines.push('undojoin')
      j = j - 1

  lines.push('cal cursor('+r+','+c+')')
  console.log 'lines2',lines

  VimGlobals.internal_change = true
  VimGlobals.updating = true
  neovim_send_message(['vim_command', [lines.join(' | ')]],
                      update_state)

#This function redraws everything and updates the state to re-enable
#Neovim -> Atom syncing.

update_state = () ->
  VimGlobals.updating = false
  VimGlobals.internal_change = false


module.exports =

#This function performs the "real update" from Atom -> Neovim. In case
#of Cmd-X, Cmd-V, etc.

    real_update : () ->
      if not VimGlobals.updating
        VimGlobals.updating = true

        curr_updates = VimGlobals.lupdates.slice(0)

        VimGlobals.lupdates = []
        if curr_updates.length > 0

          for item in curr_updates
              #console.log 'item:',item
            if item.uri is atom.workspace.getActiveTextEditor().getURI()
              neovim_set_text(item.text, item.start, item.end, item.delta)


