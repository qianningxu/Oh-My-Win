<img src="resources/winmux-logo.svg" width="80" alt="WinMux logo">

# WinMux

A macOS window manager, forked from [ZimengXiong/winmux](https://github.com/ZimengXiong/winmux).

## Working with windows

- **Tab bar:** the horizontal bar at the top left switches tabs. Each tab holds a window or a composed window layout.
- **Widget bar:** the bar at the top right displays configured widgets.
- **Window stack:** a group of windows stacked together within a tab.
- **Stack tabs:** the controls for switching windows within a window stack.

The widget bar sits within the system menu-bar area; the workspace tabs bar floats at the bottom of the work area and does not expand into a vertical sidebar.

Projects and folders organize tabs without combining their window layouts. Use the project menu to switch projects, drag tabs to reorder them, or enable **Config → Auto hide** for a bottom-edge-revealed bar. Each display has its own tab bar; a tab can be visible on only one display at a time.

## Configuration and shortcuts

WinMux reads `~/.config/winmux/winmux.toml`. Settings provides shortcut editing and access to the configuration file. Reload configuration after editing it externally.

On first launch, an existing WinMux configuration is preserved. If only an AeroSpace configuration exists, WinMux imports its shortcuts and fills in WinMux defaults, leaving the AeroSpace file unchanged. Otherwise it creates a configuration from the bundled defaults.

Older configuration section names and workspace command aliases remain supported. Internal names such as `WorkspaceSidebar` and configuration keys such as `[tab-sidebar]` are compatibility identifiers; the visible UI calls this the tab bar.

## Development

The package requires Swift 6.2 or newer. Full Xcode is needed for XCTest-based tests and the Xcode archive workflow.

```sh
swift build --product WinMuxApp
swift test
```

`make build` also generates version metadata and builds the test target. Do not launch a second window-manager instance alongside the installed app.

## Installing a local build

Use the repository's persistent signing identity, configured with the local Git settings `winmux.codesignIdentity`, `winmux.codesignAuthority`, and `winmux.developmentTeam`.

```sh
make install
```

This builds and signs the candidate, checks that the existing Accessibility grant will survive, waits for the old process to quit, replaces `/Applications/WinMux.app`, verifies its signature, and reopens it. Installation does not publish a GitHub release. If the Accessibility compatibility check fails, fix signing before replacing the app; do not reset permissions or use ad-hoc signing.

When full Xcode is unavailable, the release workflow builds with Swift Package Manager and reuses the installed app's bundle resources. XCTest still requires full Xcode.

## Credits

[WinMux](https://github.com/ZimengXiong/winmux) and [AeroSpace](https://github.com/nikitabobko/AeroSpace).
