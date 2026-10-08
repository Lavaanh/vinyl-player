# Vinyl Player

A KDE Plasma 6 desktop widget with a spinning vinyl, your Spotify album art, a blurred cover background and playback controls. Show and hide it with a keybind.

## About this project

This is just a fun personal project, shared as part of my learning journey rather than as a polished product.

I'm still learning Linux and coding. I built this with a lot of help from AI (Claude): I came up with the idea, tested everything on my own machine, and kept tweaking it until it looked and felt right, but the AI wrote most of the code. I'm posting it to document the experience and in case someone else finds it useful.

It works on my setup (Kubuntu, Plasma 6, Spotify), but I can't promise it will work on yours. Feel free to use it, change it, or learn from it.

## Requirements

- KDE Plasma 6
- playerctl (`sudo apt install playerctl`)
- Spotify (other MPRIS players may work if you change `-p spotify` in `main.qml`)

## Install

    git clone https://github.com/Lavaanh/vinyl-player.git
    cd vinyl-player
    ./install.sh

Then log out and back in once, right-click the desktop, choose Add or Manage Widgets, and add Vinyl Player.

## Show/hide keybind

The widget starts hidden. In System Settings > Keyboard > Shortcuts > Add New > Command or Script, add `~/.local/bin/vinyl-toggle` (use the full path) and pick a key.

## Customize

Edit the properties at the top of `package/contents/ui/main.qml`: bgOpacity, bgDim, bgBlur, cornerRadius, accent.

## Notes

- The install script sets `QML_XHR_ALLOW_FILE_READ=1` (in `~/.config/plasma-workspace/env/`) so the widget can read its flag file quickly. This is why a re-login is needed.
- Desktop widgets sit below windows, so it only shows when the desktop is visible.
