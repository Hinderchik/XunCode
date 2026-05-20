import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/plugin.dart';
import '../services/plugin_runtime.dart';
import '../services/plugin_service.dart';

class InstalledPluginsScreen extends StatefulWidget {
  const InstalledPluginsScreen({super.key});

  @override
  State<InstalledPluginsScreen> createState() => _InstalledPluginsScreenState();
}

class _InstalledPluginsScreenState extends State<InstalledPluginsScreen> {
  List<InstalledPlugin> _plugins = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await PluginService.listInstalled();
    if (!mounted) return;
    setState(() {
      _plugins = list;
      _loading = false;
    });
  }

  Future<void> _uninstall(InstalledPlugin p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VscodeTheme.bgSidebar,
        title: Text('Uninstall ${p.name}?',
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 14)),
        content: const Text(
          'Plugin files and stored data will be removed.',
          style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Uninstall', style: TextStyle(color: VscodeTheme.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await PluginRuntime.instance.deactivate(p.id);
    await PluginService.uninstall(p.id);
    _load();
  }

  Future<void> _reload(InstalledPlugin p) async {
    await PluginRuntime.instance.deactivate(p.id);
    await PluginRuntime.instance.activate(p);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${p.name} reloaded'),
      backgroundColor: VscodeTheme.accent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: const Text('Installed Plugins'),
        backgroundColor: VscodeTheme.bgSidebar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VscodeTheme.fgMuted),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: VscodeTheme.fgMuted, size: 18),
            tooltip: 'Reload all',
            onPressed: () async {
              await PluginRuntime.instance.reloadAll();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Plugins reloaded'),
                backgroundColor: VscodeTheme.accent,
              ));
              _load();
            },
          ),
        ],
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
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_off_outlined, size: 56, color: VscodeTheme.fgMuted),
          SizedBox(height: 12),
          Text('No plugins installed',
            style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 13)),
          SizedBox(height: 4),
          Text('Browse the marketplace to add some',
            style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildCard(InstalledPlugin p) {
    final active = PluginRuntime.instance.isActive(p.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: VscodeTheme.bgSidebar,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VscodeTheme.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.check_circle : Icons.circle_outlined,
                size: 16,
                color: active ? VscodeTheme.green : VscodeTheme.fgMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.name,
                  style: const TextStyle(color: VscodeTheme.fg, fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              Text('v${p.version}',
                style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Text('${p.id} · ${p.author}',
              style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
          ),
          if (p.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4),
              child: Text(p.description,
                style: const TextStyle(color: VscodeTheme.fgLabel, fontSize: 12),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              TextButton.icon(
                onPressed: () => _reload(p),
                icon: const Icon(Icons.refresh, size: 14, color: VscodeTheme.accent),
                label: const Text('Reload',
                  style: TextStyle(color: VscodeTheme.accent, fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _uninstall(p),
                style: OutlinedButton.styleFrom(
                  foregroundColor: VscodeTheme.red,
                  side: const BorderSide(color: VscodeTheme.red),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Uninstall', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
