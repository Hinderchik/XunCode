import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

class SearchResult {
  final String path;
  final String fileName;
  final int line;
  final String match;
  SearchResult({required this.path, required this.fileName, required this.line, required this.match});
}

class SearchQuery {
  final String text;
  final bool caseSensitive;
  SearchQuery({required this.text, this.caseSensitive = false});
}

class FileNode {
  final String name;
  final String path;
  final bool isDir;
  List<FileNode> children;
  bool expanded;

  FileNode({
    required this.name,
    required this.path,
    required this.isDir,
    this.children = const [],
    this.expanded = false,
  });
}

class FileService {
  // App's own data directory — always accessible, no permissions needed
  static Future<Directory> get appDataDir async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/projects');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  // Create a new project folder inside app data
  static Future<String?> createProject(String name) async {
    final base = await appDataDir;
    final dir = Directory('${base.path}/$name');
    if (dir.existsSync()) return null; // already exists
    dir.createSync(recursive: true);
    return dir.path;
  }

  // Create a new file inside a folder
  static Future<String?> createFile(String folderPath, String name) async {
    final file = File('$folderPath/$name');
    if (file.existsSync()) return null;
    file.createSync(recursive: true);
    return file.path;
  }

  // Read a file from disk directly (no picker)
  static Future<Map<String, String>?> readFile(String path) async {
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final content = await file.readAsString();
      return {'path': path, 'name': path.split('/').last, 'content': content};
    } catch (_) {
      return null;
    }
  }

  // Import a file from shared storage via picker
  static Future<Map<String, String>?> importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    if (file.path == null) return null;
    final content = await File(file.path!).readAsString();
    return {'path': file.path!, 'name': file.name, 'content': content};
  }

  // Import a folder from shared storage via picker
  static Future<String?> importFolder() async {
    return FilePicker.platform.getDirectoryPath();
  }

  static Future<void> saveFile(String path, String content) async {
    await File(path).writeAsString(content);
  }

  static Future<void> deleteFile(String path) async {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }

  static Future<void> deleteFolder(String path) async {
    final d = Directory(path);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  static Future<void> renameNode(String oldPath, String newName) async {
    final parent = File(oldPath).parent.path;
    final newPath = '$parent/$newName';
    final type = FileSystemEntity.typeSync(oldPath);
    if (type == FileSystemEntityType.file) {
      await File(oldPath).rename(newPath);
    } else {
      await Directory(oldPath).rename(newPath);
    }
  }

  static List<FileNode> buildTree(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return [];
    try {
      final entries = dir.listSync()
        ..sort((a, b) {
          final aIsDir = a is Directory;
          final bIsDir = b is Directory;
          if (aIsDir && !bIsDir) return -1;
          if (!aIsDir && bIsDir) return 1;
          return a.path.split('/').last.compareTo(b.path.split('/').last);
        });
      return entries.map((e) {
        final name = e.path.split('/').last;
        if (name.startsWith('.')) return null;
        if (e is Directory) {
          return FileNode(name: name, path: e.path, isDir: true, children: buildTree(e.path));
        }
        return FileNode(name: name, path: e.path, isDir: false);
      }).whereType<FileNode>().toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<SearchResult>> searchWorkspace(String root, String query,
      {bool caseSensitive = false}) async {
    final results = <SearchResult>[];
    if (query.trim().isEmpty) return results;
    final needle = caseSensitive ? query : query.toLowerCase();

    Future<void> walk(Directory dir) async {
      final children = dir.listSync();
      for (final entity in children) {
        final name = entity.path.split('/').last;
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          await walk(entity);
          continue;
        }
        try {
          final text = await File(entity.path).readAsString();
          final lines = const LineSplitter().convert(text);
          for (var i = 0; i < lines.length; i++) {
            final lineText = lines[i];
            final hay = caseSensitive ? lineText : lineText.toLowerCase();
            if (hay.contains(needle)) {
              results.add(SearchResult(
                path: entity.path,
                fileName: name,
                line: i + 1,
                match: lineText.trim(),
              ));
            }
          }
        } catch (_) {}
      }
    }

    final dir = Directory(root);
    if (dir.existsSync()) {
      await walk(dir);
    }
    return results;
  }
}
