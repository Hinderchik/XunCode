import 'package:flutter/material.dart';
import '../services/settings_service.dart';

class SettingsModel extends ChangeNotifier {
  final SettingsService _svc;

  SettingsModel(this._svc);

  ThemeMode get themeMode => _svc.themeMode;
  double get fontSize => _svc.fontSize;
  String get fontFamily => _svc.fontFamily;
  int get tabSize => _svc.tabSize;
  bool get wordWrap => _svc.wordWrap;
  String get autoSave => _svc.autoSave;
  bool get torEnabled => _svc.torEnabled;
  bool get developerMode => _svc.developerMode;
  String get language => _svc.language;

  Future<void> set<T>(String key, T value) async {
    await _svc.set(key, value);
    notifyListeners();
  }
}
