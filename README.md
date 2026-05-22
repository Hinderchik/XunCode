# XunCode for Android

[![Build APK](https://github.com/Hinderchik/XunCode/actions/workflows/build.yml/badge.svg)](https://github.com/Hinderchik/XunCode/actions/workflows/build.yml)

A native Android code editor built with Flutter — Monaco Editor, GitHub-based plugin system, plugin marketplace with reviews, and Tor proxy support. Designed to look and feel like VS Code.

> **Heads up:** XunCode is the successor to VScode Mobile. The applicationId moved from `com.hinderchik.codemobile` to `com.xunkal1.xuncode`, so it installs side-by-side with the old build.

**Marketplace:** [vscodemobile-market.vercel.app](https://vscodemobile-market.vercel.app)

---

## Features

| Feature | Description |
|---|---|
| Monaco Editor | Same engine as VS Code — syntax highlighting for 25+ languages |
| IntelliSense | Project-wide code completion, hints, and navigation |
| Multi-language UI | Russian / English out of the box, drop your own `.txt` into `Shared/XunCode/Languages/` to add a new language |
| Go to Definition | Jump to symbols and references inside code |
| Familiar UI | Activity bar, sidebar, tabs, status bar |
| File Tools | Project tree, search across files, Git, FTP/SFTP support |
| Plugin System | GitHub-based, sandboxed JS runtime with editor / fs / ui / http / hooks API |
| Plugin Marketplace | Browse, install, rate and review community plugins |
| Embedded Terminal | proot + Alpine, auto-fetched at first run, falls back to system shell |
| Proxy Stack | HTTP/HTTPS, SOCKS5, Tor via Orbot, system proxy, fallback chain |
| Run Code | Python, JS/Node.js, PHP, HTML/CSS live preview, Java, C/C++ |
| Developer Mode | Test plugins locally without publishing |
| Mobile UX | Physical keyboard support and popup Ctrl/Alt/Shift keyboard |
| Offline First | Works offline for everything except plugin install and Git push |
| Settings | Theme, font, tab size, word wrap, auto save, plugin docs |

---

## Download

- **Latest debug APK** — [GitHub Actions artifacts](https://github.com/Hinderchik/XunCode/actions)
- **Release APK** — [GitHub Releases](https://github.com/Hinderchik/XunCode/releases)

Requires Android 8.0+ (API 26).

---

## Building from Source

### Prerequisites

- Flutter 3.24.5+
- Node.js 20+
- Android SDK API 35, NDK 25.1.8937393

### Steps

```sh
# Clone
git clone https://github.com/Hinderchik/XunCode.git
cd XunCode

# Bundle Monaco Editor assets
npm install
npm run build:monaco

# Fetch the proot static binaries (terminal sandbox)
bash scripts/fetch-proot.sh

# Flutter deps
flutter pub get

# Generate launcher icons (uses icon.png)
flutter pub run flutter_launcher_icons

# Debug APK
flutter build apk --debug
# → build/app/outputs/flutter-apk/app-debug.apk
```

### Release APK

Add these secrets to your GitHub repo: `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`, then push a tag:

```sh
git tag v1.0.0
git push --tags
```

GitHub Actions builds and publishes the release APK automatically.

---

## Storage layout

XunCode creates these folders on first launch:

```
/storage/emulated/0/Android/data/com.xunkal1.xuncode/files/
├── plugins/   cache/   rootfs/   proot/
├── prefs/     database/  logs/    tmp/

/storage/emulated/0/Shared/XunCode/
├── Projects/   Downloads/   Backups/   Exports/
└── Languages/   ← drop .txt files here to add UI translations
```

The shared folder is created via Storage Manager (`MANAGE_EXTERNAL_STORAGE`). If the user denies that permission, XunCode falls back to the app-private external dir under `Android/data/.../Shared/XunCode/` — the data is still accessible, but it disappears on uninstall.

---

## Localization

UI strings live in plain `.txt` files (`key=value`, `#` comments). On first launch the bundled `ru.txt` and `en.txt` are extracted into `Shared/XunCode/Languages/`. Add another language by dropping a new file into that folder, e.g. `de.txt`:

```
_meta.name=Deutsch
common.ok=OK
common.cancel=Abbrechen
…
```

Then open **Settings → Language → Refresh** to pick it up.

---

## Plugin System

Plugins are public GitHub repositories with two files in the root: `plugin.json` (manifest) and `main.js` (code). Each plugin runs in its own sandboxed `InAppWebView` and gets a `vscode` API surface.

> The same surface is exposed as `xuncode` for forward compatibility — `window.vscode === window.xuncode` inside the sandbox, so existing plugins keep working untouched.

### Minimal plugin

```js
exports.activate = (vscode) => {
  vscode.commands.registerCommand('hello.say', () => {
    vscode.ui.showMessage('Hello from plugin!');
  });
};
```

### Plugin API surface

| Namespace | Methods |
|---|---|
| `vscode.editor` | `getText`, `setText`, `getSelection`, `setSelection`, `insertText`, `replaceRange`, `getLine`, `getLines`, `getLanguage`, `setLanguage`, `formatDocument`, `getCursorPosition`, `setCursorPosition`, `executeCommand` |
| `vscode.fs` | `readFile`, `writeFile`, `delete`, `exists`, `listDir`, `watch` |
| `vscode.workspace` | `getRoot`, `openFile`, `findFiles`, `onDidSaveFile`, `onDidOpenFile` |
| `vscode.ui` | `showMessage`, `showError`, `showInputBox`, `showQuickPick`, `showProgress`, `createStatusBarItem`, `createWebViewPanel` |
| `vscode.commands` | `registerCommand`, `executeCommand` |
| `vscode.terminal` | `create`, `runCommand` |
| `vscode.http` | `get`, `post` (Tor-aware) |
| `vscode.storage` | `get`, `set`, `delete`, `clear` (per-plugin namespace) |
| `vscode.hooks` | `onSave`, `onFileOpen`, `onEditorChange`, `onCursorMove`, `onSettingsChange` |

Full reference: in-app under **Settings → Plugins → Plugin documentation**, or [assets/plugin-docs.html](assets/plugin-docs.html).

### Developer Mode

1. Settings → Developer Mode → ON
2. Settings → Developer → Pick folder *or* From URL
3. Plugin runs immediately in the editor sandbox.

### Publishing to Marketplace

1. Push a public GitHub repo with `plugin.json` + `main.js` in the root.
2. Visit [`vscodemobile-market.vercel.app`](https://vscodemobile-market.vercel.app), open the **Submit** tab.
3. Fill in name, author, description, plugin ID, GitHub URL.
4. Maintainer reviews — once approved, your plugin appears in the in-app Marketplace.

A ready-to-test example lives in [`example-plugins/hello-world/`](example-plugins/hello-world).

---

## Marketplace Backend

The marketplace runs on Vercel from the [`market/`](market) directory of this repo.

| Method | Path                       | Purpose                                         |
|--------|----------------------------|-------------------------------------------------|
| GET    | `/api/plugins/list`        | All approved plugins, sorted by rating          |
| GET    | `/api/plugins/info?id=…`   | Single plugin detail                            |
| GET    | `/api/plugins/review?id=…` | Reviews for a plugin                            |
| POST   | `/api/plugins/review`      | Add or update a review (requires `userToken`)   |
| POST   | `/api/plugins/download`    | Increment download counter (deduped per token)  |
| POST   | `/api/admin/submit`        | Submit a GitHub repo for moderation             |
| GET    | `/api/admin/pending`       | List pending submissions (admin key)            |
| POST   | `/api/admin/approve`       | Approve a pending submission (admin key)        |

Local dev:

```sh
cd market
npx vercel dev
```

See [`market/README.md`](market/README.md) for the data layout and storage notes.

---

## Architecture

```
lib/
├── main.dart                    # App entry, MultiProvider
├── app/theme.dart               # Dark+ color palette
├── screens/
│   ├── editor_screen.dart       # Main layout (activity bar + sidebar + Monaco + status)
│   ├── settings_screen.dart     # Settings, language, completion, plugin docs link
│   ├── marketplace_screen.dart  # Plugin marketplace
│   ├── plugin_details_screen.dart # Reviews, ratings, install/uninstall
│   └── plugin_docs_screen.dart  # In-app API docs (WebView, RU/EN)
├── widgets/
│   ├── activity_bar.dart        # Left 48px icon bar
│   ├── sidebar.dart             # File explorer / search / extensions
│   ├── tab_bar.dart             # Open file tabs with dirty indicator
│   ├── status_bar.dart          # Bottom 22px status bar
│   ├── terminal_panel.dart      # proot + Alpine terminal
│   └── file_tree.dart           # Recursive file tree
├── services/
│   ├── language_service.dart    # .txt-based UI localization
│   ├── completion_service.dart  # Project-wide IntelliSense (Dart/JS/TS/Python)
│   ├── tor_service.dart         # Orbot broadcast intent + SOCKS5 status
│   ├── plugin_service.dart      # Install from GitHub, list, uninstall
│   ├── plugin_sandbox.dart      # Headless WebView + vscode/xuncode bridge
│   ├── plugin_runtime.dart      # Active sandboxes registry, hooks fan-out
│   ├── editor_bridge.dart       # Monaco operations exposed to plugins
│   ├── review_service.dart      # Marketplace reviews + anonymous user token
│   ├── file_service.dart        # File / folder open, save, search
│   ├── terminal_service.dart    # Bridge to TerminalService.kt
│   └── settings_service.dart    # SharedPreferences wrapper
└── models/
    ├── settings_model.dart      # ChangeNotifier for settings
    ├── plugin.dart              # Plugin / InstalledPlugin / Review
    └── open_file.dart           # Open tabs state

android/app/src/main/kotlin/com/xunkal1/xuncode/MainActivity.kt    # Tor + Terminal MethodChannels
android/app/src/main/kotlin/com/xunkal1/xuncode/TerminalService.kt # proot + Alpine sessions, downloadProot, /system/bin/sh fallback
assets/editor.html                                                  # Monaco init + completion bridge
assets/languages/{ru,en}.txt                                        # Bundled UI translations
assets/plugin-docs.html                                             # In-app API reference (RU/EN)
assets/plugin-examples/hello-world/                                 # Bundled minimal plugin
example-plugins/hello-world/                                        # Same example, easy to clone
market/                                                             # Vercel API + admin UI
```

---

## Supported Languages

JavaScript · TypeScript · Python · Kotlin · Java · Dart · Go · Rust · C · C++ · C# · HTML · CSS · SCSS · JSON · YAML · Markdown · Shell · XML · PHP · Ruby · Swift · SQL · R · Lua

---

## Tor Support

Enable Tor in Settings. Requires [Orbot](https://play.google.com/store/apps/details?id=org.torproject.android) installed on the device. When active, plugin HTTP calls (`vscode.http.*`) are routed through SOCKS5 on `127.0.0.1:9050`.

---

## Author & Community

- GitHub: [@Hinderchik](https://github.com/Hinderchik)
- Dev channel: [t.me/XunKal1Dev](https://t.me/XunKal1Dev)
- Community channel: [t.me/GodPassTGK](https://t.me/GodPassTGK)

---

## License

MIT
