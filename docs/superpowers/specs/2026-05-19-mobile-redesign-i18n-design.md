# EasyNode Mobile Redesign and I18n Design

Date: 2026-05-19

## Goal

Redesign all existing Flutter mobile screens according to `DESIGN.md`, adapted for a compact operational server-management app rather than a marketing site. Add a lightweight two-language system for English and Simplified Chinese, with language switching available on the login page and settings page.

The first implementation should land the light theme, while keeping the theme/token structure compatible with a later dark-mode pass.

## Confirmed Scope

Included:

- Login page visual redesign.
- Main shell bottom navigation redesign.
- Servers tab redesign.
- Terminal shell page and terminal shortcut toolbar redesign.
- Settings tab redesign.
- SFTP and Scripts placeholder page redesign.
- English and Simplified Chinese app strings.
- Locale selection on Login and Settings.
- Locale persistence in local app storage.
- First-launch locale detection from the system locale.
- Tests for locale behavior and key redesigned UI surfaces.

Excluded:

- New server-side APIs.
- New SFTP, Scripts, or Settings features beyond the existing surfaces.
- Full dark-mode implementation and runtime dark-mode toggle.
- CRUD flows for servers.
- Pixel-perfect recreation of `DESIGN.md` marketing-page hero sections.

## Design Direction

Use the selected "Editorial ops app" direction:

- Pure white app canvas for the primary light theme.
- Near-black ink for primary text.
- Cool gray for secondary text.
- Black primary actions with 8px radius.
- Compact 12px-radius cards with 1px hairline borders.
- Sparse sky-blue atmospheric wash only on the Login intro area.
- JetBrains Mono or platform monospace for terminal, SSH labels, and code-like connection strings.
- Terminal content remains an intentional dark working surface, independent of the app's light shell.
- No saturated purple/indigo seed-color look in user-facing mobile screens.

This adapts `DESIGN.md` into a mobile operations UI: restrained, scannable, dense enough for repeated server work, and visually consistent without feeling like a landing page.

## Theme Architecture

The app should introduce a small theme layer instead of scattering inline colors across pages.

Add a mobile design token module, for example:

```text
mobile/lib/core/ui/
  app_theme.dart
  app_tokens.dart
```

The theme should provide:

- `ThemeData` light theme using Material 3.
- A dark-compatible token extension with semantic values for canvas, card, hairline, strong hairline, muted text, warning surface, success, and terminal surfaces.
- Button, input, card, app bar, navigation bar, chip, dialog, and snack bar defaults that match `DESIGN.md`.
- A future dark token set, even if `ThemeMode.system` remains and the first visual pass focuses on light mode.

Pages should consume `Theme.of(context)`, `ColorScheme`, and token extension values. Avoid hard-coded black/white page backgrounds except for the terminal's fixed dark ANSI workspace and unavoidable text constants inside custom painters.

## Typography

Flutter should use the platform font stack by default unless bundled fonts are added later. Typography should match `DESIGN.md` proportions:

- Page titles: 22-30px, weight 600.
- Component titles: 16-18px, weight 600.
- Body text: 14-16px, weight 400.
- Captions and metadata: 12-13px.
- Connection strings and terminal content: monospace.
- Letter spacing stays at zero in normal controls; only small uppercase labels may use modest positive tracking.

## Page Designs

### Login Page

Remove the standard AppBar and use a full-page layout:

- Top brand intro with `EasyNode`, language switch, headline, and short supporting copy.
- A single subtle sky-blue wash behind the intro area.
- Form area with server address, username, password, MFA code, session duration, and save-password control.
- Black primary login button.
- Inline HTTP warning notice.
- Inline error notice with icon and consistent padding.
- Language switch in the top-right of the intro area.

The login page must remain usable on small screens with the keyboard open. Text fields keep at least 44px height.

### Main Shell

Keep the existing four tabs:

- Servers
- SFTP
- Scripts
- Settings

Update the bottom navigation to use:

- White/surface background.
- Top hairline divider.
- Compact icons and labels.
- Black selected state.
- Muted gray unselected state.

Keep the current `IndexedStack` behavior so tab state is preserved.

### Servers Tab

Keep the current provider and connection behavior. Redesign the UI:

- Top title row with page title and icon actions.
- Search field shown as a compact bordered field.
- Active terminal banner styled as a light operational banner with stack icon, count, enter affordance, and close-all action.
- Grouped server sections with small uppercase group labels.
- Server cards with:
  - server display name;
  - connection string in monospace;
  - status indicator when a host already has a session;
  - auth/group/tag badges;
  - black or bordered action button depending on state.
- Empty, error, and loading states use a shared visual language.

The connection logic should not change.

### Terminal Shell

The terminal page keeps its existing structure and behavior:

- 52px top toolbar.
- dark terminal viewport.
- bottom shortcut toolbar.
- session overlay menus.
- reconnect, close, and new-terminal actions.

Visual changes:

- Top toolbar becomes a light control surface with hairline border.
- Session title and status are compact and scannable.
- Stacked sessions icon should use theme-compatible colors or token constants that have light/dark counterparts.
- The terminal viewport stays dark with monospace text.
- Shortcut bar uses small bordered controls in light mode and token-driven surfaces for dark mode later.
- Shortcut labels should be localized where they are words, but terminal control labels such as `Esc`, `Tab`, `Ctrl`, `PgUp`, and `PgDn` remain conventional.

### Settings Tab

Settings should become the user's place to manage app-level preferences:

- Account/server summary card.
- Language setting row with current language and picker/action sheet.
- Logout row with confirmation dialog.

Settings must use the same shared strings system as Login.

### SFTP and Scripts Placeholder Tabs

Keep these as placeholders but make them consistent:

- AppBar/title matching the shell.
- Empty-state component with icon, title, and description.
- Proper English and Chinese strings.
- Remove current mojibake/garbled copy.

## I18n Architecture

Use a lightweight local implementation rather than adding a large dependency.

Suggested files:

```text
mobile/lib/core/i18n/
  app_locale.dart
  app_strings.dart
  app_localizations.dart
```

Core behavior:

- Support exactly two locales initially:
  - English: `en`
  - Simplified Chinese: `zh_Hans`
- If the user has not selected a language, resolve from the system locale.
- Any Chinese system locale resolves to Simplified Chinese for this phase.
- Other system locales resolve to English.
- Once the user changes language, persist it in `AppStorage`.
- Persisted user choice overrides future system-locale changes.
- Login and Settings both expose language switching.
- Switching language updates visible UI immediately.

Integration shape:

- Add `localeCode` to `AppStorage`.
- Bootstrap reads the saved locale before building `MaterialApp`.
- `_AppRoot` owns the current locale state and passes change callbacks to Login and Main Shell/Settings.
- `MaterialApp.locale` is set to the resolved locale.
- Widgets read copy via a small `context.strings` extension or `AppStrings.of(context)` helper.

Do not localize values that are command syntax or terminal conventions. Do localize labels, hints, validation errors, notices, empty states, dialog titles, and button text.

## State and Data Flow

Startup:

1. Read `SharedPreferences`.
2. Read saved server/user/save-password preferences.
3. Read saved locale code, if any.
4. Resolve effective locale from saved preference or platform locale.
5. Restore auth session as today.
6. Build `MaterialApp` with the effective locale and redesigned theme.

Language switch:

1. User opens switcher from Login or Settings.
2. App updates locale state.
3. App writes locale code to `AppStorage`.
4. `MaterialApp` rebuilds and visible strings update.

Auth and terminal-session behavior remain unchanged.

## Error Handling

- If a saved locale is unknown, fall back to system resolution.
- If writing the locale preference fails, keep the in-memory language for the current session and surface no blocking error; the user can retry later.
- Existing auth expiration behavior remains unchanged.
- Login validation messages become localized.
- HTTP warning and login failure messages become localized when generated by the app. Server-returned messages may stay as returned.

## Testing

Add or update tests for:

- `AppStorage` locale persistence.
- Locale resolution:
  - no saved locale + Chinese system locale -> Chinese;
  - no saved locale + English/other system locale -> English;
  - saved locale overrides system locale.
- Login page renders English and Chinese labels.
- Login language switch updates visible copy.
- Settings language switch updates visible copy.
- SFTP/Scripts placeholders render non-garbled localized copy.
- Servers tab still renders existing cards and connect action.
- Terminal toolbar still emits expected escape sequences after visual changes.

Run at minimum:

```bash
flutter test
```

from the `mobile` directory.

## Migration Notes

- Existing stored users will default from system locale unless they choose a language.
- Existing saved server address, username, password preference, token, session cookie, and device ID storage remain unchanged.
- No server migration is needed.
- No database or API changes are needed.

## Acceptance Criteria

- All current mobile screens visually align with the confirmed Editorial ops app direction.
- Login and Settings can switch between English and Simplified Chinese.
- Language selection persists across app restarts.
- First launch follows system language when no user preference exists.
- Current SSH connection behavior, terminal sessions, and shortcut input behavior continue to work.
- SFTP and Scripts placeholder pages no longer contain garbled text.
- Theme code is structured so a later dark-mode pass can add complete dark colors without rewriting page layouts.
