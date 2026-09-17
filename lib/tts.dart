// 语音合成工具（edge_tts 免费接口 + 限流重试）
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:edge_tts/edge_tts.dart';
import 'package:path_provider/path_provider.dart';

/// 可用音色（一期 3 个，试听已确认）
class VoiceOption {
  final String code;
  final String name;
  const VoiceOption(this.code, this.name);
}

const List<VoiceOption> kVoices = [
  VoiceOption('zh-CN-XiaoxiaoNeural', '晓晓 · 温柔女声'),
  VoiceOption('zh-CN-XiaoyiNeural', '晓伊 · 明亮女声'),
  VoiceOption('zh-CN-YunxiNeural', '云希 · 少年男声'),
];

/// 默认音色：晓晓
final VoiceOption kDefaultVoice = kVoices[0];
/// 生成统一用正常语速：语速调节已改为播放时变速（方案 A），
/// 生成参数固定为 0%，避免与播放变速叠加
const String kDefaultRate = '0%';

/// 语速滑动条范围（%）：-30% ~ +30%，播放时变速映射 speed = 1 + pct/100
const int kSpeedMinPct = -30;
const int kSpeedMaxPct = 30;

/// 音频缓存目录
Future<Directory> audioCacheDir() async {
  final dir = await getApplicationDocumentsDirectory();
  final folder = Directory('${dir.path}/sleep_recite_audio');
  if (!await folder.exists()) await folder.create(recursive: true);
  return folder;
}

/// 按 文本+音色+语速 计算音频缓存路径（同参数复用）
Future<String> audioPathFor(String text, String voice, String rate) async {
  final dir = await audioCacheDir();
  final hash = sha256
      .convert(utf8.encode('$text|$voice|$rate'))
      .toString()
      .substring(0, 20);
  return '${dir.path}/$hash.mp3';
}

/// 生成音频：含 5 次指数退避重试；返回是否成功
/// onStatus: 进度回调（如"第 2 次重试"）
Future<bool> synthesize(
  String text,
  String voice,
  String rate,
  String outPath, {
  void Function(String)? onStatus,
}) async {
  const maxAttempts = 5;
  for (int i = 1; i <= maxAttempts; i++) {
    try {
      final comm = Communicate(text: text, voice: voice, rate: rate);
      await comm.save(outPath);
      final f = File(outPath);
      if (await f.exists() && await f.length() > 2000) {
        return true; // 有效音频
      }
      if (await f.exists()) await f.delete();
      throw const FileSystemException('empty audio');
    } catch (e) {
      if (i < maxAttempts) {
        onStatus?.call('语音服务繁忙（微软接口偶发限流），第 $i 次重试…');
        await Future<void>.delayed(Duration(seconds: 3 * i));
      }
    }
  }
  return false;
}

/// 长文本切块：按句末标点（。！？；…）切分，每块不超过 [maxLen] 字。
/// 用于分块合成（防超长截断）与"听背听"逐句留白。
List<String> splitTextForTts(String text, {int maxLen = 400}) {
  final sentences = <String>[];
  final buf = StringBuffer();
  for (final rune in text.runes) {
    final ch = String.fromCharCode(rune);
    buf.write(ch);
    if ('.。!！?？;；…\n'.contains(ch) && buf.length >= 10) {
      sentences.add(buf.toString());
      buf.clear();
    }
  }
  if (buf.isNotEmpty) sentences.add(buf.toString());
  // 合并过短句为 ≤ maxLen 的块
  final chunks = <String>[];
  var cur = StringBuffer();
  for (final s in sentences) {
    if (cur.length + s.length > maxLen && cur.isNotEmpty) {
      chunks.add(cur.toString());
      cur.clear();
    }
    cur.write(s);
  }
  if (cur.isNotEmpty) chunks.add(cur.toString());
  return chunks.isEmpty ? [text] : chunks;
}

/// 是否已生成有效的单文件音频
bool audioFileValid(String path) {
  try {
    return File(path).existsSync() && File(path).lengthSync() > 2000;
  } catch (_) {
    return false;
  }
}

/// 分块音频缓存路径：hash_c{i}.mp3（同一课文各块共用 hash 前缀）
Future<String> chunkPathFor(String text, String voice, String rate, int i) async {
  final dir = await audioCacheDir();
  final hash = sha256
      .convert(utf8.encode('$text|$voice|$rate'))
      .toString()
      .substring(0, 20);
  return '${dir.path}/${hash}_c$i.mp3';
}

/// 分块合成：切块 → 逐块生成（已存在的块自动跳过，天然断点续传）。
/// 全部成功返回分块路径列表；任何一块 5 次重试后仍失败则返回 null。
Future<List<String>?> synthesizeChunks(
  String text,
  String voice,
  String rate, {
  void Function(int done, int total, String? status)? onProgress,
}) async {
  final chunks = splitTextForTts(text);
  final paths = <String>[];
  final total = chunks.length;
  for (var i = 0; i < total; i++) {
    final p = await chunkPathFor(text, voice, rate, i);
    if (audioFileValid(p)) {
      paths.add(p);
      onProgress?.call(i + 1, total, null);
      continue;
    }
    var ok = false;
    await synthesize(chunks[i], voice, rate, p,
        onStatus: (s) => onProgress?.call(i + 1, total, s));
    ok = audioFileValid(p);
    if (!ok) {
      onProgress?.call(i + 1, total, '第 ${i + 1}/$total 段失败');
      return null;
    }
    paths.add(p);
    onProgress?.call(i + 1, total, null);
  }
  return paths;
}
