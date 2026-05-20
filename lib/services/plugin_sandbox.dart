import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/plugin.dart';
import '../services/file_service.dart';
import 'editor_bridge.dart';
import 'plugin_service.dart';

typedef UiCallback = void Function(String message, {bool isError});
typedef OpenFileCallback = Future<void> Function(String path);
typedef InputBoxCallback = Future<String?> Function(String? title, String? placeholder, String? value);
typedef QuickPickCallback = Future<String?> Function(List<String> items, String? title);

class PluginSandbox {
  final InstalledPlugin plugin;
  final EditorBridge editor;
  final UiCallback onUiMessage;
  final OpenFileCallback? onOpenFile;
  final InputBoxCallback? onShowInputBox;
  final QuickPickCallback? onShowQuickPick;

  HeadlessInAppWebView? _headless;
  InAppWebViewController? _ctrl;
  final _registeredCommands = <String>{};
  final _ready = Completer<void>();

  PluginSandbox({
    required this.plugin,
    required this.editor,
    required this.onUiMessage,
    this.onOpenFile,
    this.onShowInputBox,
    this.onShowQuickPick,
  });

  Future<void> load() async {
    final code = await PluginService.readPluginCode(plugin);
    final html = _bootstrapHtml(plugin.id, code);
    _headless = HeadlessInAppWebView(
      initialData: InAppWebViewInitialData(
        data: html,
        mimeType: 'text/html',
        encoding: 'utf-8',
        baseUrl: WebUri('about:blank'),
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        allowFileAccessFromFileURLs: false,
        allowUniversalAccessFromFileURLs: false,
      ),
      onWebViewCreated: (c) {
        _ctrl = c;
        _registerHostHandlers(c);
      },
      onLoadStop: (_, __) {
        if (!_ready.isCompleted) _ready.complete();
      },
    );
    await _headless!.run();
    return _ready.future;
  }

  Future<void> dispose() async {
    try {
      await _headless?.dispose();
    } catch (_) {}
    _headless = null;
    _ctrl = null;
  }

  Future<void> executeCommand(String id) async {
    if (!_registeredCommands.contains(id)) return;
    await _ctrl?.evaluateJavascript(
      source: 'window.__plugin_run_command && window.__plugin_run_command(${jsonEncode(id)})',
    );
  }

  Set<String> get commands => Set.unmodifiable(_registeredCommands);

  void _registerHostHandlers(InAppWebViewController c) {
    c.addJavaScriptHandler(
      handlerName: 'host.invoke',
      callback: (args) async {
        if (args.isEmpty) return {'ok': false, 'error': 'no args'};
        final method = args[0]?.toString() ?? '';
        final params = args.length > 1 && args[1] is Map
            ? Map<String, dynamic>.from(args[1] as Map)
            : <String, dynamic>{};
        try {
          final result = await _dispatch(method, params);
          return {'ok': true, 'value': result};
        } catch (e) {
          return {'ok': false, 'error': e.toString()};
        }
      },
    );
    c.addJavaScriptHandler(
      handlerName: 'host.registerCommand',
      callback: (args) {
        if (args.isEmpty) return null;
        final id = args[0]?.toString() ?? '';
        if (id.isNotEmpty) _registeredCommands.add(id);
        return null;
      },
    );
  }

  Future<dynamic> _dispatch(String method, Map<String, dynamic> p) async {
    switch (method) {
      // editor
      case 'editor.getText':
        return editor.getText();
      case 'editor.setText':
        await editor.setText(p['text']?.toString() ?? '');
        return null;
      case 'editor.getSelection':
        return editor.getSelection();
      case 'editor.setSelection':
        await editor.setSelection(
          (p['startLine'] as num?)?.toInt() ?? 1,
          (p['startColumn'] as num?)?.toInt() ?? 1,
          (p['endLine'] as num?)?.toInt() ?? 1,
          (p['endColumn'] as num?)?.toInt() ?? 1,
        );
        return null;
      case 'editor.insertText':
        await editor.insertText(p['text']?.toString() ?? '');
        return null;
      case 'editor.replaceRange':
        await editor.replaceRange(
          (p['startLine'] as num?)?.toInt() ?? 1,
          (p['startColumn'] as num?)?.toInt() ?? 1,
          (p['endLine'] as num?)?.toInt() ?? 1,
          (p['endColumn'] as num?)?.toInt() ?? 1,
          p['text']?.toString() ?? '',
        );
        return null;
      case 'editor.getLine':
        return editor.getLine((p['line'] as num?)?.toInt() ?? 1);
      case 'editor.getLines':
        return editor.getLines();
      case 'editor.getLanguage':
        return editor.getLanguage();
      case 'editor.setLanguage':
        await editor.setLanguage(p['language']?.toString() ?? 'plaintext');
        return null;
      case 'editor.formatDocument':
        await editor.formatDocument();
        return null;
      case 'editor.getCursorPosition':
        return editor.getCursorPosition();
      case 'editor.setCursorPosition':
        await editor.setCursorPosition(
          (p['line'] as num?)?.toInt() ?? 1,
          (p['column'] as num?)?.toInt() ?? 1,
        );
        return null;
      case 'editor.executeCommand':
        await editor.executeCommand(p['command']?.toString() ?? '');
        return null;

      // ui
      case 'ui.showMessage':
        onUiMessage(p['text']?.toString() ?? '');
        return null;
      case 'ui.showError':
        onUiMessage(p['text']?.toString() ?? '', isError: true);
        return null;
      case 'ui.showInputBox':
        return onShowInputBox?.call(
          p['title']?.toString(),
          p['placeholder']?.toString(),
          p['value']?.toString(),
        );
      case 'ui.showQuickPick':
        final items = (p['items'] is List)
            ? (p['items'] as List).map((e) => e.toString()).toList()
            : <String>[];
        return onShowQuickPick?.call(items, p['title']?.toString());

      // storage
      case 'storage.get':
        return _storageGet(p['key']?.toString() ?? '');
      case 'storage.set':
        await _storageSet(p['key']?.toString() ?? '', p['value']?.toString() ?? '');
        return null;
      case 'storage.delete':
        await _storageDelete(p['key']?.toString() ?? '');
        return null;
      case 'storage.clear':
        await _storageClear();
        return null;

      // http
      case 'http.get':
        return _httpGet(p);
      case 'http.post':
        return _httpPost(p);

      // fs
      case 'fs.readFile':
        return _fsReadFile(p['path']?.toString() ?? '');
      case 'fs.writeFile':
        return _fsWriteFile(p['path']?.toString() ?? '', p['data']?.toString() ?? '');
      case 'fs.delete':
        return _fsDelete(p['path']?.toString() ?? '');
      case 'fs.exists':
        return _fsExists(p['path']?.toString() ?? '');
      case 'fs.listDir':
        return _fsListDir(p['path']?.toString() ?? '');

      // workspace
      case 'workspace.getRoot':
        await FileService.ensureLayout();
        return FileService.projectsDir;
      case 'workspace.findFiles':
        return _workspaceFindFiles(p['pattern']?.toString() ?? '');
      case 'workspace.openFile':
        if (onOpenFile != null) await onOpenFile!(p['path']?.toString() ?? '');
        return null;

      default:
        throw Exception('Unknown method: $method');
    }
  }

  Future<String?> _fsReadFile(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  Future<void> _fsWriteFile(String path, String data) async {
    final f = File(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(data);
  }

  Future<bool> _fsDelete(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) return false;
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
    return true;
  }

  Future<bool> _fsExists(String path) async {
    final type = await FileSystemEntity.type(path);
    return type != FileSystemEntityType.notFound;
  }

  Future<List<Map<String, Object>>> _fsListDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) return [];
    final out = <Map<String, Object>>[];
    await for (final entity in dir.list(followLinks: false)) {
      out.add({
        'name': entity.path.split('/').last,
        'path': entity.path,
        'isDir': entity is Directory,
      });
    }
    return out;
  }

  Future<List<String>> _workspaceFindFiles(String pattern) async {
    await FileService.ensureLayout();
    final root = Directory(FileService.projectsDir);
    final results = <String>[];
    final regex = _globToRegExp(pattern);
    if (!await root.exists()) return results;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = entity.path.substring(root.path.length + 1);
      if (regex.hasMatch(rel)) results.add(entity.path);
      if (results.length >= 1000) break;
    }
    return results;
  }

  static RegExp _globToRegExp(String pattern) {
    if (pattern.isEmpty) return RegExp(r'.*');
    final sb = StringBuffer('^');
    var i = 0;
    while (i < pattern.length) {
      final c = pattern[i];
      if (c == '*') {
        if (i + 1 < pattern.length && pattern[i + 1] == '*') {
          sb.write('.*');
          i += 2;
          continue;
        }
        sb.write('[^/]*');
      } else if (c == '?') {
        sb.write('[^/]');
      } else if ('.+()[]{}^\$\\|'.contains(c)) {
        sb.write('\\$c');
      } else {
        sb.write(c);
      }
      i++;
    }
    sb.write(r'$');
    return RegExp(sb.toString());
  }

  Future<String?> _storageGet(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('plugin:${plugin.id}:$key');
  }

  Future<void> _storageSet(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plugin:${plugin.id}:$key', value);
  }

  Future<void> _storageDelete(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('plugin:${plugin.id}:$key');
  }

  Future<void> _storageClear() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'plugin:${plugin.id}:';
    for (final k in prefs.getKeys().where((k) => k.startsWith(prefix))) {
      await prefs.remove(k);
    }
  }

  Future<Map<String, dynamic>> _httpGet(Map<String, dynamic> p) async {
    final url = p['url']?.toString() ?? '';
    final headers = (p['headers'] is Map)
        ? Map<String, String>.from((p['headers'] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString())))
        : <String, String>{};
    final res = await http.get(Uri.parse(url), headers: headers).timeout(const Duration(seconds: 30));
    return {'status': res.statusCode, 'body': res.body};
  }

  Future<Map<String, dynamic>> _httpPost(Map<String, dynamic> p) async {
    final url = p['url']?.toString() ?? '';
    final headers = (p['headers'] is Map)
        ? Map<String, String>.from((p['headers'] as Map).map(
            (k, v) => MapEntry(k.toString(), v.toString())))
        : <String, String>{};
    final body = p['body'];
    final encoded = body is String ? body : jsonEncode(body);
    headers.putIfAbsent('content-type', () => 'application/json');
    final res = await http
        .post(Uri.parse(url), headers: headers, body: encoded)
        .timeout(const Duration(seconds: 30));
    return {'status': res.statusCode, 'body': res.body};
  }

  Future<void> fireHook(String name, [Object? data]) async {
    await _ctrl?.evaluateJavascript(
      source:
          'window.__plugin_fire_hook && window.__plugin_fire_hook(${jsonEncode(name)}, ${jsonEncode(data)})',
    );
  }

  String _bootstrapHtml(String pluginId, String code) {
    const runtime = r'''
      (function () {
        const pending = new Map();
        let nextId = 1;

        function invoke(method, params) {
          return window.flutter_inappwebview.callHandler('host.invoke', method, params || {})
            .then(r => {
              if (!r) return null;
              if (r.ok === false) throw new Error(r.error || 'invoke failed');
              return r.value;
            });
        }

        const commands = new Map();
        const hooks = {};

        function on(name, cb) {
          (hooks[name] = hooks[name] || []).push(cb);
        }

        window.__plugin_fire_hook = function (name, data) {
          (hooks[name] || []).forEach(cb => { try { cb(data); } catch (e) { console.error(e); } });
        };

        window.__plugin_run_command = function (id) {
          const cb = commands.get(id);
          if (cb) { try { cb(); } catch (e) { console.error(e); } }
        };

        const editor = {
          getText: () => invoke('editor.getText'),
          setText: (t) => invoke('editor.setText', { text: String(t) }),
          getSelection: () => invoke('editor.getSelection'),
          setSelection: (sl, sc, el, ec) => invoke('editor.setSelection',
            { startLine: sl, startColumn: sc, endLine: el, endColumn: ec }),
          insertText: (t) => invoke('editor.insertText', { text: String(t) }),
          replaceRange: (sl, sc, el, ec, t) => invoke('editor.replaceRange',
            { startLine: sl, startColumn: sc, endLine: el, endColumn: ec, text: String(t) }),
          getLine: (l) => invoke('editor.getLine', { line: l }),
          getLines: () => invoke('editor.getLines'),
          getLanguage: () => invoke('editor.getLanguage'),
          setLanguage: (id) => invoke('editor.setLanguage', { language: String(id) }),
          formatDocument: () => invoke('editor.formatDocument'),
          getCursorPosition: () => invoke('editor.getCursorPosition'),
          setCursorPosition: (l, c) => invoke('editor.setCursorPosition', { line: l, column: c }),
          executeCommand: (cmd) => invoke('editor.executeCommand', { command: String(cmd) }),
        };

        const ui = {
          showMessage: (text) => invoke('ui.showMessage', { text: String(text) }),
          showError: (text) => invoke('ui.showError', { text: String(text) }),
          showInputBox: (opts) => invoke('ui.showInputBox', {
            title: opts && opts.title ? String(opts.title) : null,
            placeholder: opts && opts.placeholder ? String(opts.placeholder) : null,
            value: opts && opts.value ? String(opts.value) : null,
          }),
          showQuickPick: (items, opts) => invoke('ui.showQuickPick', {
            items: Array.isArray(items) ? items.map(String) : [],
            title: opts && opts.title ? String(opts.title) : null,
          }),
          showProgress: (title) => Promise.resolve(),
          createStatusBarItem: () => ({ setText: () => {}, dispose: () => {} }),
          createWebViewPanel: () => ({ dispose: () => {} }),
        };

        const storage = {
          get: (k) => invoke('storage.get', { key: String(k) }),
          set: (k, v) => invoke('storage.set', { key: String(k), value: String(v) }),
          delete: (k) => invoke('storage.delete', { key: String(k) }),
          clear: () => invoke('storage.clear'),
        };

        const http = {
          get: (url, headers) => invoke('http.get', { url: String(url), headers: headers || {} }),
          post: (url, body, headers) => invoke('http.post',
            { url: String(url), body: body, headers: headers || {} }),
        };

        const commandsApi = {
          registerCommand: (id, cb) => {
            commands.set(id, cb);
            window.flutter_inappwebview.callHandler('host.registerCommand', id);
          },
          executeCommand: (id) => {
            const cb = commands.get(id);
            return cb ? Promise.resolve(cb()) : Promise.resolve(null);
          },
        };

        const fs = {
          readFile: (path) => invoke('fs.readFile', { path: String(path) }),
          writeFile: (path, data) => invoke('fs.writeFile', { path: String(path), data: String(data) }),
          delete: (path) => invoke('fs.delete', { path: String(path) }),
          exists: (path) => invoke('fs.exists', { path: String(path) }),
          listDir: (path) => invoke('fs.listDir', { path: String(path) }),
          watch: (path, cb) => ({ dispose: () => {} }),
        };

        const workspace = {
          getRoot: () => invoke('workspace.getRoot'),
          openFile: (path) => invoke('workspace.openFile', { path: String(path) }),
          findFiles: (pattern) => invoke('workspace.findFiles', { pattern: String(pattern || '**/*') }),
          onDidSaveFile: (cb) => on('onSave', cb),
          onDidOpenFile: (cb) => on('onFileOpen', cb),
        };

        const terminal = {
          create: () => Promise.resolve({ id: '' }),
          runCommand: (cmd) => Promise.resolve({ status: 0, output: '' }),
        };

        window.vscode = {
          editor, ui, storage, http, fs, workspace, terminal,
          commands: commandsApi,
          hooks: {
            onSave: (cb) => on('onSave', cb),
            onFileOpen: (cb) => on('onFileOpen', cb),
            onEditorChange: (cb) => on('onEditorChange', cb),
            onCursorMove: (cb) => on('onCursorMove', cb),
            onSettingsChange: (cb) => on('onSettingsChange', cb),
          },
        };

        const moduleObj = { exports: {} };
        window.module = moduleObj;
        window.exports = moduleObj.exports;

        window.__plugin_activate = function () {
          try {
            const ex = window.module.exports || window.exports || {};
            if (typeof ex.activate === 'function') {
              ex.activate(window.vscode);
            }
          } catch (e) {
            console.error('plugin activate failed', e);
          }
        };
      })();
    ''';
    return '''
<!DOCTYPE html>
<html><head><meta charset="utf-8"></head><body>
<script>$runtime</script>
<script>
try {
  $code
} catch (e) {
  console.error('plugin top-level error', e);
}
</script>
<script>window.__plugin_activate && window.__plugin_activate();</script>
</body></html>
''';
  }
}
