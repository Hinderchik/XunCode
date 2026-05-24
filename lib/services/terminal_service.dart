import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'file_service.dart';

class TerminalBridge {
  static const _method = MethodChannel('com.xunkal1.xuncode/terminal');
  static const _events = EventChannel('com.xunkal1.xuncode/terminal/events');

  static Future<bool> isAlpineInstalled() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('alpine.installed') == true) {
      try {
        final root = await rootfsPath();
        if (root.isNotEmpty) {
          final marker = File('$root/.installed');
          if (await marker.exists()) return true;
          final dir = Directory(root);
          if (await dir.exists() && await _hasContent(dir)) {
            await marker.writeAsString('ok');
            return true;
          }
        }
      } catch (_) {}
      await prefs.setBool('alpine.installed', false);
    }
    final v = await _method.invokeMethod<bool>('isAlpineInstalled');
    final installed = v ?? false;
    if (installed) await prefs.setBool('alpine.installed', true);
    return installed;
  }

  static Future<bool> _hasContent(Directory dir) async {
    try {
      await for (final _ in dir.list(followLinks: false)) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  static Future<void> clearAlpineCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alpine.installed', false);
    try {
      final root = await rootfsPath();
      if (root.isNotEmpty) {
        final dir = Directory(root);
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    } catch (_) {}
    try {
      await _method.invokeMethod('clearRootfs');
    } catch (_) {}
  }

  static Future<String> rootfsPath() async {
    return await _method.invokeMethod<String>('rootfsPath') ?? '';
  }

  static Future<bool> prootExists() async {
    final v = await _method.invokeMethod<bool>('prootBinaryExists');
    return v ?? false;
  }

  /// Скачивает proot с GitHub в filesDir/proot/proot (один раз).
  /// Запуск через /system/bin/sh -c с chmod внутри — обходит noexec.
  static Future<void> ensureProot() async {
    final dir = await _method.invokeMethod<String>('filesDir');
    if (dir == null || dir.isEmpty) throw Exception('filesDir not available');
    final prootFile = File('$dir/proot/proot');
    if (await prootFile.exists() && await prootFile.length() > 1024) return;
    await prootFile.parent.create(recursive: true);

    const url =
        'https://raw.githubusercontent.com/Hinderchik/XunCode/main/proot';
    final dio = Dio();
    await dio.download(url, prootFile.path);

    if (!await prootFile.exists() || await prootFile.length() < 1024) {
      await _silent(() => prootFile.delete());
      throw Exception('proot download failed: file missing or too small');
    }
    // Делаем исполняемым через Java File API
    await _method.invokeMethod<void>('chmodProot');
  }

  /// Скачивает proot (публичный метод для UI). Возвращает true при успехе.
  static Future<bool> downloadProot() async {
    await ensureProot();
    return true;
  }

  /// Write data to a terminal session by ID (used by plugins).
  static Future<void> write({required String id, required String data}) async {
    await _method.invokeMethod('write', {'id': id, 'data': data});
  }

  /// Kill a terminal session by ID (used by plugins).
  static Future<void> kill({required String id}) async {
    await _method.invokeMethod('kill', {'id': id});
  }

  static Future<TerminalSession> createUnsandboxed({required String id}) async {
    final session = TerminalSession._(id, 80, 24);
    await session._openUnsandboxed();
    return session;
  }

  static Future<void> markAlpineInstalled() async {
    await _method.invokeMethod('markAlpineInstalled');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('alpine.installed', true);
  }

  static Future<void> installAlpine({
    void Function(double progress, String stage)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (await isAlpineInstalled()) return;

    final root = await rootfsPath();
    final rootDir = Directory(root);
    if (!await rootDir.exists()) await rootDir.create(recursive: true);

    final hasBin = await Directory('$root/bin').exists();
    final hasEtc = await Directory('$root/etc').exists();
    if (hasBin || hasEtc) {
      onProgress?.call(1.0, 'Found existing rootfs');
      await markAlpineInstalled();
      return;
    }

    final arch = _alpineArch();
    final url = 'https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/$arch/'
        'alpine-minirootfs-3.20.3-$arch.tar.gz';

    await FileService.ensureLayout();
    final tmpRoot = Directory(FileService.tmpDir);
    if (!await tmpRoot.exists()) await tmpRoot.create(recursive: true);
    final gzPath = '${tmpRoot.path}/alpine-minirootfs.tar.gz';
    final tarPath = '${tmpRoot.path}/alpine-minirootfs.tar';

    await _silent(() => File(gzPath).delete());
    await _silent(() => File(tarPath).delete());

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('rootfs_downloading', true);

    Future<void> cleanupPartial() async {
      await _silent(() => File(gzPath).delete());
      await _silent(() => File(tarPath).delete());
      try {
        if (await rootDir.exists()) {
          await rootDir.delete(recursive: true);
        }
      } catch (_) {}
      await prefs.setBool('rootfs_downloading', false);
      await prefs.setBool('alpine.installed', false);
    }

    try {
      final dio = Dio();
      await dio.download(
        url,
        gzPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            onProgress(received / total, 'Downloading Alpine');
          }
        },
      );

      onProgress?.call(0.0, 'Decompressing');
      final input = InputFileStream(gzPath);
      final output = OutputFileStream(tarPath);
      try {
        GZipDecoder().decodeStream(input, output);
      } finally {
        await input.close();
        await output.close();
      }

      onProgress?.call(0.0, 'Extracting');
      final tarStream = InputFileStream(tarPath);
      try {
        final archive = TarDecoder().decodeBuffer(tarStream);
        final total = archive.length;
        var done = 0;
        for (final entry in archive) {
          if (cancelToken?.isCancelled ?? false) {
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: url),
              reason: 'cancelled during extraction',
            );
          }
          final outPath = '$root/${entry.name}';
          if (entry.isFile) {
            final f = File(outPath);
            await f.parent.create(recursive: true);
            await f.writeAsBytes(entry.content as List<int>, flush: false);
          } else {
            await Directory(outPath).create(recursive: true);
          }
          done++;
          if (done % 200 == 0) {
            onProgress?.call(done / total, 'Extracting');
          }
        }
        onProgress?.call(1.0, 'Extracting');
      } finally {
        await tarStream.close();
      }

      final resolv = File('$root/etc/resolv.conf');
      await resolv.parent.create(recursive: true);
      await resolv.writeAsString('nameserver 1.1.1.1\nnameserver 8.8.8.8\n');

      await _silent(() => File(gzPath).delete());
      await _silent(() => File(tarPath).delete());
      await prefs.setBool('rootfs_downloading', false);
      await markAlpineInstalled();
    } catch (e) {
      await cleanupPartial();
      rethrow;
    }
  }

  static Future<void> _silent(Future<Object?> Function() block) async {
    try { await block(); } catch (_) {}
  }

  static String _alpineArch() {
    final abi = _abi();
    switch (abi) {
      case 'arm64-v8a':
        return 'aarch64';
      case 'armeabi-v7a':
        return 'armv7';
      case 'x86_64':
        return 'x86_64';
      case 'x86':
        return 'x86';
      default:
        return 'aarch64';
    }
  }

  static String _abi() {
    final v = Platform.operatingSystemVersion.toLowerCase();
    if (v.contains('aarch64') || v.contains('arm64')) return 'arm64-v8a';
    if (v.contains('armv7') || v.contains('armeabi')) return 'armeabi-v7a';
    if (v.contains('x86_64') || v.contains('amd64')) return 'x86_64';
    if (v.contains('i686') || v.contains('x86')) return 'x86';
    return 'arm64-v8a';
  }

  static Future<TerminalSession> create({
    required String id,
    int cols = 80,
    int rows = 24,
  }) async {
    final session = TerminalSession._(id, cols, rows);
    await session._open();
    return session;
  }
}

class TerminalSession {
  final String id;
  int cols;
  int rows;
  StreamSubscription? _sub;
  final _output = StreamController<String>.broadcast();

  TerminalSession._(this.id, this.cols, this.rows);

  Stream<String> get output => _output.stream;

  Future<void> _open() async {
    _sub = TerminalBridge._events
        .receiveBroadcastStream({'id': id})
        .listen(
          (event) {
            if (event is String) _output.add(event);
          },
          onError: (e) => _output.add('\n[stream error] $e\n'),
          onDone: () {
            if (!_output.isClosed) _output.add('\n[session ended]\n');
          },
        );

    final result = await TerminalBridge._method.invokeMethod<String>('create', {
      'id': id,
      'cols': cols,
      'rows': rows,
    });
    if (result != null && result != 'ok' && !result.startsWith('[terminal]')) {
      _output.add(result);
    }
  }

  Future<void> _openUnsandboxed() async {
    _sub = TerminalBridge._events
        .receiveBroadcastStream({'id': id})
        .listen(
          (event) {
            if (event is String) _output.add(event);
          },
          onError: (e) => _output.add('\n[stream error] $e\n'),
          onDone: () {
            if (!_output.isClosed) _output.add('\n[session ended]\n');
          },
        );

    final result = await TerminalBridge._method.invokeMethod<String>('createUnsandboxed', {
      'id': id,
    });
    if (result != null && result != 'ok' && !result.startsWith('[terminal]')) {
      _output.add(result);
    }
  }

  Future<void> write(String data) async {
    await TerminalBridge._method.invokeMethod('write', {'id': id, 'data': data});
  }

  Future<void> writeLine(String line) => write('$line\n');

  Future<void> resize(int c, int r) async {
    cols = c;
    rows = r;
    await TerminalBridge._method.invokeMethod('resize', {
      'id': id,
      'cols': c,
      'rows': r,
    });
  }

  Future<void> kill() async {
    runCatching(() => _sub?.cancel());
    await TerminalBridge._method.invokeMethod('kill', {'id': id});
    if (!_output.isClosed) await _output.close();
  }
}

T? runCatching<T>(T Function() block) {
  try {
    return block();
  } catch (_) {
    return null;
  }
}
