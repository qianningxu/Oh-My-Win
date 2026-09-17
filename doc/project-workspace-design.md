# Project and workspace appearance

The approved prototype lives in `../temp/winmux`. The native implementation uses the same Geist token roles, without glass.

| Name | Meaning | Appearance |
| --- | --- | --- |
| Widget bar | Status widgets in the native menu area | Native glass following the current light/dark appearance, with a faint project tint and reflective edge; safe around the camera notch |
| Project frame | Former full-screen surface beneath the Widget bar | Removed; the desktop remains visible through window gaps |
| Project tabs bar | Bottom bar containing the Project menu and workspace tabs | Centered content-sized native glass surface with a faint color-3 tint, reflective edge, and color-5 stroke; text-only workspace tabs with a text-width underline for selection |
| Workspace frame | Window layout area | No enclosing fill; each window and window tab bar owns its surface |
| Workspace tab bar / window bar | Row attached above a workspace window | Enlarged native glass track with reflective edging, a translucent active tab, and equal-width tabs with centered content |
| Stacked window | Windows sharing one workspace tab bar | Existing grouping behavior |
| Workspace window | Native app window and title bar | Native controls, borders, and corner geometry retained |

Project tabs size to their text with a 200pt cap, centered labels, and dividers only between workspaces. The Project icon and label remain; there is no divider after Project. Active workspace text is semibold with a one-pixel underline directly beneath the text. Inactive workspace text is regular gray-900-light. The floating project bar uses a 40pt content height, 12pt outer horizontal padding, a 20pt continuous radius, and 6pt spacing from the bottom work-area edge. Workspace tab bars use a 40pt tab surface inside a 42pt glass track. Their tabs retain equal widths, centered content, and existing typography. Window gaps expose the desktop instead of a project-frame fill.

The Project menu's Config submenu has a global **Auto hide** setting. It defaults off, leaving the project tabs bar sticky at the bottom of each display's work area. When enabled, the bar releases its reserved layout space, reveals from the bottom edge as an overlay on that display, and remains visible while its menus, editors, or drag targets are in use.

The names describe UI surfaces. Internal workspace/project identifiers, configuration keys, CLI commands, and stored user state keep their existing meanings for compatibility. Native window corners remain owned by their applications; the HTML mockup's simulated 20-point corners do not forcibly reshape third-party windows.

## Native frame corrections

WinMux-controlled tabs use continuous radii. The Workspace tab bar uses a 21-point outer radius around its inset. The Project tabs bar uses native macOS material, lightly tinted and stroked with the selected project's color family; Reduce Transparency falls back to the solid project surface. Navigation follows the selected light, dark, or system theme.

Each stacked window has a translucent rounded workspace tab surface aligned with the native window below. Adjacent groups share one six-point gap. Native window borders remain visible.

Project and workspace tab titles use 14-point text. Widget text remains 12 points.
