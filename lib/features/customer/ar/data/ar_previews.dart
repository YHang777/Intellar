import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

// Saved AR previews (FR14): each capture lands as a PNG in the app documents
// folder with an index of its label and time, so the buyer can come back to
// them, share them, and put two side by side before deciding.
class ArPreview {
  const ArPreview({
    required this.id,
    required this.label,
    required this.path,
    required this.createdAt,
  });

  final String id;
  final String label;
  final String path;
  final DateTime createdAt;

  factory ArPreview.fromMap(Map<String, dynamic> map) => ArPreview(
        id: map['id']?.toString() ?? '',
        label: map['label']?.toString() ?? 'AR preview',
        path: map['path']?.toString() ?? '',
        createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'path': path,
        'createdAt': createdAt.toIso8601String(),
      };

  bool get exists => path.isNotEmpty && File(path).existsSync();
}

class ArPreviewStore {
  ArPreviewStore({Directory? root}) : _root = root;

  final Directory? _root;

  static const _dirName = 'ar_previews';
  static const _indexFile = 'index.json';

  Future<Directory> _base() async {
    final override = _root;
    if (override != null) {
      if (!override.existsSync()) override.createSync(recursive: true);
      return override;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_dirName');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  Future<List<ArPreview>> list() async {
    try {
      final dir = await _base();
      final idx = File('${dir.path}/$_indexFile');
      if (!idx.existsSync()) return const [];
      final raw = jsonDecode(await idx.readAsString());
      if (raw is! List) return const [];
      final previews = [
        for (final m in raw)
          if (m is Map<String, dynamic>) ArPreview.fromMap(m),
      ];
      previews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      // A row whose file is gone is noise, not history.
      return previews.where((p) => p.exists).toList();
    } catch (e) {
      debugPrint('[ar-previews] list failed: $e');
      return const [];
    }
  }

  Future<ArPreview> save(Uint8List png, {required String label}) async {
    final dir = await _base();
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final file = File('${dir.path}/$id.png');
    await file.writeAsBytes(png, flush: true);
    final preview = ArPreview(
      id: id,
      label: label.trim().isEmpty ? 'AR preview' : label.trim(),
      path: file.path,
      createdAt: DateTime.now(),
    );
    final existing = await list();
    await _writeIndex([preview, ...existing]);
    return preview;
  }

  Future<void> delete(String id) async {
    final all = await list();
    for (final p in all) {
      if (p.id == id) {
        try {
          File(p.path).deleteSync();
        } catch (_) {}
      }
    }
    await _writeIndex(all.where((p) => p.id != id).toList());
  }

  Future<void> _writeIndex(List<ArPreview> previews) async {
    final dir = await _base();
    final idx = File('${dir.path}/$_indexFile');
    await idx.writeAsString(
        jsonEncode([for (final p in previews) p.toMap()]),
        flush: true);
  }

  Future<void> share(ArPreview preview) async {
    if (!preview.exists) {
      throw const FileSystemException('That preview is no longer on this device.');
    }
    await SharePlus.instance.share(
      ShareParams(files: [XFile(preview.path)], text: preview.label),
    );
  }
}
