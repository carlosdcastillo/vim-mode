# What is this?

This is a work in progress [Atom](http://atom.io/) package that implements
complete vim bindings by connecting to
[Neovim](http://github.com/neovim/neovim).

# What's new?

I've update everything to work with Neovim 0.1.2 (it should also work with the
version in master of [Neovim](http://github.com/neovim/neovim). The version
I'm currently using: [download]( https://github.com/neovim/neovim/archive/v0.1.2.tar.gz).

On the [Atom](https://atom.io/) side I am currently using version 1.5.3. In
versions 0.206 and later you will need to change the name of the directory
vim-mode to something else (I use the name nvim-mode). If you don't Atom
confuses this plugin with the one developed by GitHub.

It should be usable enough that if you are adventurous you will be able to get
day-to-day work done. There are, however, plenty of features missing, so you
will have to be patient when you use it.

# How do you run this?

Install, run, and quit Atom to make sure .atom exists

Install vim-mode

    $ cd .atom/packages
    $ git clone https://github.com/carlosdcastillo/vim-mode.git
    $ cd vim-mode
    $ apm install 

On OS X and Linux, create a folder for the named pipe:

    $ mkdir -p /tmp/neovim

Run Neovim, pointing it to the named pipe, on OS X and Linux:

    $ NVIM_LISTEN_ADDRESS=/tmp/neovim/neovim nvim 

The equivalent in Windows (define an environment variable and point it to the
named pipe) is:

    set NVIM_LISTEN_ADDRESS=\\.\pipe\neovim

and then

    nvim.exe

# What do you want to do with this?

This project aims to:

* Bring real vim bindings to Atom.
* Give the abstract-ui Neovim functionality a work out and find issues using
the msgpack api.
* Eventually build an editor that I would find useful. At the current state it
is pre-alpha.

# See it in action

***A video that shows the current (June/2015) status:***

http://youtu.be/FTInd3H7Zec

A video that shows the integration in action in March/2015:

https://www.youtube.com/watch?v=7TVBcdONEJo

An older video from January of the integration in action, using the abstract-ui
branch:

https://www.youtube.com/watch?v=yluIxQRjUCk

and this is an old video from 2014 using the old redraw-events branch (from mid
2014):

http://www.youtube.com/watch?v=lH_zb7X6mZw

# Things TO DO

* Handle files of more than 9999 lines.
* Handle (or handle better) Atom initiated cursor position changes.
* Make one of the following UI connections/integrations: visual selection,
highlight search, auto completion, etc.
* Better handle editing of new files
* Make the geometry of the Atom buffer fully match the geometry of the Neovim
buffer.

# Contributing

1. Find something that doesn't work (this step shouldn't be that hard, plenty
of things don't work yet)
2. Either (a) fix it and send me a pull request or (b) file a bug report so I know it
needs to be fixed.

# Configuring Atom

To make sure that hjkl get repeated like (Vim and Neovim) on Mac you will need to
run (from the command line):

    defaults write com.github.atom ApplePressAndHoldEnabled -bool false

