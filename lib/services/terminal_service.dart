import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Bridge to the native [TerminalService.kt]. Each [TerminalSession] owns one
/// proot+Alpine shell process; output is pushed via an EventChannel and writes
/// go through a MethodChannel.
class TerminalBridge {
  static const _method = MethodChannel('com.vscode.android/terminal');
  static const _events = EventChannel('com.vscode.android/terminal/events');

  static Future<bool> isAlpineInstalled() async {
    final v = await _method.invokeMethod<bool>('isAlpineInstalled');
    return v ?? false;
  }

  static Future<String> rootfsPath() async {
    return await _method.invokeMethod<String>('rootfsPath') ?? '';
  }

  static Future<bool> prootExists() async {
    final v = await _method.invokeMethod<bool>('prootBinaryExists');
    return v ?? false;
  }

  /// Asks native side to download a proot static binary into filesDir/bin/proot.
  /// Returns 'ok' on success or an error string.
  static Future<String> downloadProot() async {
    final r = await _method.invokeMethod<String>('downloadProot');
    return r ?? 'error: no response';
  }

  /// Boots a /system/bin/sh session — used when proot can't be obtained.
  static Future<TerminalSession> createUnsandboxed({required String id}) async {
    final session = TerminalSession._(id, 80, 24);
    await session._openUnsandboxed();
    return session;
  }

  static Future<void> markAlpineInstalled() =>
      _method.invokeMethod('markAlpineInstalled');

  /// Downloads the Alpine minirootfs and extracts it into the app's filesDir.
  /// Calls [onProgress] with bytes-received for download phase, then again
  /// during extraction. Idempotent: short-circuits if already installed.
  ///
  /// Streaming: gunzips into a temp .tar file, then walks tar entries one at
  /// a time via TarDecoder so the whole archive never sits in memory at once.
  static Future<void> installAlpine({
    void Function(double progress, String stage)? onProgress,
  }) async {
    if (await isAlpineInstalled()) return;

    final root = await rootfsPath();
    final rootDir = Directory(root);
    if (!await rootDir.exists()) await rootDir.create(recursive: true);

    final arch = _alpineArch();
    final url = 'https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/$arch/'
        'alpine-minirootfs-3.20.3-$arch.tar.gz';

    final tmpDir = await getTemporaryDirectory();
    final gzPath = '${tmpDir.path}/alpine-minirootfs.tar.gz';
    final tarPath = '${tmpDir.path}/alpine-minirootfs.tar';

    await _silent(() => File(gzPath).delete());
    await _silent(() => File(tarPath).delete());

    final dio = Dio();
    await dio.download(
      url,
      gzPath,
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
    await markAlpineInstalled();
  }

  static Future<void> _silent(Future<Object?> Function() block) async {
    try { await block(); } catch (_) {}
  }

  static String _alpineArch() {
    // Android arch -> Alpine arch
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
    // Best-effort; Flutter doesn't expose the running ABI directly. We rely
    // on Platform.version / Platform.operatingSystemVersion fallback to 64-bit.
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

/// Helper that swallows synchronous exceptions — used for best-effort cleanup
/// where we genuinely don't care about failures.
T? runCatching<T>(T Function() block) {
  try {
    return block();
  } catch (_) {
    return null;
  }
}
