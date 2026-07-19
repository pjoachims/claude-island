# Claude Island

Dynamic-island-style notch app for macOS: hover the notch (or hit the hotkey)
and it expands into an embedded `claude agents` terminal (FleetView) to manage
all your Claude Code sessions.

- Collapsed: black pill under the notch.
- Hover or hotkey (default ⌃⌥ Space): expands into the terminal.
- Right-click: auto-focus toggle, launch directory for new sessions,
  hotkey preset, quit.

## Install

Download `ClaudeIsland-vX.Y.Z.zip` from
[Releases](https://github.com/pjoachims/claude-island/releases), unzip, and move
`Claude Island.app` to `/Applications`. The app is ad-hoc signed, so on first
launch macOS will complain; clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine "/Applications/Claude Island.app"
```

### Build from source

Requires Xcode 15+ / Swift 5.9 (macOS 14+).

```sh
./build.sh          # -> Claude Island.app (also syncs /Applications copy)
open "Claude Island.app"
```

Launch at login: System Settings → General → Login Items → add Claude Island.app.

## Uninstall

Quit the app, delete Claude Island.app. If you installed a pre-0.3 version:
remove the `claude-island` hook entries from `~/.claude/settings.json` and
`rm -rf ~/.claude/island`.
