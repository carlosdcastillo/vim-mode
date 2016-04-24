root = exports ? this

unless root.lupdates
  root.lupdates = []

unless root.session
  root.session = undefined


unless root.current_editor
  root.current_editor = undefined

unless root.tlnumber
  root.tlnumber = 0

unless root.internal_change
  internal_change = false

unless root.updating
  updating = false
