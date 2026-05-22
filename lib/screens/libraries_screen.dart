import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/theme.dart';
import '../models/language.dart';
import '../services/language_install_service.dart';
import '../services/language_service.dart';
import '../services/package_registry_service.dart';

class LibrariesScreen extends StatefulWidget {
  final Language language;
  const LibrariesScreen({super.key, required this.language});

  @override
  State<LibrariesScreen> createState() => _LibrariesScreenState();
}

class _LibrariesScreenState extends State<LibrariesScreen> {
  final _query = TextEditingController();
  final _registry = TextEditingController();
  List<PackageHit> _hits = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _registry.text =
        LanguageInstallService.instance.registryFor(widget.language) ?? '';
  }

  @override
  void dispose() {
    _query.dispose();
    _registry.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hits =
          await PackageRegistryService.instance.search(widget.language, q);
      if (!mounted) return;
      setState(() {
        _hits = hits;
        if (hits.isEmpty) {
          _error = LanguageService.of(context, listen: false)
              .tr('libraries.empty');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveRegistry() async {
    final v = _registry.text.trim();
    await LanguageInstallService.instance
        .setRegistryOverride(widget.language.id, v.isEmpty ? null : v);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(LanguageService.of(context, listen: false)
            .tr('libraries.registry_saved')),
        backgroundColor: VscodeTheme.accent,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = LanguageService.of(context);
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: Text(l10n.tr('libraries.title_for',
            params: {'name': widget.language.name})),
        backgroundColor: VscodeTheme.bgSidebar,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _query,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _runSearch(),
                  style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: l10n.tr('libraries.search_hint'),
                    hintStyle: const TextStyle(color: VscodeTheme.fgMuted),
                    filled: true,
                    fillColor: VscodeTheme.bgSidebar,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, color: VscodeTheme.accent),
                      onPressed: _runSearch,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _registry,
                        style: const TextStyle(
                            color: VscodeTheme.fg, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: widget.language.registry ??
                              l10n.tr('libraries.registry_hint'),
                          hintStyle: const TextStyle(
                              color: VscodeTheme.fgMuted, fontSize: 12),
                          filled: true,
                          fillColor: VscodeTheme.bgSidebar,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _saveRegistry,
                      child: Text(l10n.tr('common.save'),
                          style: const TextStyle(color: VscodeTheme.accent)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(color: VscodeTheme.accent),
          if (_error != null && _hits.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!,
                  style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _hits.length,
              addAutomaticKeepAlives: false,
              itemBuilder: (_, i) => _hitTile(_hits[i], l10n),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hitTile(PackageHit hit, LanguageService l10n) {
    return ListTile(
      tileColor: VscodeTheme.bgSidebar,
      dense: true,
      title: Text('${hit.name}  ${hit.version}',
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
      subtitle: Text(hit.description.isEmpty ? hit.installCommand : hit.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
      trailing: IconButton(
        icon: const Icon(Icons.copy, size: 16, color: VscodeTheme.accent),
        tooltip: l10n.tr('libraries.copy_command'),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: hit.installCommand));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(l10n.tr('libraries.copied')),
              backgroundColor: VscodeTheme.accent,
            ));
          }
        },
      ),
    );
  }
}
