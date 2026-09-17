# Project and workspace appearance

The approved prototype lives in `../temp/winmux`. The native implementation uses the same Geist token roles, without glass.

| Name | Meaning | Appearance |
| --- | --- | --- |
| Widget bar | Status widgets in the native menu area | WinDock clear glass with backdrop blur and a 20% white tint, without an added outline; safe around the camera notch |
| Project frame | Former full-screen surface beneath the Widget bar | Removed; the desktop remains visible through window gaps |
| Workspace tabs bar | Bottom bar containing the Project menu and workspace tabs | Centered content-sized WinDock clear-glass surface with backdrop blur and a 20% white tint, without an outline, floating 12 points above the usable screen edge; text-only workspace tabs with a text-width underline for selection |
| Workspace frame | Window layout area | No enclosing fill; each window and window tab bar owns its surface |
| Window tab bar | Compact untinted WinDock clear-glass track with backdrop blur at 2.5% emphasis for unfocused groups; the focused group uses the full-strength regular recipe with a 28% white tint. Within an unfocused group, inactive labels use 40% emphasis while the active tab uses 65% foreground and a 25% selected fill. Hover restores full text with a 25% overlay, and the focused active tab uses a 70% fill. |
| Stacked window | Windows sharing one workspace tab bar | Existing grouping behavior |
| Workspace window | Native app window and title bar | Native controls, borders, and corner geometry retained |

Workspace tabs size to their text with a 200pt cap, centered labels, and dividers only between workspaces. The Project icon and label remain; there is no divider after Project. Active workspace text is semibold with a one-pixel underline directly beneath the text. Inactive workspace text is regular gray-900-light. The floating workspace bar uses a 48pt content height, 16pt outer horizontal padding, a 24pt continuous radius, and 8pt spacing from the bottom work-area edge. Window tab bars retain their original compact 32pt tab surface inside a 34pt glass track. Their tabs retain equal widths, centered content, and existing typography. Window gaps expose the desktop instead of a project-frame fill.

The Project menu's Config submenu has a global **Auto hide** setting. It defaults off, leaving the workspace tabs bar sticky at the bottom of each display's work area. When enabled, the bar releases its reserved layout space, reveals from the bottom edge as an overlay on that display, and remains visible while its menus, editors, or drag targets are in use. Switching workspaces or moving a window to another workspace briefly reveals the destination display's bar, including the default Option+number and Option+Shift+number shortcuts.

The Project menu opens above the floating bar with a small gap, so it never covers the bar itself.

The names describe UI surfaces. Internal workspace/project identifiers, configuration keys, CLI commands, and stored user state keep their existing meanings for compatibility. Native window corners remain owned by their applications; the HTML mockup's simulated 20-point corners do not forcibly reshape third-party windows.

## Native frame corrections

WinDock-controlled tabs use continuous radii. The Window tab bar uses a 21-point outer radius around its inset. All bars use the shared WinDock glass compositor rather than SwiftUI's native `glassEffect`: an AppKit backdrop blur plus explicit WinDock-owned blur opacity, white tint, stroke, shadow, and focus opacity. Clear uses full blur with a 20% white tint and no shadow; regular uses full blur with a 28% white tint and a restrained shadow. Reduce Transparency falls back to the solid background surface. Navigation follows the selected light, dark, or system theme.

Each stacked window has a translucent rounded workspace tab surface aligned with the native window below. Adjacent groups share one six-point gap. Native window borders remain visible.

Workspace tabs use 16-point text, window tabs use 14-point text, and widget text remains 12 points.
