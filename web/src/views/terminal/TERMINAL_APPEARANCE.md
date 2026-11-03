# Terminal appearance architecture

EasyNode treats terminal appearance as four independent layers:

1. A terminal theme resolves the xterm foreground, background, cursor, selection, and ANSI palette.
2. An optional built-in/custom HTML theme or authenticated local image renders once beneath all terminal panes.
3. A workspace overlay controls decorative-background readability without changing terminal colors.
4. Content highlighting adds semantic styles to matched text after the theme has resolved ANSI colors.

Terminals use xterm.js 6 with matching fit, search, and web-links addons. Desktop-width terminals load the WebGL addon after opening; initialization failure or an unrecovered context loss disposes the addon and falls back to the built-in DOM renderer without reconnecting SSH. Mobile-width terminals and the highlighting preview use DOM rendering. Theme backgrounds are managed through xterm's theme API, including its scrollable element; the legacy viewport remains transparent.

Built-in themes come from EasyNode's existing `xterm-theme` dependency and remain immutable. Custom themes use EasyNode's own V2 data model and default palette, and support only create, edit, rename, and delete operations.

Appearance editing uses a transient Pinia draft. The draft is consumed by active terminal instances immediately, but is never sent to the server until the user saves. Cancelling or unmounting the settings workbench removes the draft and restores persisted appearance.

Built-in HTML themes are code-owned documents. Users can also create, edit, and delete local HTML/CSS themes. Every HTML theme runs without scripts in an iframe sandbox with a CSP that blocks network and other external resources; validation also rejects scripts, nested pages, forms, imports, and remote URLs.

Image backgrounds accept PNG, JPEG, and WebP files up to 5 MB. Selection creates a local Object URL for immediate draft rendering; the file is uploaded only when appearance is saved. Asset reads require the normal API authentication, and replaced or disabled assets are removed after a successful settings save. Remote images and gradient presets are not supported.

Selecting a terminal theme explicitly returns the workspace background mode to the theme color, so the selected state and the visible terminal background cannot disagree.

Content highlighting uses the versioned `builtin:standard` preset. Built-in rules remain code-owned and only user changes are persisted as overrides; custom rules are stored separately. Default styles reference ANSI theme slots, while explicit fixed colors remain available for intentional overrides. Match scopes distinguish the exact match, the complete logical line, and the tail from a match to the line ending.

The highlighter preserves the original WebSocket-to-xterm write order, matches against text with ANSI control sequences removed, and then renders styles back into the untouched control stream. It tracks SGR state across writes and restores the remote foreground, background, and text attributes after each semantic highlight instead of leaving a bare reset. Only an incomplete ANSI sequence at a chunk boundary is held until the following write; ordinary text and prompts are never delayed. Pattern input is limited to 4096 characters and legacy rules are validated without truncation during migration.

The background component, built-in HTML documents, settings workflow, configuration schema, palette, and CSS in this implementation were written for EasyNode. No source code, generated presets, assets, CSS, UI text, or configuration formats from Nexus Terminal are included.
