// 书单页：书单列表 / 新建 / 详情（添加课文、顺序连播）
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models.dart';
import '../player_holder.dart';
import '../store.dart';
import '../tts.dart';
import 'player_page.dart';

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.inst,
      builder: (context, _) {
        final store = AppStore.inst;
        return Scaffold(
          appBar: AppBar(
            title: const Text('书单'),
            centerTitle: true,
            backgroundColor: Colors.transparent,
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _newPlaylist(context),
            icon: const Icon(Icons.add),
            label: const Text('新建书单'),
          ),
          body: store.data.playlists.isEmpty
              ? const Center(
                  child: Text('还没有书单', style: TextStyle(color: Color(0xFF94A3B8))),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    for (final p in store.data.playlists)
                      _PlaylistTile(
                        playlist: p,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PlaylistDetailPage(playlist: p),
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _newPlaylist(BuildContext context) async {
    final store = AppStore.inst;
    final nameCtrl = TextEditingController();
    String? folderId;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('新建书单'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(hintText: '书单名，如：睡前必背'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: folderId,
                decoration: const InputDecoration(
                  hintText: '放进文件夹（可选）',
                  filled: true,
                  fillColor: Color(0xFF1E293B),
                ),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('不放进文件夹')),
                  ...store.data.folders.map(
                    (f) => DropdownMenuItem<String?>(value: f.id, child: Text(f.name)),
                  ),
                ],
                onChanged: (v) => setSt(() => folderId = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (name != null && name.isNotEmpty) {
      AppStore.inst.addPlaylist(name, folderId: folderId);
    }
  }
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final VoidCallback onTap;

  const _PlaylistTile({required this.playlist, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final store = AppStore.inst;
    final count = playlist.textIds.length;
    final folderName =
        playlist.folderId == null ? null : store.data.folders.where((f) => f.id == playlist.folderId).firstOrNull?.name;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF2DD4BF).withValues(alpha: 0.15),
          child: const Icon(Icons.queue_music, color: Color(0xFF2DD4BF)),
        ),
        title: Text(playlist.name, style: const TextStyle(fontSize: 16)),
        subtitle: Text(
          '$count 篇${folderName != null ? ' · $folderName' : ''}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'rename') _rename(context);
            if (v == 'delete') _delete(context);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  void _rename(BuildContext context) {
    final ctrl = TextEditingController(text: playlist.name);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名书单'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((n) {
      if (n != null && n.isNotEmpty) AppStore.inst.renamePlaylist(playlist.id, n);
    });
  }

  void _delete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除书单「${playlist.name}」？'),
        content: const Text('书单里的课文不会被删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) AppStore.inst.deletePlaylist(playlist.id);
    });
  }
}

/// 书单详情：课文列表 + 播放 + 添加/移除
class PlaylistDetailPage extends StatelessWidget {
  final Playlist playlist;

  const PlaylistDetailPage({super.key, required this.playlist});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.inst,
      builder: (context, _) {
        final store = AppStore.inst;
        final texts = playlist.textIds
            .map((id) => store.textById(id))
            .whereType<ReciteText>()
            .toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                onPressed: () => _addTexts(context, store),
                tooltip: '添加课文',
                icon: const Icon(Icons.library_add_outlined),
              ),
            ],
          ),
          body: texts.isEmpty
              ? Center(
                  child: Text(
                    '书单是空的，点右上角添加课文',
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  children: [
                    FilledButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlayerQueuePage(texts: texts, playlistName: playlist.name),
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 26),
                      label: Text('播放书单（${texts.length} 篇）'),
                    ),
                    const SizedBox(height: 16),
                    for (final t in texts)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: const Color(0xFF1E293B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => PlayerPage(text: t)),
                          ),
                          leading: Icon(
                            t.audioPath == null ? Icons.schedule : Icons.volume_up,
                            color: t.audioPath == null
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF2DD4BF),
                          ),
                          title: Text(t.title,
                              style: const TextStyle(fontSize: 15),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${t.voiceName} · ${t.rate}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: Color(0xFF64748B)),
                            onPressed: () {
                              store.playlistSetTexts(
                                playlist.id,
                                playlist.textIds.where((id) => id != t.id).toList(),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _addTexts(BuildContext context, AppStore store) async {
    final all = store.data.texts;
    final picked = <String>[];
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('选择要添加的课文'),
          content: SizedBox(
            width: 320,
            height: 360,
            child: all.isEmpty
                ? const Center(child: Text('还没有课文，先去「课文」页新建'))
                : ListView(
                    children: [
                      for (final t in all)
                        CheckboxListTile(
                          value: picked.contains(t.id),
                          title: Text(t.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(t.voiceName,
                              style: const TextStyle(fontSize: 12)),
                          onChanged: (v) => setSt(() {
                            if (v == true) {
                              picked.add(t.id);
                            } else {
                              picked.remove(t.id);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, picked),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty) {
      store.playlistSetTexts(playlist.id, [...playlist.textIds, ...result]);
    }
  }
}

/// 书单顺序连播：播完一篇自动下一篇
class PlayerQueuePage extends StatefulWidget {
  final List<ReciteText> texts;
  final String playlistName;

  const PlayerQueuePage({super.key, required this.texts, required this.playlistName});

  @override
  State<PlayerQueuePage> createState() => _PlayerQueuePageState();
}

class _PlayerQueuePageState extends State<PlayerQueuePage> {
  // 全局唯一播放器（后台播放/锁屏控制/媒体通知）
  final AudioPlayer _player = PlayerHolder.player;
  int _index = 0;
  // 语速滑动条（-30% ~ +30%，播放时变速）
  int _speedPct = 0;
  bool _playing = false;
  String _status = '';
  String _progress = '';
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  List<ReciteText> get _queue => widget.texts;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _player.processingStateStream.listen((s) {
      if (!mounted) return;
      if (s == ProcessingState.completed) _next(auto: true);
    });
    _player.playerStateStream.listen((ps) {
      if (mounted) setState(() => _playing = ps.playing);
    });
    _playCurrent();
  }

  @override
  void dispose() {
    // 全局播放器不在此销毁：切走页面时播放继续
    super.dispose();
  }

  ReciteText? get _current => _index < _queue.length ? _queue[_index] : null;

  /// 课文的有效音频路径列表（分块优先；单文件返回单元素）
  List<String>? _pathsOf(ReciteText t) {
    final chunks = t.audioChunks;
    if (chunks != null && chunks.isNotEmpty && chunks.every((p) => File(p).existsSync())) {
      return chunks;
    }
    if (t.audioPath != null && File(t.audioPath!).existsSync()) {
      return [t.audioPath!];
    }
    return null;
  }

  Future<void> _playCurrent() async {
    final t = _current;
    if (t == null) {
      setState(() => _status = '播放结束');
      return;
    }
    final paths = _pathsOf(t);
    if (paths == null) {
      setState(() {
        _status = '《${t.title}》还没有语音，已跳过（去课文里生成后可重播）';
      });
      _next(auto: true);
      return;
    }
    setState(() => _status = '正在播放：${t.title}');
    await _player.stop();
    await _player.setSpeed(1.0 + _speedPct / 100.0);
    try {
      final tag = MediaItem(
        id: t.id,
        title: t.title,
        artist: '${t.voiceName} · ${t.rate}',
      );
      if (paths.length == 1) {
        await _player.setAudioSource(AudioSource.uri(Uri.file(paths.first), tag: tag));
      } else {
        await _player.setAudioSources(
          paths.map((p) => AudioSource.uri(Uri.file(p), tag: tag)).toList(),
        );
      }
      await _player.play();
    } catch (e) {
      setState(() => _status = '播放失败：$e');
      _next(auto: true);
    }
  }

  Future<void> _next({bool auto = false}) async {
    if (_index < _queue.length - 1) {
      setState(() => _index += 1);
      await _playCurrent();
    } else {
      if (auto) {
        setState(() => _status = '书单播放完毕');
      } else {
        setState(() => _status = '已经是最后一篇');
      }
    }
  }

  Future<void> _prev() async {
    if (_index > 0) {
      setState(() => _index -= 1);
      await _playCurrent();
    }
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<void> _stopAll() async {
    await _player.stop();
    setState(() {
      _status = '已停止';
      _progress = '';
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final t = _current;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlistName, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                '${_index + 1} / ${_queue.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 8),
              Text(
                t?.title ?? '—',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                t == null ? '' : '${t.voiceName} · ${t.rate}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: _prev,
                          iconSize: 36,
                          icon: const Icon(Icons.skip_previous_rounded),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _playing ? _toggle : null,
                          iconSize: 44,
                          icon: const Icon(Icons.pause_circle_filled),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _playing ? null : _toggle,
                          iconSize: 44,
                          icon: const Icon(Icons.play_circle_filled),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _next,
                          iconSize: 36,
                          icon: const Icon(Icons.skip_next_rounded),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          onPressed: _stopAll,
                          iconSize: 36,
                          icon: const Icon(Icons.stop_circle_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _progress.isEmpty
                          ? '${_fmt(_position)} / ${_fmt(_duration)}'
                          : _progress,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // 语速：播放时变速，即时生效；±10% 步进
              Row(
                children: [
                  const Icon(Icons.speed, size: 20, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  const Text('语速', style: TextStyle(fontSize: 14, color: Color(0xFFCBD5E1))),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _speedPct > kSpeedMinPct
                        ? () {
                            setState(() => _speedPct -= 10);
                            _player.setSpeed(1.0 + _speedPct / 100.0);
                          }
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: '减 10%',
                  ),
                  Expanded(
                    child: Slider(
                      value: _speedPct.toDouble(),
                      min: kSpeedMinPct.toDouble(),
                      max: kSpeedMaxPct.toDouble(),
                      divisions: 12,
                      onChanged: (v) {
                        setState(() => _speedPct = v.round());
                        _player.setSpeed(1.0 + _speedPct / 100.0);
                      },
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _speedPct < kSpeedMaxPct
                        ? () {
                            setState(() => _speedPct += 10);
                            _player.setSpeed(1.0 + _speedPct / 100.0);
                          }
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: '加 10%',
                  ),
                  SizedBox(
                    width: 52,
                    child: Text(
                      '$_speedPct%',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2DD4BF),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
