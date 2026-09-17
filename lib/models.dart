// 数据模型：文件夹 / 课文 / 书单，JSON 持久化
import 'dart:convert';

/// 文件夹（分类容器，可放课文，也可放书单）
class Folder {
  final String id;
  String name;

  Folder({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Folder.fromJson(Map<String, dynamic> j) =>
      Folder(id: j['id'] as String, name: j['name'] as String);
}

/// 一篇课文（含文本、音色、语速、音频路径）
class ReciteText {
  final String id;
  String? folderId; // null = 未分类
  String title;
  String content;
  String voice;
  String voiceName;
  String rate;
  String? audioPath; // 单文件音频；null = 尚未生成或走分块
  List<String>? audioChunks; // 长文本分块音频（逐块 mp3 路径）；非空时优先于 audioPath
  DateTime createdAt;

  ReciteText({
    required this.id,
    this.folderId,
    required this.title,
    required this.content,
    required this.voice,
    required this.voiceName,
    required this.rate,
    this.audioPath,
    this.audioChunks,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'folderId': folderId,
        'title': title,
        'content': content,
        'voice': voice,
        'voiceName': voiceName,
        'rate': rate,
        'audioPath': audioPath,
        'audioChunks': audioChunks,
        'createdAt': createdAt.toIso8601String(),
      };

  factory ReciteText.fromJson(Map<String, dynamic> j) => ReciteText(
        id: j['id'] as String,
        folderId: j['folderId'] as String?,
        title: j['title'] as String,
        content: j['content'] as String,
        voice: j['voice'] as String,
        voiceName: j['voiceName'] as String,
        rate: j['rate'] as String,
        audioPath: j['audioPath'] as String?,
        audioChunks: (j['audioChunks'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList()
            .let((l) => l.isEmpty ? null : l),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// 书单：独立播放列表，可放文件夹；textIds 按顺序播放
class Playlist {
  final String id;
  String name;
  String? folderId; // null = 独立（不进文件夹）
  List<String> textIds;

  Playlist({required this.id, this.folderId, required this.name, List<String>? textIds})
      : textIds = textIds ?? [];

  Map<String, dynamic> toJson() =>
      {'id': id, 'folderId': folderId, 'name': name, 'textIds': textIds};

  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
        id: j['id'] as String,
        folderId: j['folderId'] as String?,
        name: j['name'] as String,
        textIds: (j['textIds'] as List<dynamic>? ?? []).cast<String>(),
      );
}

/// 全量数据
class AppData {
  List<Folder> folders;
  List<ReciteText> texts;
  List<Playlist> playlists;

  AppData({List<Folder>? folders, List<ReciteText>? texts, List<Playlist>? playlists})
      : folders = folders ?? [],
        texts = texts ?? [],
        playlists = playlists ?? [];

  Map<String, dynamic> toJson() => {
        'folders': folders.map((f) => f.toJson()).toList(),
        'texts': texts.map((t) => t.toJson()).toList(),
        'playlists': playlists.map((p) => p.toJson()).toList(),
      };

  factory AppData.fromJson(Map<String, dynamic> j) => AppData(
        folders: (j['folders'] as List<dynamic>? ?? [])
            .map((e) => Folder.fromJson(e as Map<String, dynamic>))
            .toList(),
        texts: (j['texts'] as List<dynamic>? ?? [])
            .map((e) => ReciteText.fromJson(e as Map<String, dynamic>))
            .toList(),
        playlists: (j['playlists'] as List<dynamic>? ?? [])
            .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  String encode() => jsonEncode(toJson());
}
