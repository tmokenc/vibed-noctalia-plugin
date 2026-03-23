# Anime Corner

A standalone Noctalia plugin for browsing anime art, wallpapers, and booru image boards.

## Included

- yande.re
- Konachan
- Danbooru
- tag suggestions, recent tags, and local tag cache
- save image
- set wallpaper
- attached preview panel
- persisted browsing state

## Install

Copy the `anime-corner` folder into `~/.config/noctalia/plugins/`.

## IPC

```bash
qs -c noctalia-shell ipc call plugin:anime-corner toggle
qs -c noctalia-shell ipc call plugin:anime-corner open
qs -c noctalia-shell ipc call plugin:anime-corner close
```
