import 'dart:io';
import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../models/open_file.dart';
import '../services/file_service.dart';
import 'file_tree.dart';

class Sidebar extends StatefulWidget {
  final String activePanel;
  final OpenFilesModel filesModel;
  final Function(String path, String name, String content) onFileOpen;

  const Sidebar({
    super.key,
    required this.activePanel,
    required this.filesModel,
    required this.onFileOpen,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  List<FileNode> _tree = [];
  String _folderPath = '';
  String _folderName = '';
  final _searchCtrl = TextEditingController();
  List<SearchResult> _searchResults = [];
  bool _searching = false;
  String _status = '';
  bool _caseSensitive = false;

  @override
  void initState() {
    super.initState();
    _loadAppProjects();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAppProjects() async {
    await FileService.ensureLayout();
    final dir = await FileService.projectsDirectory();
    setState(() {
      _folderPath = dir.path;
      _folderName = 'PROJECTS';
      _tree = FileService.buildTree(dir.path);
    });
  }

  void _refreshTree() {
    if (_folderPath.isEmpty) return;
    setState(() => _tree = FileService.buildTree(_folderPath));
  }

  Future<void> _newProject() async {
    final name = await _inputDialog('New Project', 'Project name', 'my-project');
    if (name == null || name.isEmpty) return;
    final path = await FileService.createProject(name);
    if (path == null) {
      _snack('Project "$name" already exists');
      return;
    }
    _openProjectRoot(path);
  }

  Future<void> _newFile() async {
    if (_folderPath.isEmpty) return;
    final name = await _inputDialog('New File', 'File name', 'main.dart');
    if (name == null || name.isEmpty) return;
    final path = await FileService.createFile(_folderPath, name);
    if (path == null) {
      _snack('File already exists');
      return;
    }
    _refreshTree();
    final result = await FileService.readFile(path);
    if (result != null) widget.onFileOpen(result['path']!, result['name']!, result['content']!);
  }

  Future<void> _importFile() async {
    final result = await FileService.importFile();
    if (result == null) return;
    widget.onFileOpen(result['path']!, result['name']!, result['content']!);
  }

  Future<void> _importFolder() async {
    final path = await FileService.importFolder();
    if (path == null) return;
    _openProjectRoot(path);
  }

  void _openProjectRoot(String path) {
    setState(() {
      _folderPath = path;
      _folderName = path.split('/').last.toUpperCase();
      _tree = FileService.buildTree(path);
    });
  }

  Future<String?> _inputDialog(String title, String label, String hint) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: VscodeTheme.bgSidebar,
        title: Text(title, style: const TextStyle(color: VscodeTheme.fg, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: const TextStyle(color: VscodeTheme.fgMuted),
          ),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Create', style: TextStyle(color: VscodeTheme.accent)),
          ),
        ],
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _onFileTap(FileNode node) async {
    final result = await FileService.readFile(node.path);
    if (result != null) {
      widget.onFileOpen(result['path']!, result['name']!, result['content']!);
    }
  }

  Future<void> _onNodeLongPress(FileNode node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: VscodeTheme.bgSidebar,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (node.isDir) ...[
            _sheetTile(Icons.note_add_outlined, 'New File', 'new_file'),
            _sheetTile(Icons.create_new_folder_outlined, 'New Folder', 'new_folder'),
          ],
          _sheetTile(Icons.drive_file_rename_outline, 'Rename', 'rename'),
          _sheetTile(Icons.delete_outline, 'Delete', 'delete', color: VscodeTheme.red),
        ],
      ),
    );
    if (action == null) return;

    if (action == 'new_file') {
      final name = await _inputDialog('New File', 'File name', 'main.dart');
      if (name == null || name.isEmpty) return;
      final path = await FileService.createFile(node.path, name);
      if (path != null) {
        _refreshTree();
        final result = await FileService.readFile(path);
        if (result != null) widget.onFileOpen(result['path']!, result['name']!, result['content']!);
      }
    } else if (action == 'new_folder') {
      final name = await _inputDialog('New Folder', 'Folder name', 'src');
      if (name == null || name.isEmpty) return;
      final dir = Directory('${node.path}/$name');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _refreshTree();
    } else if (action == 'rename') {
      final name = await _inputDialog('Rename', 'New name', node.name);
      if (name == null || name.isEmpty) return;
      await FileService.renameNode(node.path, name);
      _refreshTree();
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: VscodeTheme.bgSidebar,
          title: Text('Delete ${node.name}?', style: const TextStyle(color: VscodeTheme.fg)),
          content: const Text('This cannot be undone.', style: TextStyle(color: VscodeTheme.fgMuted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete', style: TextStyle(color: VscodeTheme.red)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      if (node.isDir) await FileService.deleteFolder(node.path);
      else await FileService.deleteFile(node.path);
      _refreshTree();
    }
  }

  ListTile _sheetTile(IconData icon, String label, String value, {Color? color}) {
    return ListTile(
      leading: Icon(icon, size: 18, color: color ?? VscodeTheme.fgMuted),
      title: Text(label, style: TextStyle(color: color ?? VscodeTheme.fg, fontSize: 13)),
      onTap: () => Navigator.pop(context, value),
    );
  }

  Future<void> _searchWorkspace() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty || _folderPath.isEmpty) return;
    setState(() {
      _searching = true;
      _status = 'Searching...';
    });
    final hits = await FileService.searchWorkspace(_folderPath, query, caseSensitive: _caseSensitive);
    setState(() {
      _searchResults = hits;
      _searching = false;
      _status = '${_searchResults.length} result(s)';
    });
  }

  Future<void> _openSearchHit(SearchResult hit) async {
    final result = await FileService.readFile(hit.path);
    if (result != null) {
      widget.onFileOpen(result['path']!, result['name']!, result['content']!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: VscodeTheme.bgSidebar,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final title = widget.activePanel == 'search'
        ? 'SEARCH'
        : widget.activePanel == 'extensions'
            ? 'EXTENSIONS'
            : 'EXPLORER';

    return Container(
      height: 35,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 11, color: VscodeTheme.fgLabel, letterSpacing: 1, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (widget.activePanel == 'explorer') ...[
            _iconBtn(Icons.create_new_folder_outlined, _newProject, 'New Project'),
            _iconBtn(Icons.note_add_outlined, _newFile, 'New File'),
            _iconBtn(Icons.file_download_outlined, _importFile, 'Import File'),
            _iconBtn(Icons.folder_open_outlined, _importFolder, 'Import Folder'),
          ] else if (widget.activePanel == 'search') ...[
            _iconBtn(Icons.search, _searchWorkspace, 'Search'),
          ],
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 15, color: VscodeTheme.fgMuted),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (widget.activePanel) {
      case 'search':
        return _buildSearch();
      case 'extensions':
        return _buildExtensions();
      default:
        return _buildExplorer();
    }
  }

  Widget _buildExplorer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _refreshTree,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.keyboard_arrow_down, size: 14, color: VscodeTheme.fgMuted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _folderName,
                    style: const TextStyle(fontSize: 11, color: VscodeTheme.fgLabel, letterSpacing: 0.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.refresh, size: 12, color: VscodeTheme.fgMuted),
              ],
            ),
          ),
        ),
        Expanded(
          child: _tree.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.folder_open, size: 40, color: VscodeTheme.fgMuted),
                      const SizedBox(height: 8),
                      const Text('No projects yet', style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _newProject,
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('New Project', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: FileTreeWidget(
                    nodes: _tree,
                    onFileTap: _onFileTap,
                    onLongPress: _onNodeLongPress,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(color: VscodeTheme.fg, fontSize: 13),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _searchWorkspace(),
            decoration: InputDecoration(
              hintText: 'Search in workspace',
              prefixIcon: const Icon(Icons.search, size: 16, color: VscodeTheme.fgMuted),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, size: 16, color: VscodeTheme.fgMuted),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() => _searchResults.clear());
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilterChip(
                label: const Text('Case'),
                selected: _caseSensitive,
                onSelected: (v) => setState(() => _caseSensitive = v),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _searchWorkspace,
                child: const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          if (_status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_status, style: const TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _searchResults.isEmpty
                ? const Center(
                    child: Text('Search workspace to show results', style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 12)),
                  )
                : ListView.builder(
                    itemCount: _searchResults.length,
                    itemBuilder: (_, i) {
                      final hit = _searchResults[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.search, size: 14, color: VscodeTheme.fgMuted),
                        title: Text(hit.fileName, style: const TextStyle(fontSize: 12, color: VscodeTheme.fg)),
                        subtitle: Text('Line ${hit.line}: ${hit.match}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: VscodeTheme.fgMuted)),
                        onTap: () => _openSearchHit(hit),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildExtensions() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.extension_outlined, size: 48, color: VscodeTheme.fgMuted),
          SizedBox(height: 12),
          Text('Open Marketplace', style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 13)),
          SizedBox(height: 4),
          Text('via the Extensions icon', style: TextStyle(color: VscodeTheme.fgMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
