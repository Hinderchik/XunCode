# XunCode for Android

[![Build APK](https://img.shields.io/badge/Build%20APK-passing-brightgreen)](https://github.com/Hinderchik/XunCode/actions/workflows/build.yml)

> **Лицензия / Licence:** проприетарная — форки, модификация и распространение **запрещены**. Подробнее в [LICENSE](LICENSE).
> Proprietary — forks, modification and redistribution are **prohibited**. See [LICENSE](LICENSE) for the full terms.

---

## Русский

**XunCode — мощный редактор кода для Android.** Нативное Flutter-приложение с движком Monaco Editor, GitHub-плагинами, плагин-маркетплейсом, поддержкой Tor через Orbot и встроенным proot-терминалом с Alpine Linux.

### Возможности
- Monaco Editor — тот же движок, что в VS Code, подсветка для 25+ языков.
- IntelliSense по всему проекту, переход к определению, переименование.
- **Мультиязычность:** Русский / English «из коробки», любой `.txt` в `Shared/XunCode/Languages/` добавляет новый язык интерфейса.
- **Установка языков программирования:** Python, Node.js, Go, Rust, Ruby, Lua, PHP, Java + любые свои сборки по URL.
- Плагин-система: GitHub-репо с `plugin.json` + `main.js`, песочница на InAppWebView.
- Маркетплейс плагинов (Vercel-бэкенд) с рейтингами и отзывами.
- Терминал proot + Alpine, fallback на `/system/bin/sh`.
- Прокси: HTTP/HTTPS, SOCKS5, Tor через Orbot.
- Запуск кода: Python, JS/Node, PHP, HTML/CSS preview, Java, C/C++.

### Требования
Android 8.0+ (API 26).

### Установка
- **APK:** [GitHub Releases](https://github.com/Hinderchik/XunCode/releases) или [артефакты CI](https://github.com/Hinderchik/XunCode/actions).

### Сборка из исходников (для оценки)
```sh
git clone https://github.com/Hinderchik/XunCode.git
cd XunCode
npm install && npm run build:monaco
bash scripts/fetch-proot.sh
flutter pub get
flutter pub run flutter_launcher_icons
flutter build apk --debug
```

### Лицензия
Это **не open-source**. Форки, копирование, модификация, переупаковка, коммерческое использование запрещены без письменного согласия автора. Полный текст — в [LICENSE](LICENSE). Запросы на отдельное разрешение: [t.me/XunKal1Dev](https://t.me/XunKal1Dev).

### Контакты
- GitHub: [@Hinderchik](https://github.com/Hinderchik)
- Dev-канал: [t.me/XunKal1Dev](https://t.me/XunKal1Dev)
- Сообщество: [t.me/GodPassTGK](https://t.me/GodPassTGK)
- Личка: [t.me/Skuuuchn](https://t.me/Skuuuchn)

---

## English

**XunCode is a powerful code editor for Android.** A native Flutter app with the Monaco Editor engine, GitHub-based plugins, a plugin marketplace, Tor support via Orbot, and an embedded proot terminal running Alpine Linux.

### Features
- Monaco Editor — same engine as VS Code, syntax highlighting for 25+ languages.
- Project-wide IntelliSense, go-to-definition, rename.
- **Multi-language UI:** Russian / English out of the box; drop any `.txt` into `Shared/XunCode/Languages/` to add another language.
- **Install runtimes:** Python, Node.js, Go, Rust, Ruby, Lua, PHP, Java, plus any custom build by URL.
- Plugin system — GitHub repos with `plugin.json` + `main.js`, sandboxed WebView.
- Plugin marketplace (Vercel backend) with ratings and reviews.
- proot + Alpine terminal, falls back to `/system/bin/sh`.
- Proxy: HTTP/HTTPS, SOCKS5, Tor via Orbot.
- Run code: Python, JS/Node, PHP, HTML/CSS preview, Java, C/C++.

### Requirements
Android 8.0+ (API 26).

### Install
- **APK:** [GitHub Releases](https://github.com/Hinderchik/XunCode/releases) or [CI artefacts](https://github.com/Hinderchik/XunCode/actions).

### Build from source (for evaluation)
```sh
git clone https://github.com/Hinderchik/XunCode.git
cd XunCode
npm install && npm run build:monaco
bash scripts/fetch-proot.sh
flutter pub get
flutter pub run flutter_launcher_icons
flutter build apk --debug
```

### Licence
**Not open source.** Forks, modification, redistribution, repackaging and commercial use are prohibited without prior written permission. See [LICENSE](LICENSE) for the full terms. For special permissions contact [t.me/XunKal1Dev](https://t.me/XunKal1Dev).

### Contacts
- GitHub: [@Hinderchik](https://github.com/Hinderchik)
- Dev channel: [t.me/XunKal1Dev](https://t.me/XunKal1Dev)
- Community: [t.me/GodPassTGK](https://t.me/GodPassTGK)
- DM: [t.me/Skuuuchn](https://t.me/Skuuuchn)