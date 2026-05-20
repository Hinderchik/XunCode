# VScode Mobile for Android

[![Build APK](https://github.com/Hinderchik/VScodeMobile/actions/workflows/build.yml/badge.svg)](https://github.com/Hinderchik/VScodeMobile/actions/workflows/build.yml)

A native Android code editor built with Flutter — Monaco Editor, Clim AI assistant, Plugin Marketplace, and Tor proxy support. Designed to look and feel like VS Code.

---

## Features

| Feature | Description |
|---|---|
| Monaco Editor | Same engine as VS Code — syntax highlighting for 25+ languages |
| IntelliSense | Code completion, hints, and navigation support |
| Go to Definition | Jump to symbols and references inside code |
| VSCode UI | Activity bar, sidebar, tabs, status bar, bottom Clim panel |
| File Tools | Project tree, search across files, Git, FTP/SFTP support |
| Clim AI | Chat, Explain, Complete — powered by Anthropic Claude |
| Cline-like AI Agent | Read, create, edit code, and launch terminal tasks |
| Proxy Stack | HTTP/HTTPS, SOCKS5, Tor via Orbot, system proxy, fallback chain |
| Run Code | Python, JS/Node.js, PHP, HTML/CSS live preview, Java, C/C++ |
| Plugin System | One-click install, JS/TS SDK, command and button APIs |
| Plugin Marketplace | Browse & install community plugins from Vercel-hosted site |
| Developer Mode | Test plugins locally without publishing |
| Mobile UX | Physical keyboard support and popup Ctrl/Alt/Shift keyboard |
| Offline First | Works offline for everything except AI and Git push |
| Settings | Theme, font, tab size, word wrap, auto save, API key, AI model |


---

## Download

- **Latest debug APK** — [GitHub Actions artifacts](https://github.com/Hinderchik/VScodeMobile/actions)
- **Release APK** — [GitHub Releases](https://github.com/Hinderchik/VScodeMobile/releases)

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
git clone https://github.com/Hinderchik/VScodeMobile.git
cd VScodeMobile

# Bundle Monaco Editor assets
npm install
npm run build:monaco

# Flutter deps
flutter pub get

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

## Plugin System

Plugins are single JavaScript files that run inside the Monaco WebView sandbox. Install from the Marketplace or load any URL directly.

### Minimal plugin

```js
VscodePlugin.register({
  id: 'my-org.my-plugin',
  name: 'My Plugin',
  version: '1.0.0',
  description: 'Does something cool',
  author: 'you',

  activate(ctx) {
    ctx.editor.addAction({
      id: 'my-plugin.hello',
      label: 'My Plugin: Hello',
      run() { ctx.ui.showMessage('Hello from My Plugin!'); }
    });
  },

  deactivate() {}
});
```

### Plugin API surface

| Namespace | Methods |
|---|---|
| `ctx.editor` | `getText`, `setText`, `getSelection`, `insertText`, `getCursorPosition`, `getLanguage`, `setLanguage`, `formatDocument`, `addAction` |
| `ctx.ui` | `showMessage`, `showError`, `showInputBox`, `showQuickPick` |
| `ctx.hooks` | `onSave`, `onFileOpen`, `onChange`, `onCursorMove` |
| `ctx.storage` | `get`, `set`, `remove` |
| `ctx.http` | `get`, `post` (Tor-aware) |

Full reference: [docs/plugin-api.md](docs/plugin-api.md) · also available in-app under Extensions → API Docs.

### Developer Mode

1. Settings → Developer Mode → ON
2. Settings → Developer → Load Local Plugin
3. Paste your plugin JS → runs immediately in the editor sandbox

### Publishing to Marketplace

1. Host your plugin JS at a public URL
2. Submit at `https://vscode-mobile-plugins.vercel.app/submit`
3. Fill in name, description, category, and the raw JS URL
4. Maintainer reviews and approves — plugin goes live in the app

---

## Architecture

```
lib/
├── main.dart                    # App entry, MultiProvider
├── app/theme.dart               # VSCode Dark+ color palette
├── screens/
│   ├── editor_screen.dart       # Main layout (activity bar + sidebar + Monaco + Clim + status)
│   ├── settings_screen.dart     # Full settings screen
│   ├── marketplace_screen.dart  # Plugin marketplace (Vercel API)
│   └── plugin_docs_screen.dart  # In-app API docs (WebView)
├── widgets/
│   ├── activity_bar.dart        # Left 48px icon bar
│   ├── sidebar.dart             # File explorer / search / extensions
│   ├── tab_bar.dart             # Open file tabs with dirty indicator
│   ├── status_bar.dart          # Bottom 22px status bar
│   ├── clim_panel.dart          # AI assistant bottom panel
│   └── file_tree.dart           # Recursive file tree
├── services/
│   ├── tor_service.dart         # Orbot broadcast intent + SOCKS5 status
│   ├── plugin_service.dart      # Install / remove / list plugins
│   ├── file_service.dart        # SAF file/folder open, save
│   ├── clim_service.dart        # Anthropic API (chat, explain, complete)
│   └── settings_service.dart    # SharedPreferences wrapper
└── models/
    ├── settings_model.dart      # ChangeNotifier for settings
    ├── plugin_model.dart        # Plugin metadata + fromJson
    └── open_file.dart           # Open tabs state

android/app/src/main/kotlin/…/MainActivity.kt   # Tor MethodChannel (startTor/stopTor)
assets/editor.html                               # Monaco init + VscodePlugin JS runtime
assets/plugin-docs.html                          # In-app API reference
docs/plugin-api.md                               # Full plugin API markdown docs
```

---

## Supported Languages

JavaScript · TypeScript · Python · Kotlin · Java · Dart · Go · Rust · C · C++ · C# · HTML · CSS · SCSS · JSON · YAML · Markdown · Shell · XML · PHP · Ruby · Swift · SQL · R · Lua

---

## Tor Support

Enable Tor in Settings. Requires [Orbot](https://play.google.com/store/apps/details?id=org.torproject.android) installed on the device. When active, all Clim AI requests and plugin HTTP calls are routed through SOCKS5 on `127.0.0.1:9050`.

---


## Author & Community

- GitHub: [@Hinderchik](https://github.com/Hinderchik)
- Dev channel: [t.me/XunKal1Dev](https://t.me/XunKal1Dev)
- Community channel: [t.me/GodPassTGK](https://t.me/GodPassTGK)

---

## License

MIT
