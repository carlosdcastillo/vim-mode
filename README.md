# What is this?

This is a work in progress branch that shows how to make Atom talk to Neovim.

# What's new?

I've updated it to use the abstract-ui branch, it no longer uses the redraw-events patch.

To use this you will need to install neovim from @tarruda's abstract-ui-fixes
branch. The last commit should be: 

commit b430078047256810fed734661b8b2bf2e4c32977
Author: Thiago de Arruda <tpadilha84@gmail.com>
Date:   Fri Jan 2 21:16:18 2015 -0300

    runtime: Fix plugin/matchparen.vim for abstract_ui

# What do you want to do with this?

This project aims to:

* Bring real vim bindings to Atom.
* Give the abstract-ui neovim patch a work out and find issues using the msgpack api.
* Eventually build an editor that I would find useful. At the current state it is
pre-alpha.

# See it in action

A video of the integration in action:

http://www.youtube.com/watch?v=lH_zb7X6mZw

# Things TO DO

* Handle Atom-centric text editing actions, i.e., situations like the user searching and replacing in Atom by hitting Cmd-F
* Fix the several issues with the communication in such a way that there are no
breaks in communication.
* Update the code to handle the UI details such as the command mode indicator
and show the command line when you type :w and such.

# Contributing

1. Find something that doesn't work (this step shouldn't be that hard, plenty of things don't work yet)
2. Fix it. 
3. Send me a pull request.
