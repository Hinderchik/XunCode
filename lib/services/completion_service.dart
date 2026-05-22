import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'file_service.dart';

/// Тип символа для подсказки. Соответствует `monaco.languages.CompletionItemKind`.
enum SymbolKind { text, function, klass, method, variable, constant, module, keyword }

class CompletionSymbol {
  final String name;
  final SymbolKind kind;
  final String detail;
  final String? sourcePath;

  const CompletionSymbol({
    required this.name,
    required this.kind,
    this.detail = '',
    this.sourcePath,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'kind': kind.name,
        'detail': detail,
        'sourcePath': sourcePath,
      };

  factory CompletionSymbol.fromJson(Map<String, Object?> j) => CompletionSymbol(
        name: j['name']?.toString() ?? '',
        kind: SymbolKind.values.firstWhere(
          (k) => k.name == j['kind'],
          orElse: () => SymbolKind.text,
        ),
        detail: j['detail']?.toString() ?? '',
        sourcePath: j['sourcePath']?.toString(),
      );
}

/// Провайдер автодополнения для конкретного языка. Получает на вход
/// содержимое файла и возвращает извлечённые символы. Регистрируется в
/// [CompletionService] на старте.
abstract class LanguageCompletionProvider {
  /// Список Monaco-идентификаторов языков, на которые отзывается провайдер.
  List<String> get languages;

  /// Извлечь символы из исходного кода файла.
  List<CompletionSymbol> parse(String source);
}

class _DartProvider extends LanguageCompletionProvider {
  @override
  List<String> get languages => ['dart'];

  static final _class = RegExp(r'\b(?:class|mixin|enum|extension)\s+([A-Z][\w$]*)');
  static final _func = RegExp(r'^\s*(?:Future<[^>]*>\s+|[A-Za-z_$][\w$<>?,\s]*\s+)?([a-z_][\w$]*)\s*\(', multiLine: true);
  static final _topVar = RegExp(r'^\s*(?:final|const|var|late)\s+(?:[A-Za-z_$][\w$<>?]*\s+)?([A-Za-z_$][\w$]*)\s*[=;]', multiLine: true);

  @override
  List<CompletionSymbol> parse(String source) {
    final out = <CompletionSymbol>[];
    final seen = <String>{};
    void add(String name, SymbolKind kind, [String detail = '']) {
      if (name.isEmpty) return;
      final key = '$kind:$name';
      if (seen.add(key)) out.add(CompletionSymbol(name: name, kind: kind, detail: detail));
    }
    for (final m in _class.allMatches(source)) add(m.group(1) ?? '', SymbolKind.klass, 'class');
    for (final m in _func.allMatches(source)) {
      final n = m.group(1) ?? '';
      if (_dartReserved.contains(n)) continue;
      add(n, SymbolKind.function, 'function');
    }
    for (final m in _topVar.allMatches(source)) add(m.group(1) ?? '', SymbolKind.variable, 'variable');
    return out;
  }

  static const _dartReserved = {
    'if', 'else', 'for', 'while', 'switch', 'case', 'return', 'try', 'catch',
    'finally', 'throw', 'class', 'extends', 'implements', 'with', 'mixin',
    'enum', 'extension', 'true', 'false', 'null', 'await', 'async', 'this', 'super', 'new',
  };
}

class _JsTsProvider extends LanguageCompletionProvider {
  @override
  List<String> get languages => ['javascript', 'typescript'];

  static final _func = RegExp(r'\bfunction\s+([A-Za-z_$][\w$]*)');
  static final _arrow = RegExp(r'\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$])\s*=>');
  static final _decl = RegExp(r'\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)');
  static final _class = RegExp(r'\bclass\s+([A-Za-z_$][\w$]*)');
  static final _method = RegExp(r'^\s*([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{', multiLine: true);

  @override
  List<CompletionSymbol> parse(String source) {
    final out = <CompletionSymbol>[];
    final seen = <String>{};
    void add(String name, SymbolKind kind, [String detail = '']) {
      if (name.isEmpty || _jsReserved.contains(name)) return;
      final key = '$kind:$name';
      if (seen.add(key)) out.add(CompletionSymbol(name: name, kind: kind, detail: detail));
    }
    for (final m in _class.allMatches(source)) add(m.group(1) ?? '', SymbolKind.klass, 'class');
    for (final m in _func.allMatches(source)) add(m.group(1) ?? '', SymbolKind.function, 'function');
    for (final m in _arrow.allMatches(source)) add(m.group(1) ?? '', SymbolKind.function, 'arrow');
    for (final m in _decl.allMatches(source)) add(m.group(1) ?? '', SymbolKind.variable, 'declaration');
    for (final m in _method.allMatches(source)) add(m.group(1) ?? '', SymbolKind.method, 'method');
    return out;
  }

  static const _jsReserved = {
    'if', 'else', 'for', 'while', 'switch', 'case', 'return', 'try', 'catch',
    'finally', 'throw', 'class', 'extends', 'function', 'true', 'false', 'null',
    'undefined', 'new', 'this', 'super', 'await', 'async', 'typeof', 'instanceof',
    'const', 'let', 'var', 'import', 'export', 'from', 'default', 'in', 'of',
  };
}

class _PythonProvider extends LanguageCompletionProvider {
  @override
  List<String> get languages => ['python'];

  static final _def = RegExp(r'^\s*def\s+([A-Za-z_][\w]*)', multiLine: true);
  static final _class = RegExp(r'^\s*class\s+([A-Za-z_][\w]*)', multiLine: true);
  static final _topVar = RegExp(r'^([A-Za-z_][\w]*)\s*=', multiLine: true);

  @override
  List<CompletionSymbol> parse(String source) {
    final out = <CompletionSymbol>[];
    final seen = <String>{};
    void add(String name, SymbolKind kind) {
      if (name.isEmpty || _pyReserved.contains(name)) return;
      final key = '$kind:$name';
      if (seen.add(key)) out.add(CompletionSymbol(name: name, kind: kind));
    }
    for (final m in _class.allMatches(source)) add(m.group(1) ?? '', SymbolKind.klass);
    for (final m in _def.allMatches(source)) add(m.group(1) ?? '', SymbolKind.function);
    for (final m in _topVar.allMatches(source)) add(m.group(1) ?? '', SymbolKind.variable);
    return out;
  }

  static const _pyReserved = {
    'if', 'elif', 'else', 'for', 'while', 'return', 'try', 'except', 'finally',
    'raise', 'class', 'def', 'lambda', 'True', 'False', 'None', 'and', 'or',
    'not', 'in', 'is', 'pass', 'break', 'continue', 'with', 'as', 'import', 'from',
  };
}

/// Сервис автодополнения. Сканирует файлы проекта, кэширует символы по
/// языку и отдаёт подсказки в редактор.
class CompletionService {
  CompletionService._();
  static final CompletionService instance = CompletionService._();

  final Map<String, LanguageCompletionProvider> _providers = {};
  final Map<String, List<CompletionSymbol>> _byFile = {};
  final Map<String, int> _mtimes = {};
  String? _projectRoot;
  Future<void>? _indexing;

  /// Зарегистрированные расширения и язык. Для незаявленных расширений
  /// сервис отдаст только локальные слова (это уже делает Monaco без нас).
  static const _extToLang = {
    '.dart': 'dart',
    '.js': 'javascript',
    '.jsx': 'javascript',
    '.ts': 'typescript',
    '.tsx': 'typescript',
    '.py': 'python',
  };

  bool _initialized = false;

  void _ensureProviders() {
    if (_initialized) return;
    _initialized = true;
    register(_DartProvider());
    register(_JsTsProvider());
    register(_PythonProvider());
  }

  void register(LanguageCompletionProvider p) {
    for (final l in p.languages) {
      _providers[l] = p;
    }
  }

  /// Корень проекта на момент последней индексации. Используется чтобы не
  /// переиндексировать при каждом открытии файла.
  String? get projectRoot => _projectRoot;

  /// Запустить индексацию проекта. Идемпотентно: повторные вызовы для того
  /// же корня сравнивают mtime файлов и пересчитывают только изменённые.
  Future<void> indexProject(String root) async {
    _ensureProviders();
    if (_indexing != null && _projectRoot == root) return _indexing!;
    final c = Completer<void>();
    _indexing = c.future;
    _projectRoot = root;
    try {
      await _loadCacheIfFresh();
      await _walkAndIndex(root);
      await _saveCache();
    } catch (_) {
      // индексация лучшее усилие — ошибки не должны ронять редактор
    } finally {
      c.complete();
      _indexing = null;
    }
  }

  Future<void> _walkAndIndex(String root) async {
    final dir = Directory(root);
    if (!await dir.exists()) return;
    var indexed = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split(Platform.pathSeparator).last;
      if (name.startsWith('.')) continue;
      final ext = _extension(name);
      final lang = _extToLang[ext];
      if (lang == null) continue;
      final provider = _providers[lang];
      if (provider == null) continue;
      try {
        final stat = await entity.stat();
        final mtime = stat.modified.millisecondsSinceEpoch;
        if (_mtimes[entity.path] == mtime && _byFile.containsKey(entity.path)) continue;
        if (stat.size > 512 * 1024) continue; // не парсим огромные файлы
        final source = await entity.readAsString();
        _byFile[entity.path] = provider.parse(source);
        _mtimes[entity.path] = mtime;
        indexed++;
        if (indexed > 500) break; // защита от чудовищных деревьев
      } catch (_) {}
    }
  }

  /// Подсказки по префиксу. Возвращает список JSON-структур, которые
  /// напрямую разворачиваются в `monaco.languages.CompletionItem` на стороне
  /// редактора.
  Future<List<Map<String, Object?>>> suggest({
    required String language,
    required String prefix,
    String? currentFilePath,
    int maxItems = 50,
  }) async {
    _ensureProviders();
    if (prefix.length < 1) return const [];
    final lang = language.toLowerCase();
    final lower = prefix.toLowerCase();
    final results = <CompletionSymbol>[];
    final seen = <String>{};

    void collect(List<CompletionSymbol> syms) {
      for (final s in syms) {
        if (!s.name.toLowerCase().startsWith(lower)) continue;
        if (!seen.add(s.name)) continue;
        results.add(s);
        if (results.length >= maxItems) break;
      }
    }

    // 1. Сам открытый файл — самый важный источник.
    if (currentFilePath != null) {
      final localSyms = _byFile[currentFilePath];
      if (localSyms != null) collect(localSyms);
    }
    // 2. Остальные файлы того же языка в проекте.
    if (results.length < maxItems) {
      _byFile.forEach((path, syms) {
        if (results.length >= maxItems) return;
        if (path == currentFilePath) return;
        final ext = _extension(path);
        if (_extToLang[ext] != lang) return;
        collect(syms);
      });
    }
    return results.map((s) {
      return {
        'label': s.name,
        'kind': _kindToMonaco(s.kind),
        'insertText': s.name,
        'detail': s.detail.isEmpty ? null : s.detail,
        if (s.sourcePath != null) 'documentation': s.sourcePath,
      };
    }).toList();
  }

  static int _kindToMonaco(SymbolKind k) {
    // Соответствует значениям monaco.languages.CompletionItemKind.
    switch (k) {
      case SymbolKind.method: return 0;
      case SymbolKind.function: return 1;
      case SymbolKind.constant: return 14;
      case SymbolKind.variable: return 4;
      case SymbolKind.klass: return 6;
      case SymbolKind.module: return 8;
      case SymbolKind.keyword: return 17;
      case SymbolKind.text: return 18;
    }
  }

  String _extension(String path) {
    final i = path.lastIndexOf('.');
    if (i <= 0 || i == path.length - 1) return '';
    return path.substring(i).toLowerCase();
  }

  Future<File> _cacheFile() async {
    await FileService.ensureLayout();
    return File('${FileService.cacheDir}/completion.json');
  }

  Future<void> _loadCacheIfFresh() async {
    if (_byFile.isNotEmpty) return;
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return;
      final raw = await f.readAsString();
      final data = jsonDecode(raw);
      if (data is! Map) return;
      if (data['root'] != _projectRoot) return;
      final files = data['files'];
      if (files is! Map) return;
      final mtimes = data['mtimes'];
      files.forEach((path, syms) {
        if (syms is! List) return;
        _byFile[path.toString()] = syms
            .whereType<Map>()
            .map((m) => CompletionSymbol.fromJson(Map<String, Object?>.from(m)))
            .toList();
      });
      if (mtimes is Map) {
        mtimes.forEach((path, t) {
          if (t is num) _mtimes[path.toString()] = t.toInt();
        });
      }
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final f = await _cacheFile();
      await f.parent.create(recursive: true);
      final payload = {
        'root': _projectRoot,
        'files': _byFile.map((k, v) => MapEntry(k, v.map((s) => s.toJson()).toList())),
        'mtimes': _mtimes,
      };
      await f.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  @visibleForTesting
  void debugReset() {
    _byFile.clear();
    _mtimes.clear();
    _projectRoot = null;
    _indexing = null;
  }
}
