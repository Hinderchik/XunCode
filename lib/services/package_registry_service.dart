import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/language.dart';
import 'language_install_service.dart';

/// Один результат поиска по реестру пакетов.
class PackageHit {
  final String name;
  final String version;
  final String description;
  final String? homepage;

  /// Готовая команда для копирования / выполнения в терминале:
  /// `pip install foo`, `npm install foo@1.2.3` и т.п.
  final String installCommand;

  const PackageHit({
    required this.name,
    required this.version,
    required this.description,
    required this.installCommand,
    this.homepage,
  });
}

/// Поиск пакетов в официальных реестрах. Хранит таймауты и логику
/// выбора эндпоинта по `language.libManager` / `registryFor()`.
class PackageRegistryService {
  PackageRegistryService._();
  static final PackageRegistryService instance = PackageRegistryService._();

  static const _timeout = Duration(seconds: 12);

  Future<List<PackageHit>> search(Language language, String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final manager = (language.libManager ?? '').toLowerCase();
    final registry = LanguageInstallService.instance.registryFor(language);
    try {
      switch (manager) {
        case 'pip':
          return _searchPyPI(q, registry);
        case 'npm':
          return _searchNpm(q, registry);
        case 'cargo':
          return _searchCrates(q, registry);
        case 'gem':
          return _searchRubyGems(q, registry);
        default:
          // Custom registry: best effort — пробуем npm-стиль search,
          // если не выходит, отдаём пустой список с подсказкой выше.
          if (registry != null && registry.isNotEmpty) {
            return _searchGeneric(q, registry);
          }
          return const [];
      }
    } catch (_) {
      return const [];
    }
  }

  Future<List<PackageHit>> _searchPyPI(String q, String? registry) async {
    // PyPI «полноценного» search-API не отдаёт, поэтому используем
    // /pypi/<name>/json для точного попадания и /simple/ для подсказок.
    final base = (registry ?? 'https://pypi.org/pypi/').replaceAll(RegExp(r'/?$'), '/');
    final url = Uri.parse('${base}${Uri.encodeComponent(q)}/json');
    final r = await http.get(url).timeout(_timeout);
    if (r.statusCode != 200) return const [];
    final data = jsonDecode(r.body);
    if (data is! Map) return const [];
    final info = data['info'];
    if (info is! Map) return const [];
    final name = info['name']?.toString() ?? q;
    final version = info['version']?.toString() ?? '';
    return [
      PackageHit(
        name: name,
        version: version,
        description: info['summary']?.toString() ?? '',
        homepage: info['home_page']?.toString(),
        installCommand: 'pip install $name${version.isEmpty ? '' : '==$version'}',
      ),
    ];
  }

  Future<List<PackageHit>> _searchNpm(String q, String? registry) async {
    // npm search через registry.npmjs.org/-/v1/search?text=...
    var base = registry ?? 'https://registry.npmjs.org/';
    if (!base.endsWith('/')) base = '$base/';
    final url = Uri.parse('${base}-/v1/search?text=${Uri.encodeQueryComponent(q)}&size=20');
    final r = await http.get(url).timeout(_timeout);
    if (r.statusCode != 200) return const [];
    final data = jsonDecode(r.body);
    if (data is! Map) return const [];
    final objects = data['objects'];
    if (objects is! List) return const [];
    return objects
        .whereType<Map>()
        .map((o) {
          final pkg = o['package'];
          if (pkg is! Map) return null;
          final name = pkg['name']?.toString() ?? '';
          final version = pkg['version']?.toString() ?? '';
          return PackageHit(
            name: name,
            version: version,
            description: pkg['description']?.toString() ?? '',
            homepage: (pkg['links'] is Map) ? (pkg['links'] as Map)['homepage']?.toString() : null,
            installCommand: 'npm install $name${version.isEmpty ? '' : '@$version'}',
          );
        })
        .whereType<PackageHit>()
        .toList();
  }

  Future<List<PackageHit>> _searchCrates(String q, String? registry) async {
    var base = registry ?? 'https://crates.io/api/v1/';
    if (!base.endsWith('/')) base = '$base/';
    final url = Uri.parse('${base}crates?q=${Uri.encodeQueryComponent(q)}&per_page=20');
    final r = await http.get(url, headers: {'User-Agent': 'XunCode/1.0'}).timeout(_timeout);
    if (r.statusCode != 200) return const [];
    final data = jsonDecode(r.body);
    if (data is! Map) return const [];
    final crates = data['crates'];
    if (crates is! List) return const [];
    return crates
        .whereType<Map>()
        .map((c) {
          final name = c['name']?.toString() ?? '';
          final version = c['max_stable_version']?.toString() ??
              c['newest_version']?.toString() ??
              '';
          return PackageHit(
            name: name,
            version: version,
            description: c['description']?.toString() ?? '',
            homepage: c['homepage']?.toString(),
            installCommand: 'cargo add $name${version.isEmpty ? '' : '@$version'}',
          );
        })
        .toList();
  }

  Future<List<PackageHit>> _searchRubyGems(String q, String? registry) async {
    var base = registry ?? 'https://rubygems.org/api/v1/';
    if (!base.endsWith('/')) base = '$base/';
    final url = Uri.parse('${base}search.json?query=${Uri.encodeQueryComponent(q)}');
    final r = await http.get(url).timeout(_timeout);
    if (r.statusCode != 200) return const [];
    final data = jsonDecode(r.body);
    if (data is! List) return const [];
    return data.whereType<Map>().take(20).map((g) {
      final name = g['name']?.toString() ?? '';
      final version = g['version']?.toString() ?? '';
      return PackageHit(
        name: name,
        version: version,
        description: g['info']?.toString() ?? '',
        homepage: g['homepage_uri']?.toString(),
        installCommand: 'gem install $name${version.isEmpty ? '' : ' -v $version'}',
      );
    }).toList();
  }

  Future<List<PackageHit>> _searchGeneric(String q, String registry) async {
    // Пытаемся достать прямо страницу — если это JSON, показываем raw-name.
    final url = Uri.parse('${registry.endsWith('/') ? registry : '$registry/'}$q');
    try {
      final r = await http.get(url).timeout(_timeout);
      if (r.statusCode == 200) {
        return [
          PackageHit(
            name: q,
            version: '',
            description: 'Custom registry response (${r.body.length} bytes)',
            homepage: url.toString(),
            installCommand: '# открыть $url',
          ),
        ];
      }
    } catch (_) {}
    return const [];
  }
}
