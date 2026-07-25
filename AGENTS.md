# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

EasyNode is a Linux server management panel with WebSSH, WebSFTP, RDP, Docker, AI chat, and batch operations. It's a monorepo with three modules:

- **`server/`** — Koa.js backend (Node.js, CommonJS), REST API + Socket.IO WebSockets
- **`web/`** — Vue 3 + Vite SPA frontend
- **`native/`** — Flutter mobile app (Android/iOS/macOS/Linux, HarmonyOS in progress)

## Common Commands

### Development
```bash
yarn dev                          # Run web + server concurrently
yarn workspace server run local   # Server only (nodemon, EXEC_ENV=local)
yarn workspace web run dev        # Web only (Vite, port 18090)
cd native && flutter run          # Native app on connected device
```

### Build
```bash
yarn workspace web run build      # Vite production build
cd native && flutter build apk --release --split-per-abi  # Android APK
```

### Lint
```bash
yarn workspace server run lint    # Server ESLint
yarn workspace web run lint       # Web ESLint
cd native && flutter analyze      # Dart static analysis
```

### Test
```bash
yarn workspace server run test       # All server tests
yarn workspace server run test:api   # REST API auth tests only
yarn workspace server run test:ws    # WebSocket tests only
cd native && flutter test            # Flutter unit tests
```

## Architecture

### Server
- **Koa 2** with middleware chain: IP filter → compression → history fallback → static files → response handler → body parser → access logging → auth → router
- **API prefix**: `/api/v1`, HTTP port 8082 (configurable via `HTTP_PORT`)
- **Database**: NeDB (embedded document DB), files in `server/app/db/`. Each domain has its own `.db` file. DB classes use singleton pattern via `server/app/utils/db-class.js`
- **WebSocket namespaces** (Socket.IO): `/terminal`, `/sftp-v2`, `/docker`, `/onekey`, `/server-status`, `/file-transfer` — all require auth via `verifyWsAuthSync`
- **Auth flow**: RSA-2048 keypair generated on first boot → client encrypts password with public key → server decrypts → JWT issued (AES-encrypted before sending) → session cookie stored in `session.db`
- **Global `logger`** object (log4js) available everywhere — no need to import

### Web
- **Vue 3** Composition API + **Pinia** store + **Vue Router 4** (history mode)
- **Element Plus** components auto-imported via `unplugin-vue-components`
- **Path aliases**: `@` → `src/`, `@views`, `@utils`, `@store`
- **Vite proxy**: `/api/v1` and `/sftp-cache` → `http://localhost:8082`
- Terminal: xterm.js (`@xterm/xterm`), RDP: `guacamole-common-js`, AI: `ant-design-x-vue`

### Native
- **Flutter** (SDK ^3.11.0) with **Riverpod** state management
- **Direct SSH**: connects to servers via `dartssh2` natively — does NOT go through the server's WebSocket. Fetches AES-GCM encrypted credentials from `POST /api/v1/native/ssh-connection`, decrypts locally
- **Feature-based layout**: `lib/features/` (`auth/`, `servers/`, `terminal/`, `shell/`, `docker/`, `scripts/`, `settings/`), state in `lib/state/`
- **Storage**: `AppStorage` (SharedPreferences) for preferences, `SecureAppStorage` (flutter_secure_storage) for tokens/passwords
- **i18n**: `lib/l10n/strings_en.dart` and `strings_zh.dart` with `AppLocalizations` — dotted key notation (`'sftp.newFile'`)
- **Theme**: Material 3, `AppColorTheme` extension accessed via `context.colors`

## Code Conventions

### Server & Web (JavaScript)
- CommonJS in server, ES modules in web — no TypeScript
- Single quotes, no semicolons, 2-space indent (`eslint.config.cjs` in each)
- Equality: `eqeqeq` enforced

### Native (Dart)
- `flutter_lints` analysis rules
- snake_case filenames, PascalCase classes
- Riverpod providers in `lib/state/`, features in `lib/features/`

## Key Patterns

- **Web ↔ Server**: Axios for REST (token in header, `withCredentials` for cookies), Socket.IO for real-time ops (terminal I/O, SFTP, Docker)
- **Native ↔ Server**: Dio + cookie manager for REST API calls; SSH/SFTP operations happen directly on-device via `dartssh2`
- **Encryption interop**: Server uses `node-rsa` + `crypto-js`; native uses `pointycastle` + `basic_utils` — must stay compatible (RSA PKCS1, AES-GCM)
- **DB singleton**: All NeDB collections accessed via class instances from `db-class.js` — never instantiate DB directly
