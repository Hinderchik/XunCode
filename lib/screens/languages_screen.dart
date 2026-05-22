import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../models/language.dart';
import '../services/language_install_service.dart';
import '../services/language_service.dart';
import 'add_custom_language_screen.dart';
import 'libraries_screen.dart';

class LanguagesScreen extends StatefulWidget {
  const LanguagesScreen({super.key});

  @override
  State<LanguagesScreen> createState() => _LanguagesScreenState();
}

class _LanguagesScreenState extends State<LanguagesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final Map<String, double> _progress = {};
  final Map<String, String> _stage = {};
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    LanguageInstallService.instance.init();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _install(Language lang) async {
    if (_busy.contains(lang.id)) return;
    setState(() {
      _busy.add(lang.id);
      _progress[lang.id] = 0;
      _stage[lang.id] = '';
    });
    final l10n = LanguageService.of(context, listen: false);
    try {
      await LanguageInstallService.instance.install(
        lang,
        onProgress: (p, stage) {
          if (!mounted) return;
          setState(() {
            _progress[lang.id] = p;
            _stage[lang.id] = stage;
          });
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.tr('languages.install_done', params: {'name': lang.name})),
        backgroundColor: VscodeTheme.accent,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.tr('languages.install_failed', params: {'error': e})),
        backgroundColor: VscodeTheme.red,
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(lang.id));
    }
  }

  Future<void> _uninstall(Language lang) async {
    final l10n = LanguageService.of(context, listen: false);
    await LanguageInstallService.instance.uninstall(lang.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.tr('languages.uninstalled',
            params: {'name': lang.name})),
        backgroundColor: VscodeTheme.accent,
      ));
      setState(() {});
    }
  }

  Future<void> _removeCustom(Language lang) async {
    await LanguageInstallService.instance.removeCustom(lang.id);
    if (mounted) setState(() {});
  }

  void _openLibraries(Language lang) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => LibrariesScreen(language: lang)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.watch<LanguageService>();
    final svc = context.watch<LanguageInstallService>();
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: Text(l10n.tr('languages.title')),
        backgroundColor: VscodeTheme.bgSidebar,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: VscodeTheme.accent,
          labelColor: VscodeTheme.fg,
          unselectedLabelColor: VscodeTheme.fgMuted,
          tabs: [
            Tab(text: l10n.tr('languages.tab.builtin')),
            Tab(text: l10n.tr('languages.tab.custom')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _buildList(svc.builtin, l10n, custom: false),
          _buildCustom(svc, l10n),
        ],
      ),
      floatingActionButton: _tab.index == 1
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AddCustomLanguageScreen()));
                if (mounted) setState(() {});
              },
              backgroundColor: VscodeTheme.accent,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text(l10n.tr('languages.add_custom'),
                  style: const TextStyle(color: Colors.white)),
            )
          : null,
    );
  }

  Widget _buildList(List<Language> list, LanguageService l10n,
      {required bool custom}) {
    return ListView.builder(
      itemCount: list.length,
      addAutomaticKeepAlives: false,
      itemBuilder: (_, i) => _tile(list[i], l10n, removable: custom),
    );
  }

  Widget _buildCustom(LanguageInstallService svc, LanguageService l10n) {
    if (svc.custom.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.tr('languages.empty_custom'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 13)),
        ),
      );
    }
    return _buildList(svc.custom, l10n, custom: true);
  }

  Widget _tile(Language lang, LanguageService l10n, {required bool removable}) {
    final installed = LanguageInstallService.instance.isInstalledSync(lang.id);
    final busy = _busy.contains(lang.id);
    final progress = _progress[lang.id] ?? 0;
    final stage = _stage[lang.id] ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: VscodeTheme.bgSidebar,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VscodeTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(lang.name,
                          style: const TextStyle(
                              color: VscodeTheme.fg,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('v${lang.version} · ${lang.libManager ?? '—'}',
                          style: const TextStyle(
                              color: VscodeTheme.fgMuted, fontSize: 11)),
                    ],
                  ),
                ),
                if (installed && lang.libManager != null)
                  IconButton(
                    icon: const Icon(Icons.library_books_outlined,
                        size: 18, color: VscodeTheme.accent),
                    tooltip: l10n.tr('libraries.title'),
                    onPressed: () => _openLibraries(lang),
                  ),
                if (installed)
                  TextButton(
                    onPressed: busy ? null : () => _uninstall(lang),
                    child: Text(l10n.tr('common.uninstall'),
                        style: const TextStyle(
                            color: VscodeTheme.red, fontSize: 12)),
                  )
                else
                  ElevatedButton(
                    onPressed: busy ? null : () => _install(lang),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VscodeTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(l10n.tr('common.install')),
                  ),
                if (removable)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 18, color: VscodeTheme.red),
                    onPressed: busy ? null : () => _removeCustom(lang),
                  ),
              ],
            ),
            if (busy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: progress > 0 ? progress : null,
                color: VscodeTheme.accent,
                backgroundColor: VscodeTheme.bgInput,
                minHeight: 3,
              ),
              const SizedBox(height: 4),
              Text(
                  '$stage · ${(progress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                      color: VscodeTheme.fgMuted, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}
