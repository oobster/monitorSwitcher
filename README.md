# Monitor Switcher

Share one monitor between a desktop Mac and your laptops – and let it follow whoever plugs in.

Monitor Switcher is a small macOS menu bar app. The Mac the monitor is connected to (the
**server**) switches the monitor's input over DDC/CI using [`m1ddc`](https://github.com/waydabber/m1ddc).
**Laptops** connected to another input of the same monitor ask the server to switch over SSH on
your local network.

- **Plug in a laptop** → the monitor switches to it.
- **Unplug it or put it to sleep** → the monitor goes back to the server.
- On the server: menu bar icon or **⌃⌥⌘M** to switch by hand.
- The server's other displays are **protected** and never switched.

Version: see [`VERSION`](VERSION) · changes: [`CHANGELOG.md`](CHANGELOG.md) · license: [Unlicense](LICENSE) (public domain)

## Requirements

- **Server:** Apple Silicon Mac, macOS 13+, [Homebrew](https://brew.sh) and `m1ddc`
  (`brew install m1ddc`), Remote Login (SSH) turned on.
  The built-in HDMI port of M1 and entry-level M2 Macs does not support DDC – use USB-C/Thunderbolt.
- **Monitor:** DDC/CI support (most desktop monitors), with the server and the laptops on different inputs.
- **Laptops:** any Mac with macOS 13+ (Apple Silicon or Intel), on the same local network as the server.

## How it works

```
  Server Mac ──── cable ────▶ input A ┐
                                       ├── shared monitor
  Laptop     ──── cable ────▶ input B ┘

  Laptop ── SSH (local network) ──▶ Server Mac ── DDC ──▶ monitor switches input
```

- The laptop app watches its displays. When the shared monitor appears (cable plugged in, or the
  laptop wakes with it attached) it sends `client`; when the monitor disappears for 5 s or the laptop
  goes to sleep it sends `release`.
- Laptop keys are restricted on the server (`restrict` + forced command `monitor-switch-ssh`):
  they can only switch the monitor, query the version and download the client package – no shell.
- The shared monitor is addressed only by its saved UUID, and protected displays are refused before
  every command, so a command can never reach the wrong display.
- A monitor without a signal often goes into power save and ignores the first DDC command; the server
  waits for it, verifies the input and retries (at most every 6 s, so the screen doesn't blink).

## Install

```
repository:  ./release.sh            →  dist/MonitorSwitcher-server-<version>.zip
server:      zsh setup.command       →  installs the server + dist/MonitorSwitcher-client-<version>.zip
laptop:      zsh install.command     (copy the client zip over, e.g. with AirDrop)
```

Ready-made server packages are attached to the [GitHub releases](../../releases).

### 1. Server

1. `brew install m1ddc`, and turn on System Settings → General → Sharing → **Remote Login**.
2. Unzip the server package. Make sure the shared monitor is showing the server.
3. In Terminal: `zsh setup.command`

Setup:

1. lists every display it finds, with its current input, and marks the one with the menu bar;
2. asks which display is the **main** one (stays with the server) and which one **may be switched**
   (shared); all others are **protected**; shows a summary and asks for confirmation;
3. reads the server's input from the shared monitor, asks for the laptops' input and the menu names;
4. writes this Mac's own SSH address (`user@computer-name.local`) – a new server writes its own;
5. saves `~/.config/monitor-switch/config`, installs the app and builds a **separate client package**
   `dist/MonitorSwitcher-client-<version>.zip` with the same settings, and publishes it for updates.

Press Enter to accept a suggestion in `[brackets]`; `zsh setup.command --yes` accepts all of them.
Run setup again whenever the monitor, a cable, an input or the server changes.

### 2. Laptops

Copy the client package to the laptop, unzip it and run `zsh install.command`
(end-user instructions are inside: `INSTRUCTIONS.txt`).

On first install the laptop prints its public key and copies it to the clipboard. On the server:
**menu bar icon → Laptop Keys … → paste → Add**. The same window lists all laptops (with *Remove*)
and shows whether Remote Login is on. Without the app: `./authorize-key.sh "ssh-ed25519 AAAA… name"`.

Keys stay valid when you run setup again.

## Use

**Server**
- Menu bar icon → pick a computer (a checkmark shows the current one).
- **⌃⌥⌘M** (global) switches to the other computer.
- Terminal: `~/.local/bin/monitor-switch toggle|server|client|status`

**Laptop** – usually nothing to do:
- It takes over when the shared monitor appears and gives it back when unplugged or asleep
  (the server answers at once and switches in the background, so sleep is delayed by ~1 s;
  at most 8 s if the server is unreachable).
- It only gives the monitor back if the monitor is attached to **this** laptop.
- It only works on the server's local network (`.local` is a Bonjour name); elsewhere nothing happens.
- If the laptop dies or is offline it cannot give the monitor back – press ⌃⌥⌘M on the server.
- Menu: switch by hand, turn the automatic take-over/give-back off, **Update from Server**.

Both start at login (can be turned off in the menu); the version is shown at the bottom of the menu.

## Updates

1. Build a new server package (`./release.sh`) and run `zsh setup.command --yes` from it on the server.
   It installs the server and publishes the new client package.
2. On each laptop: menu → **Update from Server** (on the server's network). Nothing runs on its own,
   so a laptop away from home never waits for the server.

Changes to `monitor-switch` alone take effect for everyone as soon as the server is updated.

## Build from source

```sh
xcode-select --install     # Swift compiler
./release.sh               # → dist/MonitorSwitcher-server-<version>.zip
```

In the repository you can also run `zsh setup.command` directly; without a bundled app it builds one.
The app is ad-hoc signed, not notarized; the installers remove the quarantine flag from the app they install.

### Release checklist

1. Bump `VERSION` (`x.y.Z` fix, `x.Y.0` feature, `X.0.0` breaking) and add to `CHANGELOG.md`.
2. `git commit`, `git tag v<version>`, `git push --follow-tags`.
3. `./release.sh` and attach `dist/MonitorSwitcher-server-<version>.zip` to a GitHub release.

## Files

| File | Runs on | Purpose |
|---|---|---|
| `setup.command` | server | settings, server install, client package |
| `install.command` | server | installs the app and scripts (called by setup) |
| `build-client.sh` | server | builds the client package (called by setup) |
| `monitor-switch` | server | switches over DDC; safety checks and retries |
| `monitor-switch-ssh` | server | forced command for laptop keys |
| `authorize-key.sh` | server | adds a laptop key without the app |
| `client/*` | laptop | SSH wrapper, updater, installer, instructions |
| `server/INSTRUCTIONS.txt` | server | short instructions inside the server package |
| `MonitorSwitcher.swift` | both | the menu bar app (its role is set by the installer) |
| `build-app.sh`, `release.sh` | repository | builds the app and the server package |

Logs: `~/.local/state/monitor-switch/log` (last 24 hours).

## Security notes

- Keep SSH on your local network – don't port-forward it.
- Laptop keys can only run the commands listed above; adding a key never touches other lines in
  `authorized_keys`.
- "Update from Server" installs the package the server offers; the laptop pins the server's SSH host
  key on first contact and verifies the package version and the app signature before installing.

## License and disclaimer

Released into the public domain under the [Unlicense](LICENSE): use, copy, modify and share it
for any purpose, no attribution needed.

The software is provided **"as is", without warranty of any kind**. It changes monitor inputs over
DDC and edits `~/.ssh/authorized_keys` on the server – you use it **at your own risk**, and the
authors are not liable for any damage or other consequences.
