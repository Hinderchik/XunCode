import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/plugin.dart';
import '../services/plugin_service.dart';
import 'plugin_details_screen.dart';

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  List<Plugin> _plugins = [];
  Set<String> _installedIds = {};
  bool _loading = true;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      PluginService.fetchMarketplace(query: _query),
      PluginService.listInstalled(),
    ]);
    if (!mounted) return;
    setState(() {
      _plugins = results[0] as List<Plugin>;
      _installedIds =
          (results[1] as List<InstalledPlugin>).map((p) => p.id).toSet();
      _loading = false;
    });
  }

  Future<void> _install(Plugin plugin) async {
    setState(() => _installedIds = {..._installedIds, plugin.id}); // optimistic
    try {
      await PluginService.installFromGithub(plugin.githubUrl);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${plugin.name} installed'),
        backgroundColor: VscodeTheme.accent,
      ));
      // Refresh so the download counter updates in the card.
      _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _installedIds = _installedIds.where((id) => id != plugin.id).toSet());
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Install failed: $e'),
        backgroundColor: VscodeTheme.red,
      ));
    }
  }

  Future<void> _uninstall(Plugin plugin) async {
    await PluginService.uninstall(plugin.id);
    if (!mounted) return;
    setState(() => _installedIds = _installedIds.where((id) => id != plugin.id).toSet());
  }

  void _openDetails(Plugin plugin) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => PluginDetailsScreen(plugin: plugin),
    )).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: const Text('Extensions Marketplace'),
        backgroundColor: VscodeTheme.bgSidebar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VscodeTheme.fgMuted),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search extensions…',
                prefixIcon: const Icon(Icons.search, size: 16, color: VscodeTheme.fgMuted),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                          _load();
                        })
                    : null,
              ),
              onSubmitted: (v) {
                setState(() => _query = v);
                _load();
              },
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: VscodeTheme.accent))
          : _plugins.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: VscodeTheme.accent,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _plugins.length,
                    itemBuilder: (_, i) => _buildCard(_plugins[i]),
                  ),
                ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.extension_off_outlined, size: 64, color: VscodeTheme.fgMuted),
          const SizedBox(height: 16),
          const Text('No extensions found', style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('The marketplace is online — pull to refresh',
            style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
          const SizedBox(height: 8),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildCard(Plugin plugin) {
    final isInstalled = _installedIds.contains(plugin.id);
    return InkWell(
      onTap: () => _openDetails(plugin),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: VscodeTheme.bgSidebar,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: VscodeTheme.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: VscodeTheme.bgInput,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: plugin.icon != null && plugin.icon!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          plugin.icon!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.extension, color: VscodeTheme.accent, size: 22),
                        ),
                      )
                    : const Icon(Icons.extension, color: VscodeTheme.accent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plugin.name,
                      style: const TextStyle(color: VscodeTheme.fg, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(plugin.author,
                      style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
                    const SizedBox(height: 6),
                    Text(plugin.description,
                      style: const TextStyle(color: VscodeTheme.fgLabel, fontSize: 12),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        StarRow(
                          rating: plugin.rating,
                          reviewsCount: plugin.reviewsCount,
                          downloads: plugin.downloads,
                        ),
                        const Spacer(),
                        isInstalled
                            ? OutlinedButton(
                                onPressed: () => _uninstall(plugin),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: VscodeTheme.red,
                                  side: const BorderSide(color: VscodeTheme.red),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Uninstall', style: TextStyle(fontSize: 11)),
                              )
                            : ElevatedButton(
                                onPressed: () => _install(plugin),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: VscodeTheme.accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: const Text('Install', style: TextStyle(fontSize: 11)),
                              ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
