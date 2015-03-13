# What is this?

This is a work in progress branch that shows how to make Atom talk to Neovim.

# What's new?
I've update everything to work with the version in master of
[Neovim](http://github.com/neovim/neovim)

On the [Atom](https://atom.io/) side I've tested it with version 0.175 and
0.184 and seems to work fine.

# How do you run this?

Install, run, and quit Atom to make sure .atom exists

Install vim-mode

    $ cd .atom/packages
    $ git clone https://github.com/carlosdcastillo/vim-mode.git
    $ cd vim-mode
    $ apm install # install dependencies

Create a folder for the socket

    $ mkdir -p /tmp/neovim

Run Neovim, pointing it to the socket

    $ NVIM_LISTEN_ADDRESS=/tmp/neovim/neovim581 nvim 

# What do you want to do with this?

This project aims to:

* Bring real vim bindings to Atom.
* Give the abstract-ui neovim functionality a work out and find issues using
the msgpack api.
* Eventually build an editor that I would find useful. At the current state it is
pre-alpha.

# See it in action

A video that shows the integration in action in March/2015:

https://www.youtube.com/watch?v=7TVBcdONEJo

An older video from January of the integration in action, using the abstract-ui branch:

https://www.youtube.com/watch?v=yluIxQRjUCk

and this is an old video from 2014 using the old redraw-events branch (from mid 2014):

http://www.youtube.com/watch?v=lH_zb7X6mZw

# Things TO DO

* Handle Atom-centric text editing actions, i.e., situations like the user
searching and replacing in Atom by hitting Cmd-F
* Make the scroll wheel work.
* Handle files of more than 9999 lines.
* Make Atom not complain about the file having been changed when it hasn't.
More importantly make Cmd-S not make a mess of your file.
* Make one of the following UI connections/integrations: visual selection,
highlight search, auto completion, etc.

# Contributing

1. Find something that doesn't work (this step shouldn't be that hard, plenty
of things don't work yet)
2. Fix it. 
3. Send me a pull request.

# Configuring Atom
To make sure that hjkl get repeated like (Vim and Neovim) on Mac you will need to
run (from the command line):

    defaults write com.github.atom ApplePressAndHoldEnabled -bool false

