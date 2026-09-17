// 本地 JSON 存储 + 全局状态（ChangeNotifier）
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class AppStore extends ChangeNotifier {
  AppStore._();
  static final AppStore inst = AppStore._();

  AppData data = AppData();
  bool loaded = false;
  String _dataFilePath = '';

  /// 文档目录下的数据文件
  static Future<String> dataFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/sleep_recite_data.json';
  }

  /// 文档目录下的音频目录
  static Future<String> audioDirPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/sleep_recite_audio';
  }

  Future<void> load() async {
    try {
      _dataFilePath = await dataFilePath();
      final f = File(_dataFilePath);
      if (await f.exists()) {
        final raw = await f.readAsString();
        final j = jsonDecode(raw) as Map<String, dynamic>;
        data = AppData.fromJson(j);
      }
    } catch (e) {
      debugPrint('AppStore.load error: $e');
      data = AppData();
    }
    loaded = true;
    notifyListeners();
  }

  Future<void> save() async {
    try {
      _dataFilePath = await dataFilePath();
      final f = File(_dataFilePath);
      await f.writeAsString(data.encode(), flush: true);
    } catch (e) {
      debugPrint('AppStore.save error: $e');
    }
    notifyListeners();
  }

  // ---- CRUD ----
  Folder addFolder(String name) {
    final f = Folder(id: _newId('f'), name: name);
    data.folders.add(f);
    save();
    return f;
  }

  void renameFolder(String id, String name) {
    final f = _folder(id);
    if (f != null) {
      f.name = name;
      save();
    }
  }

  void deleteFolder(String id) {
    data.folders.removeWhere((f) => f.id == id);
    // 文件夹内的课文与书单变为未分类
    for (final t in data.texts) {
      if (t.folderId == id) t.folderId = null;
    }
    for (final p in data.playlists) {
      if (p.folderId == id) p.folderId = null;
    }
    save();
  }

  ReciteText addText(ReciteText t) {
    data.texts.add(t);
    save();
    return t;
  }

  void updateText(ReciteText t) {
    final i = data.texts.indexWhere((x) => x.id == t.id);
    if (i >= 0) {
      _cleanupOrphanedAudio(data.texts[i], t);
      data.texts[i] = t;
    }
    save();
  }

  void deleteText(String id) {
    final i = data.texts.indexWhere((t) => t.id == id);
    if (i >= 0) {
      _cleanupOrphanedAudio(data.texts[i], null);
      data.texts.removeAt(i);
    }
    for (final p in data.playlists) {
      p.textIds.remove(id);
    }
    save();
  }

  /// 编辑/删除后清理旧音频：内容/音色变化导致路径变化时，若旧音频不再被
  /// 任何课文引用，则删除文件（防止 sleep_recite_audio/ 存储爆炸）。
  void _cleanupOrphanedAudio(ReciteText old, ReciteText? next) {
    final oldPaths = <String>{
      if (old.audioPath != null) old.audioPath!,
      ...?old.audioChunks,
    };
    final nextPaths = <String>{
      if (next != null) ...?next.audioChunks,
      if (next?.audioPath != null) next!.audioPath!,
    };
    final stillUsed = <String>{};
    for (final t in data.texts) {
      if (t.id == old.id) continue;
      if (t.audioPath != null) stillUsed.add(t.audioPath!);
      stillUsed.addAll(t.audioChunks ?? const []);
    }
    for (final p in oldPaths.difference(nextPaths)) {
      if (stillUsed.contains(p)) continue;
      try {
        final f = File(p);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {
        // 文件不存在或删除失败：忽略，交给缓存清理兜底
      }
    }
  }

  Playlist addPlaylist(String name, {String? folderId}) {
    final p = Playlist(id: _newId('p'), name: name, folderId: folderId);
    data.playlists.add(p);
    save();
    return p;
  }

  void renamePlaylist(String id, String name) {
    final p = _playlist(id);
    if (p != null) {
      p.name = name;
      save();
    }
  }

  void deletePlaylist(String id) {
    data.playlists.removeWhere((p) => p.id == id);
    save();
  }

  void playlistSetTexts(String id, List<String> textIds) {
    final p = _playlist(id);
    if (p != null) {
      p.textIds = List.of(textIds);
      save();
    }
  }

  // ---- helpers ----
  Folder? _folder(String id) {
    for (final f in data.folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  Playlist? _playlist(String id) {
    for (final p in data.playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  ReciteText? textById(String id) {
    for (final t in data.texts) {
      if (t.id == id) return t;
    }
    return null;
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}
