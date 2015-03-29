# What is this?

This is a work in progress Atom package that implements complete vim bindings
by connecting to Neovim.

# What's new?
I've update everything to work with the version in master of
[Neovim](http://github.com/neovim/neovim)

On the [Atom](https://atom.io/) side I've tested it with version 0.175 and
0.184 and seems to work fine.

It should be usable enough that if you are adventurous you will be able to get
day-to-day work done. There are, however, plenty of features missing, so you
will have to be patient when you use it.

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

* Fix hiccups when editing a new file (a new tab with title undefined is
created)
* Make the geometry of the Atom buffer fully match the geometry of the Neovim
buffer.
* Find a solution to syncing when the file has a line with more than 
96 characters.
* Handle Atom-centric text editing actions, i.e., situations like the user
searching and replacing in Atom by hitting Cmd-F
* Handle files of more than 9999 lines.
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

