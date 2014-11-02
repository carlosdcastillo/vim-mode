# What is this?

This is a work in progress branch that shows how to make Atom talk to Neovim.

# What do you want to do with this?

This project aims to:

* Bring real vim bindings to Atom.
* Give the redraw-events neovim patch and the sendkey patch a work out and find
issues using the msgpack api.
* Eventually build an editor that I would find useful. At the current state it is
pre-alpha.

# See it in action

A video of the integration in action:

http://www.youtube.com/watch?v=lH_zb7X6mZw

# Things TO DO

* Update to support the msgpack API of the latest version of Neovim.
* Update the code to handle the UI details such as the command mode indicator
and show the command line when you type :w and such.
* Fix the several issues with the communication in such a way that there are no
breaks in communication.
