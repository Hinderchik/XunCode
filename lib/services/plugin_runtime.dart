import 'dart:async';

import '../models/plugin.dart';
import 'editor_bridge.dart';
import 'plugin_sandbox.dart';
import 'plugin_service.dart';

class PluginRuntime {
  PluginRuntime._();
  static final PluginRuntime instance = PluginRuntime._();

  final Map<String, PluginSandbox> _active = {};
  EditorBridge? _editor;
  void Function(String message, {bool isError})? _uiNotifier;

  void attachEditor(EditorBridge bridge) {
    _editor = bridge;
  }

  void attachUi(void Function(String message, {bool isError}) notifier) {
    _uiNotifier = notifier;
  }

  Future<void> activateInstalled() async {
    final list = await PluginService.listInstalled();
    for (final p in list) {
      unawaited(activate(p));
    }
  }

  Future<void> activate(InstalledPlugin p) async {
    if (_editor == null) return;
    if (_active.containsKey(p.id)) return;
    final sandbox = PluginSandbox(
      plugin: p,
      editor: _editor!,
      onUiMessage: (msg, {bool isError = false}) {
        _uiNotifier?.call(msg, isError: isError);
      },
    );
    try {
      await sandbox.load();
      _active[p.id] = sandbox;
    } catch (_) {
      await sandbox.dispose();
    }
  }

  Future<void> deactivate(String id) async {
    final s = _active.remove(id);
    if (s != null) await s.dispose();
  }

  Future<void> deactivateAll() async {
    for (final s in _active.values.toList()) {
      await s.dispose();
    }
    _active.clear();
  }

  Future<void> fireSave(String path) async {
    for (final s in _active.values) {
      await s.fireHook('onSave', path);
    }
  }

  Future<void> fireFileOpen(String path) async {
    for (final s in _active.values) {
      await s.fireHook('onFileOpen', path);
    }
  }

  Future<void> fireEditorChange(String content) async {
    for (final s in _active.values) {
      await s.fireHook('onEditorChange', content);
    }
  }

  Future<void> fireCursorMove(int line, int column) async {
    for (final s in _active.values) {
      await s.fireHook('onCursorMove', {'line': line, 'column': column});
    }
  }
}
