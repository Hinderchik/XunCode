import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../services/plugin_runtime.dart';

/// Quick-pick palette listing every command currently registered by an active
/// plugin. Returns the picked entry "pluginId:commandId" via Navigator.pop, and
/// fires the command itself.
Future<void> showPluginCommandPalette(BuildContext context) async {
  final entries = PluginRuntime.instance.allCommandIds();
  if (entries.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('No plugin commands registered'),
      backgroundColor: VscodeTheme.fgMuted,
    ));
    return;
  }

  final picked = await showDialog<String>(
    context: context,
    builder: (_) => _CommandPalette(entries: entries),
  );
  if (picked == null) return;
  await PluginRuntime.instance.executeCommand(picked);
}

class _CommandPalette extends StatefulWidget {
  final List<String> entries;
  const _CommandPalette({required this.entries});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _ctrl = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filter.isEmpty
        ? widget.entries
        : widget.entries
            .where((e) => e.toLowerCase().contains(_filter.toLowerCase()))
            .toList();

    return Dialog(
      backgroundColor: VscodeTheme.bgSidebar,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
              decoration: const InputDecoration(
                hintText: '> Type a command…',
                hintStyle: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12),
                prefixIcon: Icon(Icons.bolt_outlined, size: 16, color: VscodeTheme.fgMuted),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No matches', style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final entry = filtered[i];
                        final colon = entry.indexOf(':');
                        final pluginId = colon > 0 ? entry.substring(0, colon) : '';
                        final cmd = colon > 0 ? entry.substring(colon + 1) : entry;
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.terminal, size: 14, color: VscodeTheme.accent),
                          title: Text(cmd, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
                          subtitle: Text(pluginId,
                            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
                          onTap: () => Navigator.pop(context, entry),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
