import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/language.dart';
import 'file_service.dart';

typedef ProgressCb = void Function(double progress, String stage);

/// Скачивает / удаляет / перечисляет среды программирования.
///
/// Хранит:
///  • Бинарники / распакованные тулчейны:
///    `<privateRoot>/languages/<id>/`
///  • JSON-список пользовательских языков в SharedPreferences под ключом
///    `languages.custom`.
///  • Маркер `installed.json` внутри папки языка с реальной версией и URL,
///    из которого был установлен.
class LanguageInstallService extends ChangeNotifier {
  LanguageInstallService._();
  static final LanguageInstallService instance = LanguageInstallService._();

  static const _customKey = 'languages.custom';
  static const _registryOverrideKey = 'languages.registryOverride';

  List<Language> _custom = const [];
  Map<String, String> _registryOverride = const {};
  bool _loaded = false;

  /// Все известные языки: встроенные + пользовательские. Дубликаты по `id`
  /// исключаются — пользовательский с тем же id перебивает встроенный.
  List<Language> get allKnown {
    final byId = <String, Language>{};
    for (final b in builtinLanguages) {
      byId[b.id] = b;
    }
    for (final c in _custom) {
      byId[c.id] = c;
    }
    return byId.values.toList();
  }

  List<Language> get builtin => List.unmodifiable(builtinLanguages);
  List<Language> get custom => List.unmodifiable(_custom);

  Future<void> init() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _custom = Language.decodeList(prefs.getString(_customKey) ?? '');
    final raw = prefs.getString(_registryOverrideKey) ?? '';
    if (raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _registryOverride = decoded.map(
              (k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    _loaded = true;
  }

  // ── Custom language CRUD ──────────────────────────────────────────────

  Future<void> addCustom(Language lang) async {
    final filtered = _custom.where((l) => l.id != lang.id).toList()
      ..add(lang.copyWith(builtin: false));
    _custom = filtered;
    await _persistCustom();
    notifyListeners();
  }

  Future<void> removeCustom(String id) async {
    _custom = _custom.where((l) => l.id != id).toList();
    await _persistCustom();
    await _deleteInstallDir(id);
    notifyListeners();
  }

  Future<void> _persistCustom() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customKey, Language.encodeList(_custom));
  }

  // ── Install / uninstall ──────────────────────────────────────────────

  bool isInstalledSync(String id) {
    return File('${FileService.languagesInstallDir}/$id/installed.json')
        .existsSync();
  }

  Future<bool> isInstalled(String id) async {
    return File('${FileService.languagesInstallDir}/$id/installed.json')
        .exists();
  }

  String installPathOf(String id) =>
      '${FileService.languagesInstallDir}/$id';

  /// Скачивает архив языка и распаковывает в `<privateRoot>/languages/<id>/`.
  /// Поддерживает `.tar.gz` / `.tgz`, `.tar.xz`, `.tar`, `.zip`. Идемпотентно:
  /// если уже установлен — возвращает true сразу.
  Future<bool> install(Language lang, {ProgressCb? onProgress}) async {
    final dir = Directory(installPathOf(lang.id));
    if (await isInstalled(lang.id)) return true;
    await FileService.ensureLayout();
    await Directory(FileService.languagesInstallDir).create(recursive: true);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);

    final archivePath = '${FileService.tmpDir}/${lang.id}.archive';
    await _silent(() => File(archivePath).delete());

    onProgress?.call(0, 'Resolving');
    final dio = Dio();
    try {
      await dio.download(
        lang.url,
        archivePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total, 'Downloading');
          }
        },
      );
    } catch (e) {
      await _silent(() => File(archivePath).delete());
      throw 'Download failed: $e';
    }

    onProgress?.call(0, 'Extracting');
    try {
      await _extract(archivePath, dir.path,
          onProgress: (p) => onProgress?.call(p, 'Extracting'));
    } catch (e) {
      await _silent(() => dir.delete(recursive: true));
      throw 'Extraction failed: $e';
    } finally {
      await _silent(() => File(archivePath).delete());
    }

    final marker = File('${dir.path}/installed.json');
    await marker.writeAsString(jsonEncode(lang.toJson()));
    onProgress?.call(1.0, 'Done');
    notifyListeners();
    return true;
  }

  Future<void> uninstall(String id) async {
    await _deleteInstallDir(id);
    notifyListeners();
  }

  Future<void> _deleteInstallDir(String id) async {
    final dir = Directory(installPathOf(id));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // ── Registry override ────────────────────────────────────────────────

  /// Эффективный URL реестра для языка с учётом пользовательского override'а.
  String? registryFor(Language lang) =>
      _registryOverride[lang.id] ?? lang.registry;

  Future<void> setRegistryOverride(String id, String? url) async {
    final next = Map<String, String>.from(_registryOverride);
    if (url == null || url.isEmpty) {
      next.remove(id);
    } else {
      next[id] = url;
    }
    _registryOverride = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_registryOverrideKey, jsonEncode(next));
    notifyListeners();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  Future<void> _extract(String archivePath, String outDir,
      {void Function(double)? onProgress}) async {
    final lower = archivePath.toLowerCase();
    final input = InputFileStream(archivePath);
    try {
      Archive archive;
      if (lower.endsWith('.tar.gz') || lower.endsWith('.tgz') ||
          lower.endsWith('.archive') /* unknown ext, try gzip */) {
        // Сначала пробуем gzip + tar (чаще всего).
        final tarPath = '${FileService.tmpDir}/${_basename(archivePath)}.tar';
        try {
          final out = OutputFileStream(tarPath);
          try {
            GZipDecoder().decodeStream(input, out);
          } finally {
            await out.close();
          }
          final tarStream = InputFileStream(tarPath);
          try {
            archive = TarDecoder().decodeBuffer(tarStream);
            await _writeArchive(archive, outDir, onProgress);
          } finally {
            await tarStream.close();
          }
          await _silent(() => File(tarPath).delete());
          return;
        } catch (_) {
          await _silent(() => File(tarPath).delete());
          // Не gzip — попробуем дальше.
        }
      }
      // Закрываем и переоткрываем поток для повторных попыток.
      await input.close();
      final input2 = InputFileStream(archivePath);
      try {
        if (lower.endsWith('.tar.xz') || lower.endsWith('.txz')) {
          // XZDecoder в текущей версии archive не имеет decodeStream;
          // читаем архив целиком в память и распаковываем побайтово.
          await input2.close();
          final bytes = await File(archivePath).readAsBytes();
          final decodedBytes = XZDecoder().decodeBytes(bytes);
          archive = TarDecoder().decodeBytes(decodedBytes);
          await _writeArchive(archive, outDir, onProgress);
          return;
        }
        if (lower.endsWith('.tar')) {
          archive = TarDecoder().decodeBuffer(input2);
          await _writeArchive(archive, outDir, onProgress);
          return;
        }
        if (lower.endsWith('.zip') || lower.endsWith('.archive')) {
          archive = ZipDecoder().decodeBuffer(input2);
          await _writeArchive(archive, outDir, onProgress);
          return;
        }
        throw 'Unsupported archive format: $archivePath';
      } finally {
        await _silent(() => input2.close());
      }
    } finally {
      await _silent(() => input.close());
    }
  }

  Future<void> _writeArchive(Archive archive, String outDir,
      void Function(double)? onProgress) async {
    final total = archive.length;
    var done = 0;
    for (final entry in archive) {
      final outPath = '$outDir/${entry.name}';
      if (entry.isFile) {
        final f = File(outPath);
        await f.parent.create(recursive: true);
        await f.writeAsBytes(entry.content as List<int>, flush: false);
      } else {
        await Directory(outPath).create(recursive: true);
      }
      done++;
      if (onProgress != null && total > 0 && done % 100 == 0) {
        onProgress(done / total);
      }
    }
    onProgress?.call(1.0);
  }

  String _basename(String p) => p.split(Platform.pathSeparator).last;

  Future<void> _silent(Future<Object?> Function() block) async {
    try {
      await block();
    } catch (_) {}
  }

  @visibleForTesting
  void debugReset() {
    _custom = const [];
    _registryOverride = const {};
    _loaded = false;
  }
}
