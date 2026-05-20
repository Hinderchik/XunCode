import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app/theme.dart';
import '../models/github_user.dart';
import '../models/settings_model.dart';
import '../services/file_service.dart';
import '../services/github_oauth_service.dart';
import 'about_screen.dart';
import 'github_signin_screen.dart';
import 'installed_plugins_screen.dart';
import 'plugin_docs_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  GithubUser? _githubUser;
  bool _githubLoading = true;
  bool _hasAllFiles = false;
  bool _sharedPublic = false;
  String _sharedPath = '';
  String _privatePath = '';

  @override
  void initState() {
    super.initState();
    _loadGithub();
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    await FileService.ensureLayout();
    final has = await FileService.hasAllFilesAccess();
    if (!mounted) return;
    setState(() {
      _hasAllFiles = has;
      _sharedPublic = FileService.sharedIsPublic;
      _sharedPath = FileService.sharedRoot;
      _privatePath = FileService.privateRoot;
    });
  }

  Future<void> _grantStorage() async {
    await FileService.requestAllFilesAccess();
    // Re-check after a short delay so the UI updates when the user returns.
    Future.delayed(const Duration(seconds: 1), _loadStorage);
  }

  Future<void> _loadGithub() async {
    final user = await GithubOAuthService.getUser();
    if (!mounted) return;
    setState(() {
      _githubUser = user;
      _githubLoading = false;
    });
  }

  Future<void> _signIn() async {
    final user = await Navigator.push<GithubUser?>(
      context,
      MaterialPageRoute(builder: (_) => const GithubSignInScreen()),
    );
    if (user != null && mounted) {
      setState(() => _githubUser = user);
    } else {
      _loadGithub();
    }
  }

  Future<void> _signOut() async {
    await GithubOAuthService.signOut();
    if (mounted) setState(() => _githubUser = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsModel>();
    return Scaffold(
      backgroundColor: VscodeTheme.bg,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: VscodeTheme.bgSidebar,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: VscodeTheme.fgMuted),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        children: [
          _section('Appearance'),
          _dropdown(context, 'Theme', s.themeMode == ThemeMode.dark ? 'dark' : 'light',
            ['dark', 'light'], (v) => s.set('theme', v!)),
          _slider(context, 'Font Size', s.fontSize, 10, 24,
            (v) => s.set('fontSize', v)),
          _dropdown(context, 'Font Family', s.fontFamily,
            ['JetBrains Mono', 'Fira Code', 'Cascadia Code', 'monospace'],
            (v) => s.set('fontFamily', v!)),
          _section('Editor'),
          _dropdown(context, 'Tab Size', s.tabSize.toString(),
            ['2', '4', '8'], (v) => s.set('tabSize', int.parse(v!))),
          _toggle(context, 'Word Wrap', s.wordWrap, (v) => s.set('wordWrap', v)),
          _dropdown(context, 'Auto Save', s.autoSave,
            ['off', 'afterDelay', 'onFocusChange'],
            (v) => s.set('autoSave', v!)),
          _section('Sync'),
          _buildGithubSync(),
          _section('Plugins'),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.extension_outlined, size: 18, color: VscodeTheme.accent),
            title: const Text('Installed Plugins',
              style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: const Text('Manage, reload, or uninstall',
              style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, size: 16, color: VscodeTheme.fgMuted),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const InstalledPluginsScreen())),
          ),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.menu_book_outlined, size: 18, color: VscodeTheme.accent),
            title: const Text('Документация по плагинам',
              style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: const Text('Plugin API reference (RU / EN)',
              style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
            trailing: const Icon(Icons.chevron_right, size: 16, color: VscodeTheme.fgMuted),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const PluginDocsScreen())),
          ),
          _section('Network'),
          _toggle(context, 'Tor Proxy (via Orbot)', s.torEnabled,
            (v) => s.set('torEnabled', v)),
          _section('Storage'),
          _buildStorageInfo(),
          _section('Developer'),
          _toggle(context, 'Developer Mode', s.developerMode,
            (v) => s.set('developerMode', v)),
          if (s.developerMode) _devModePanel(context),
          _section('About'),
          _info('Version', '1.0.0'),
          _info('Platform', 'Flutter · Android'),
          _link(context, 'GitHub: @Hinderchik', 'https://github.com/Hinderchik'),
          _link(context, 'Dev channel: t.me/XunKal1Dev', 'https://t.me/XunKal1Dev'),
          _link(context, 'Community: t.me/GodPassTGK', 'https://t.me/GodPassTGK'),
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            title: const Text('About VScode Mobile',
              style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, size: 16, color: VscodeTheme.fgMuted),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildGithubSync() {
    if (_githubLoading) {
      return Container(
        color: VscodeTheme.bgSidebar,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        alignment: Alignment.centerLeft,
        child: const SizedBox(
          width: 14, height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: VscodeTheme.accent),
        ),
      );
    }
    final user = _githubUser;
    if (user == null) {
      return ListTile(
        tileColor: VscodeTheme.bgSidebar,
        dense: true,
        leading: const Icon(Icons.code, size: 18, color: VscodeTheme.accent),
        title: const Text('Sign in with GitHub',
          style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
        subtitle: const Text('Sync settings and projects across devices',
          style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right, size: 16, color: VscodeTheme.fgMuted),
        onTap: _signIn,
      );
    }
    return Column(
      children: [
        ListTile(
          tileColor: VscodeTheme.bgSidebar,
          dense: true,
          leading: user.avatarUrl != null
              ? CircleAvatar(radius: 14, backgroundImage: NetworkImage(user.avatarUrl!))
              : const CircleAvatar(radius: 14, child: Icon(Icons.person, size: 16)),
          title: Text('@${user.login}',
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
          subtitle: Text(user.name ?? 'Connected to GitHub',
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
          trailing: TextButton(
            onPressed: _signOut,
            child: const Text('Sign out',
              style: TextStyle(color: VscodeTheme.red, fontSize: 12)),
          ),
        ),
        Container(
          color: VscodeTheme.bgSidebar,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          alignment: Alignment.centerLeft,
          child: const Text('Repo sync coming soon — token stored securely.',
            style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 10)),
        ),
      ],
    );
  }

  Widget _buildStorageInfo() {
    return Column(
      children: [
        ListTile(
          tileColor: VscodeTheme.bgSidebar,
          dense: true,
          leading: Icon(
            _sharedPublic ? Icons.folder_shared_outlined : Icons.folder_off_outlined,
            size: 18,
            color: _sharedPublic ? VscodeTheme.accent : VscodeTheme.red,
          ),
          title: const Text('Projects folder',
            style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
          subtitle: Text(
            _sharedPath.isEmpty
                ? 'Resolving…'
                : (_sharedPublic
                    ? _sharedPath
                    : '$_sharedPath\n(app-private fallback — files removed on uninstall)'),
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
          ),
          isThreeLine: !_sharedPublic && _sharedPath.isNotEmpty,
        ),
        ListTile(
          tileColor: VscodeTheme.bgSidebar,
          dense: true,
          leading: const Icon(Icons.lock_outline, size: 18, color: VscodeTheme.fgMuted),
          title: const Text('App data',
            style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
          subtitle: Text(
            _privatePath.isEmpty ? 'Resolving…' : _privatePath,
            style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
          ),
        ),
        if (!_hasAllFiles)
          ListTile(
            tileColor: VscodeTheme.bgSidebar,
            dense: true,
            leading: const Icon(Icons.shield_outlined, size: 18, color: VscodeTheme.accent),
            title: const Text('Grant All Files Access',
              style: TextStyle(color: VscodeTheme.fg, fontSize: 13)),
            subtitle: const Text(
              'Lets the app save projects to /Shared/CodeMobile so they survive uninstall',
              style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11),
            ),
            trailing: const Icon(Icons.open_in_new, size: 14, color: VscodeTheme.accent),
            onTap: _grantStorage,
          ),
      ],
    );
  }

    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(title.toUpperCase(),
      style: const TextStyle(fontSize: 11, color: VscodeTheme.fgLabel,
        letterSpacing: 1, fontWeight: FontWeight.w600)),
  );

  Widget _toggle(BuildContext ctx, String label, bool value, ValueChanged<bool> onChanged) =>
    SwitchListTile(
      title: Text(label, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
      value: value,
      onChanged: onChanged,
      activeColor: VscodeTheme.accent,
      tileColor: VscodeTheme.bgSidebar,
      dense: true,
    );

  Widget _dropdown(BuildContext ctx, String label, String value,
      List<String> options, ValueChanged<String?> onChanged) =>
    ListTile(
      tileColor: VscodeTheme.bgSidebar,
      dense: true,
      title: Text(label, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
      trailing: DropdownButton<String>(
        value: value,
        dropdownColor: VscodeTheme.bgInput,
        style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
        underline: const SizedBox(),
        items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
        onChanged: onChanged,
      ),
    );

  Widget _slider(BuildContext ctx, String label, double value,
      double min, double max, ValueChanged<double> onChanged) =>
    ListTile(
      tileColor: VscodeTheme.bgSidebar,
      dense: true,
      title: Text('$label: ${value.round()}px',
        style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
      subtitle: Slider(
        value: value, min: min, max: max, divisions: (max - min).round(),
        activeColor: VscodeTheme.accent,
        onChanged: onChanged,
        onChangeEnd: onChanged,
      ),
    );

  Widget _info(String label, String value) => ListTile(
    tileColor: VscodeTheme.bgSidebar,
    dense: true,
    title: Text(label, style: const TextStyle(color: VscodeTheme.fg, fontSize: 13)),
    trailing: Text(value, style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
  );

  Widget _link(BuildContext ctx, String label, String url) => ListTile(
    tileColor: VscodeTheme.bgSidebar,
    dense: true,
    title: Text(label, style: const TextStyle(color: VscodeTheme.accent, fontSize: 13)),
    trailing: const Icon(Icons.open_in_new, size: 14, color: VscodeTheme.accent),
    onTap: () async {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    },
  );

  Widget _devModePanel(BuildContext ctx) {
    final ctrl = TextEditingController();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Load Local Plugin (paste JS code):',
            style: TextStyle(color: VscodeTheme.fgLabel, fontSize: 12)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: VscodeTheme.bgInput,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: VscodeTheme.border),
            ),
            child: TextField(
              controller: ctrl,
              maxLines: 8,
              style: const TextStyle(color: VscodeTheme.fg, fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: '// VscodePlugin.register({ id: "my-plugin", ... })',
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(10),
              ),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: () {
              // TODO: inject into WebView via navigator key
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Plugin loaded in editor'),
                  backgroundColor: VscodeTheme.accent),
              );
            },
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Run Plugin'),
            style: ElevatedButton.styleFrom(
              backgroundColor: VscodeTheme.accent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
