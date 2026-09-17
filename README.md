<img src="resources/winmux-logo.svg" width="80" alt="WinNotch logo">

# WinNotch

A macOS window manager with workspace controls designed for the camera-notch area.

## Working with windows

- **Tab bar:** the horizontal bar at the top left switches tabs. Each tab holds a window or a composed window layout.
- **Workspace switcher:** a temporary workspace-only HUD centered like macOS Command–Tab.
- **Window stack:** a group of windows stacked together within a tab.
- **Stack tabs:** the controls for switching windows within a window stack.

The workspace switcher appears temporarily during keyboard switching and does not reserve window-layout space. The independent [My Menu Bar](https://github.com/qianningxu/my-menu-bar) app owns the configurable top widget strip.

Projects and folders organize tabs without combining their window layouts. Use the WinNotch menu-bar icon to switch or configure projects. Each display has its own workspace bar; a workspace can be visible on only one display at a time.

## Configuration and shortcuts

WinNotch keeps reading `~/.config/winmux/winmux.toml` so existing settings and Accessibility permission remain compatible.

On first launch, an existing WinMux configuration is preserved. If only an AeroSpace configuration exists, WinNotch imports its shortcuts and fills in defaults, leaving the AeroSpace file unchanged.

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

This builds and signs the candidate, preserves the existing Accessibility identity, replaces the legacy `/Applications/WinMux.app` with `/Applications/WinNotch.app`, verifies its signature, and reopens it.

When full Xcode is unavailable, the release workflow builds with Swift Package Manager and reuses the installed app's bundle resources. XCTest still requires full Xcode.

## Credits

[WinMux](https://github.com/ZimengXiong/winmux) and [AeroSpace](https://github.com/nikitabobko/AeroSpace) for the original window-management foundation.
