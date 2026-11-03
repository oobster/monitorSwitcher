# Changelog

All notable changes to Monitor Switcher. Versions follow [Semantic Versioning](https://semver.org/):
`MAJOR.MINOR.PATCH`. The current version is in the `VERSION` file.

## [Unreleased]

### Security
- `authorize-key.sh` accepts exactly one public key: text with a line break is refused, the line is
  rebuilt from its fields and must parse as exactly one valid key (`ssh-keygen -l`) before it is added
  with the forced command and `restrict`. Before, a second line could be added without restrictions.
  A key that is already present without restrictions is left unchanged (same as the app).
- `authorize-key.sh`: a single line break at the very end of the argument (`\n` or `\r\n`, e.g. from
  copy and paste) is dropped silently; any other line break (inside the key, a second trailing one or
  several keys) is still refused.

### Fixed
- Laptops: take-over retries are cancelled when the shared monitor is unplugged, on sleep and on
  release, and each retry checks that the monitor is still attached – a late retry can no longer
  switch the monitor back to a laptop that is gone. A release that arrives while a switch is running
  is queued and runs right after it instead of being dropped. Retries are cancelled on a short blip
  of the monitor connection too (by design; this only matters if an attempt fails during the blip –
  then switch from the menu or plug the cable in again).

### Added
- `scripts/test.sh`: `authorize-key.sh` with throwaway keys in a temporary HOME (including one
  trailing `\n` / `\r\n` accepted, two trailing line breaks or one inside the key refused), and a simulation of
  the take-over / release order on a virtual clock (`scripts/takeover-sim.swift`).

## [3.2.0] – 2026-11-01

### Changed
- Release builds are signed with a Developer ID (hardened runtime) and notarized, so the app opens on
  any Mac without Gatekeeper warnings. Builds without that identity are still signed ad-hoc.
- Bundle ID is now `se.premakni.MonitorSwitcher`. The installers move existing settings over
  automatically; the launch-at-login item is registered again under the new ID.
- Developer scripts moved to `scripts/`: `build.sh` (needs a clean tree, tags the version, keeps the
  last two packages), `build-app.sh` (build, sign, notarize), `deploy.sh` (install on this Mac).

### Added
- `scripts/test.sh`: quick tests without a monitor – script syntax, Swift type check and the switching
  logic against a fake `m1ddc` (switching, power save, protected displays, alternate addressing,
  monitors without read-back).

## [3.1.0] – 2026-10-23

### Added
- **Detect the laptops' input** in `setup.command`: switch the monitor to a laptop with its buttons,
  setup reads the input and switches back over DDC as a test – no need to know input codes.
- **Alternate addressing** (`input-alt`, e.g. LG monitors): chosen automatically when the standard
  switch does not work in that test; `--input-alt` forces it.
- Names for all standard DDC inputs (VGA, DVI, Composite, S-Video, Component, DisplayPort, HDMI, USB-C)
  and for the alternate codes.
- Monitors that can't report their current input are supported (switching without read-back).

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
