import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import '../app/theme.dart';
import '../models/open_file.dart';
import '../models/settings_model.dart';
import '../services/file_service.dart';
import '../services/tor_service.dart';
import '../services/plugin_service.dart';
import '../widgets/activity_bar.dart';
import '../widgets/sidebar.dart';
import '../widgets/tab_bar.dart';
import '../widgets/status_bar.dart';
import '../widgets/clim_panel.dart';
import '../widgets/terminal_panel.dart';
import 'settings_screen.dart';
import 'marketplace_screen.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  // Layout breakpoint between phone (bottom-nav) and tablet (VS Code) layouts.
  static const double _kTabletBreakpoint = 600;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  InAppWebViewController? _webCtrl;
  ActivityBarItem _activeBar = ActivityBarItem.explorer;
  bool _sidebarVisible = true;
  bool _climVisible = false;
  bool _terminalVisible = false;
  String _currentLang = 'plaintext';
  int _line = 1, _col = 1;
  String _selectedCode = '';
  bool _torEnabled = false;

  @override
  void initState() {
    super.initState();
    TorService.checkStatus().then((v) {
      if (mounted) setState(() => _torEnabled = v);
    });
  }

  // ── Bar / panel actions ────────────────────────────────────────────────────

  void _onActivityBarSelect(ActivityBarItem item) {
    if (item == ActivityBarItem.settings) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
      return;
    }
    if (item == ActivityBarItem.clim) {
      setState(() => _climVisible = !_climVisible);
      return;
    }
    if (item == ActivityBarItem.extensions) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MarketplaceScreen()));
      return;
    }
    setState(() {
      if (_activeBar == item) {
        _sidebarVisible = !_sidebarVisible;
      } else {
        _activeBar = item;
        _sidebarVisible = true;
      }
    });
  }

  void _openFile(String path, String name, String content) {
    final filesModel = context.read<OpenFilesModel>();
    filesModel.open(OpenFile(uri: path, name: name, content: content));
    _loadInEditor(content, name);
    final width = MediaQuery.of(context).size.width;
    if (width < _kTabletBreakpoint) {
      // Phones: close the drawer if it's open and dismiss any modal sheet
      // we might have been opened from.
      if (Navigator.canPop(context)) Navigator.pop(context);
      _scaffoldKey.currentState?.closeDrawer();
      setState(() => _sidebarVisible = false);
    }
  }

  void _loadInEditor(String content, String name) {
    final lang = _detectLang(name);
    setState(() => _currentLang = lang);
    _webCtrl?.evaluateJavascript(
      source: 'window.loadFile(${jsonEncode(content)}, ${jsonEncode(lang)}, ${jsonEncode(name)});',
    );
  }

  Future<void> _saveActive() async {
    final filesModel = context.read<OpenFilesModel>();
    final active = filesModel.active;
    if (active == null) return;
    final result = await _webCtrl?.evaluateJavascript(source: 'window.editor.getValue()');
    if (result == null) return;
    final content = result is String ? result : result.toString();
    await FileService.saveFile(active.uri, content);
    filesModel.markClean(active.uri);
  }

  Future<void> _toggleTor() async {
    if (_torEnabled) {
      await TorService.stop();
    } else {
      await TorService.start();
    }
    final status = await TorService.checkStatus();
    if (mounted) setState(() => _torEnabled = status);
  }

  void _insertCode(String code) {
    _webCtrl?.evaluateJavascript(
      source: "window.editor.trigger('clim', 'type', { text: ${jsonEncode(code)} });",
    );
  }

  void _toggleTerminal() => setState(() => _terminalVisible = !_terminalVisible);

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filesModel = context.watch<OpenFilesModel>();
    final settings = context.watch<SettingsModel>();

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final isTablet = constraints.maxWidth >= _kTabletBreakpoint;
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: VscodeTheme.bg,
          resizeToAvoidBottomInset: true,
          drawer: isTablet ? null : _PhoneDrawer(
            activePanel: _activeBar.name,
            filesModel: filesModel,
            onFileOpen: _openFile,
          ),
          body: SafeArea(
            child: isTablet
                ? _buildTabletLayout(filesModel, settings)
                : _buildPhoneLayout(filesModel, settings),
          ),
          bottomNavigationBar: isTablet ? null : _buildPhoneNav(),
        );
      },
    );
  }

  Widget _buildTabletLayout(OpenFilesModel filesModel, SettingsModel settings) {
    final isLandscape = MediaQuery.of(context).size.width >
        MediaQuery.of(context).size.height;
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              ActivityBar(selected: _activeBar, onSelect: _onActivityBarSelect),
              Expanded(
                child: Stack(
                  children: [
                    Column(
                      children: [
                        EditorTabBar(model: filesModel),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(child: _buildEditor(settings)),
                                    if (_terminalVisible)
                                      SizedBox(
                                        height: 280,
                                        child: TerminalPanel(
                                          onClose: _toggleTerminal,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (_climVisible)
                                ClimPanel(
                                  selectedCode: _selectedCode,
                                  language: _currentLang,
                                  onClose: () => setState(() => _climVisible = false),
                                  onInsertCode: _insertCode,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_sidebarVisible)
                      Positioned(
                        left: 0, top: 0, bottom: 0,
                        child: Row(
                          children: [
                            Sidebar(
                              activePanel: _activeBar.name,
                              filesModel: filesModel,
                              onFileOpen: _openFile,
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _sidebarVisible = false),
                              child: Container(
                                width: isLandscape ? 40 : 0,
                                color: Colors.transparent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Positioned(
                      right: 12, bottom: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'tablet-term',
                        backgroundColor: VscodeTheme.bgInput,
                        foregroundColor: VscodeTheme.accent,
                        tooltip: 'Toggle terminal',
                        onPressed: _toggleTerminal,
                        child: const Icon(Icons.terminal, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        VscodeStatusBar(
          fileName: filesModel.active?.name ?? '',
          language: _currentLang,
          line: _line,
          col: _col,
          torEnabled: _torEnabled,
          onTorTap: _toggleTor,
          onLangTap: () {},
        ),
      ],
    );
  }

  Widget _buildPhoneLayout(OpenFilesModel filesModel, SettingsModel settings) {
    return Column(
      children: [
        EditorTabBar(model: filesModel),
        Expanded(
          child: Stack(
            children: [
              _buildEditor(settings),
              // Bottom-edge gesture: drag up to open the terminal sheet.
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (d) {
                    if ((d.primaryDelta ?? 0) < -8 && !_terminalVisible) {
                      _openTerminalSheet();
                    }
                  },
                  child: Container(
                    height: 14,
                    alignment: Alignment.center,
                    child: Container(
                      width: 36, height: 3,
                      decoration: BoxDecoration(
                        color: VscodeTheme.fgMuted.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        VscodeStatusBar(
          fileName: filesModel.active?.name ?? '',
          language: _currentLang,
          line: _line,
          col: _col,
          torEnabled: _torEnabled,
          onTorTap: _toggleTor,
          onLangTap: () {},
        ),
      ],
    );
  }

  Widget _buildPhoneNav() {
    return BottomNavigationBar(
      backgroundColor: VscodeTheme.bgSidebar,
      selectedItemColor: VscodeTheme.accent,
      unselectedItemColor: VscodeTheme.fgMuted,
      type: BottomNavigationBarType.fixed,
      currentIndex: 0,
      onTap: (i) {
        switch (i) {
          case 0:
            setState(() => _activeBar = ActivityBarItem.explorer);
            _scaffoldKey.currentState?.openDrawer();
            break;
          case 1:
            setState(() => _activeBar = ActivityBarItem.search);
            _scaffoldKey.currentState?.openDrawer();
            break;
          case 2:
            _openTerminalSheet();
            break;
          case 3:
            _openClimSheet();
            break;
          case 4:
            Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()));
            break;
        }
      },
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.folder_outlined, size: 20), label: 'Files'),
        BottomNavigationBarItem(icon: Icon(Icons.search, size: 20), label: 'Search'),
        BottomNavigationBarItem(icon: Icon(Icons.terminal, size: 20), label: 'Terminal'),
        BottomNavigationBarItem(icon: Icon(Icons.auto_awesome, size: 20), label: 'Clim'),
        BottomNavigationBarItem(icon: Icon(Icons.settings_outlined, size: 20), label: 'Settings'),
      ],
    );
  }

  void _openTerminalSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VscodeTheme.bgPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.55,
          minChildSize: 0.25,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, __) => TerminalPanel(
            onClose: () => Navigator.maybePop(sheetCtx),
          ),
        );
      },
    );
  }

  void _openClimSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VscodeTheme.bgSidebar,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scroll) => SizedBox(
            width: double.infinity,
            child: ClimPanel(
              selectedCode: _selectedCode,
              language: _currentLang,
              onClose: () => Navigator.maybePop(sheetCtx),
              onInsertCode: _insertCode,
              fillWidth: true,
            ),
          ),
        );
      },
    );
  }

  // ── WebView ────────────────────────────────────────────────────────────────

  Widget _buildEditor(SettingsModel settings) {
    return InAppWebView(
      initialFile: 'assets/editor.html',
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        supportZoom: false,
        transparentBackground: true,
      ),
      onWebViewCreated: (ctrl) {
        _webCtrl = ctrl;
        _registerHandlers(ctrl, settings);
      },
      onLoadStop: (ctrl, _) async {
        await _applySettings(settings);
        await _loadInstalledPlugins(ctrl);
      },
    );
  }

  void _registerHandlers(InAppWebViewController ctrl, SettingsModel settings) {
    ctrl.addJavaScriptHandler(
      handlerName: 'onCursorChange',
      callback: (args) {
        if (!mounted) return;
        if (args.length >= 2) {
          setState(() {
            _line = args[0] is int ? args[0] : (args[0] as num).toInt();
            _col = args[1] is int ? args[1] : (args[1] as num).toInt();
          });
        }
      },
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'onSelectionChange',
      callback: (args) {
        if (!mounted) return;
        if (args.isNotEmpty) setState(() => _selectedCode = args[0]?.toString() ?? '');
      },
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'onContentChange',
      callback: (args) {
        final filesModel = context.read<OpenFilesModel>();
        final active = filesModel.active;
        if (active != null) filesModel.markDirty(active.uri);
        if (settings.autoSave == 'afterDelay') {
          Future.delayed(const Duration(seconds: 1), _saveActive);
        }
      },
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'installPlugin',
      callback: (args) async {
        if (args.isEmpty) return;
        final url = args[0] as String;
        try {
          final code = await PluginService.fetchPluginCode(url);
          await PluginService.install(url);
          await ctrl.evaluateJavascript(source: '(function(){$code})()');
        } catch (e) {
          await ctrl.evaluateJavascript(
            source: 'window.onPluginError && window.onPluginError(${jsonEncode(e.toString())})',
          );
        }
      },
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'removePlugin',
      callback: (args) async {
        if (args.isEmpty) return;
        await PluginService.remove(args[0]);
      },
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'listPlugins',
      callback: (_) async => await PluginService.getInstalled(),
    );
    ctrl.addJavaScriptHandler(
      handlerName: 'saveFile',
      callback: (args) async {
        if (args.length < 2) return;
        await FileService.saveFile(args[0], args[1]);
        if (mounted) context.read<OpenFilesModel>().markClean(args[0]);
      },
    );
  }

  Future<void> _applySettings(SettingsModel s) async {
    final payload = jsonEncode({
      'fontSize': s.fontSize,
      'fontFamily': s.fontFamily,
      'tabSize': s.tabSize,
      'wordWrap': s.wordWrap ? 'on' : 'off',
    });
    await _webCtrl?.evaluateJavascript(source: 'window.applySettings && window.applySettings($payload);');
  }

  Future<void> _loadInstalledPlugins(InAppWebViewController ctrl) async {
    final urls = await PluginService.getInstalled();
    for (final url in urls) {
      try {
        final code = await PluginService.fetchPluginCode(url);
        await ctrl.evaluateJavascript(source: '(function(){$code})()');
      } catch (_) {}
    }
  }

  String _detectLang(String name) {
    final ext = name.split('.').last.toLowerCase();
    const map = {
      'js': 'javascript', 'ts': 'typescript', 'jsx': 'javascript', 'tsx': 'typescript',
      'py': 'python', 'kt': 'kotlin', 'java': 'java', 'dart': 'dart', 'go': 'go',
      'rs': 'rust', 'c': 'c', 'cpp': 'cpp', 'h': 'cpp', 'cs': 'csharp',
      'html': 'html', 'css': 'css', 'scss': 'scss', 'json': 'json',
      'yaml': 'yaml', 'yml': 'yaml', 'md': 'markdown', 'sh': 'shell',
      'xml': 'xml', 'php': 'php', 'rb': 'ruby', 'swift': 'swift',
      'sql': 'sql', 'r': 'r', 'lua': 'lua',
    };
    return map[ext] ?? 'plaintext';
  }
}

class _PhoneDrawer extends StatelessWidget {
  final String activePanel;
  final OpenFilesModel filesModel;
  final void Function(String path, String name, String content) onFileOpen;

  const _PhoneDrawer({
    required this.activePanel,
    required this.filesModel,
    required this.onFileOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: VscodeTheme.bgSidebar,
      width: 280,
      child: SafeArea(
        child: Sidebar(
          activePanel: activePanel,
          filesModel: filesModel,
          onFileOpen: (path, name, content) {
            onFileOpen(path, name, content);
          },
        ),
      ),
    );
  }
}
