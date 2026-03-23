# Kanshi Manager for Noctalia

A Noctalia plugin for Niri users who want a compact display-management panel.

## What changed in this revision

- fixed the color-token warning in `Panel.qml`
- made the panel denser and moved create/edit into a modal editor so it only appears when needed
- added a graphical monitor layout view based on Niri logical coordinates
- changed the bar title to the active profile name when it can be inferred
- added startup `kanshictl reload` support so you do not need to hit Reload manually after every shell start
- added a configurable bar refresh interval for title updates

## What it does

- lists kanshi profiles found in your config
- lets you create, edit, save, and delete named profiles
- lets you switch named profiles with `kanshictl switch <name>`
- shows the current Niri output state from `niri msg --json outputs`
- provides per-output on/off buttons via `niri msg output <name> on|off`
- generates a profile body from the current output layout so you can save it quickly

## Notes

- manual monitor on/off is **transient** because it uses `niri msg output`; it is not written to your kanshi config
- switching profiles requires **named** profiles; unnamed `profile { ... }` blocks can still be edited, but not switched manually
- the plugin expects these commands to be available: `python3`, `niri`, `kanshictl`
- if your commands or config path are different, open the plugin settings in Noctalia and override them there
- active profile detection is best-effort: it first looks at `kanshictl status`, then falls back to matching the current output layout or the last switched profile

## Install

1. Copy this directory to:
   `~/.config/noctalia/plugins/noctalia-kanshi-manager`
2. Register it in:
   `~/.config/noctalia/plugins.json`

Example:

```json
{
  "kanshi-manager": {
    "enabled": true,
    "sourceUrl": "local"
  }
}
```

3. Restart Noctalia.
4. Enable the plugin in Noctalia settings if needed.
5. Add the bar widget, or use the control-center button.

## Files

- `manifest.json` – plugin manifest
- `BarWidget.qml` – bar entry point
- `ControlCenterWidget.qml` – control-center shortcut button
- `Panel.qml` – main UI
- `Settings.qml` – plugin settings
- `helpers/kanshi_manager.py` – helper script for config editing and command execution

## Caveats

This still edits the **inside** of profile blocks as raw text instead of building a fully structured kanshi editor. That keeps it flexible for advanced directives such as `exec`, custom criteria, and special output options.
