# Project and workspace appearance

The approved prototype lives in `../temp/winmux`. The native implementation uses the same Geist token roles, without glass.

| Name | Meaning | Appearance |
| --- | --- | --- |
| Widget bar | Status widgets in the native menu area | Dark secondary background; safe around the camera notch |
| Project frame | Former full-screen surface beneath the Widget bar | Removed; the desktop remains visible through window gaps |
| Project tabs bar | Bottom bar containing the Project menu and workspace tabs | Centered content-sized color-3 surface with a color-5 stroke; text-only workspace tabs with a text-width underline for selection |
| Workspace frame | Window layout area | No enclosing fill; each window and window tab bar owns its surface |
| Workspace tab bar / window bar | Second row switching apply, Inspiration, etc. | gray-500-light track, white active tab, equal-width tabs with centered content |
| Stacked window | Windows sharing one workspace tab bar | Existing grouping behavior |
| Workspace window | Native app window and title bar | Native controls, borders, and corner geometry retained |

Project tabs size to their text with a 200pt cap, centered labels, and dividers only between workspaces. The Project icon and label remain; there is no divider after Project. Active workspace text is semibold with a one-pixel underline directly beneath the text. Inactive workspace text is regular gray-900-light. Window tabs divide their available bar width evenly, with centered icons and text; active text is semibold and inactive text medium. Both rows preserve 38pt bar height, 32pt tabs, 6pt outer spacing, and 3pt inner spacing. Tab content retains 12pt horizontal padding. Window gaps expose the desktop instead of a project-frame fill.

The Project menu's Config submenu has a global **Auto hide** setting. It defaults off, leaving the project tabs bar sticky at the bottom of each display's work area. When enabled, the bar releases its reserved layout space, reveals from the bottom edge as an overlay on that display, and remains visible while its menus, editors, or drag targets are in use.

The names describe UI surfaces. Internal workspace/project identifiers, configuration keys, CLI commands, and stored user state keep their existing meanings for compatibility. Native window corners remain owned by their applications; the HTML mockup's simulated 20-point corners do not forcibly reshape third-party windows.

## Native frame corrections

WinMux-controlled tabs use a 16-point continuous radius. The Workspace tab bar uses a 19-point outer radius around its three-point inset. The Project tabs bar uses the selected project's color family for its fill and stroke. Navigation follows the selected light, dark, or system theme.

Each stacked window has a gray-500 rounded workspace tab surface aligned with the native window below. Adjacent groups share one six-point gap. Native window borders remain visible.

Project and workspace tab titles use 14-point text. Widget text remains 12 points.
