# Changelog

All notable changes to Monitor Switcher. Versions follow [Semantic Versioning](https://semver.org/):
`MAJOR.MINOR.PATCH`. The current version is in the `VERSION` file.

## [3.0.0] – 2026-10-23

First public release.

### Server
- Menu bar app: switch the shared monitor between the server and the laptops, ⌃⌥⌘M (global),
  launch at login.
- `setup.command`: lists all displays with their current input; you choose the main display and the
  one that may be switched, all others are protected; reads the server's input from the monitor,
  saves the settings and this Mac's SSH address, installs the server and builds a client package.
- Safe switching: the shared monitor is addressed only by its saved UUID, protected displays are
  refused before every command, one switch at a time, a 24-hour log.
- Works with monitors in power save: waits for the monitor, verifies the input and retries without
  making the screen blink.
- **Laptop Keys** window: add and remove laptop keys and see whether Remote Login is on. Keys are
  restricted to switching the monitor; other `authorized_keys` lines are never touched.
- Publishes the client package so laptops can update from the server.

### Laptops
- Takes over the monitor when its cable is plugged in (or the laptop wakes with it attached) and
  gives it back when unplugged or asleep; sleep is delayed by ~1 s at most (8 s if the server is away).
- Only gives the monitor back if it is attached to this laptop; does nothing off the server's network.
- **Update from Server** in the menu: downloads the newer package, checks its version and signature,
  installs it and relaunches. Never runs on its own.

### Packaging
- `release.sh` builds a server package with a prebuilt universal app (no developer tools needed on
  the server); `setup.command` builds the separate client package from it.
- Installers migrate earlier private builds (settings, log, laptop keys and menu choices).
