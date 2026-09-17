// 播放页：单篇课文 循环N遍 / 定时停止(倒计时+准时结束) / 听背听
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models.dart';
import '../player_holder.dart';
import '../store.dart';
import '../tts.dart';

enum PlayMode { loopCount, timer, listenRepeat }
enum TimerStyle { countdown, absolute }

/// 准时结束的候选时间（今天，若已过则顺延到明天）
const List<Duration> kAbsoluteTargets = [
  Duration(hours: 22, minutes: 30),
  Duration(hours: 23, minutes: 0),
  Duration(hours: 23, minutes: 30),
];
/// 听背听留白比例（% of 朗读时长）
const List<int> kGapPercents = [50, 60, 80, 100];

class PlayerPage extends StatefulWidget {
  final ReciteText text;

  const PlayerPage({super.key, required this.text});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late ReciteText _text;
  // 全局唯一播放器（后台播放/锁屏控制/媒体通知）
  final AudioPlayer _player = PlayerHolder.player;

  PlayMode _mode = PlayMode.loopCount;
  TimerStyle _timerStyle = TimerStyle.countdown;
  int _loopCount = 3;
  int _timerMinutes = 30;
  int _gapPercent = 60; // 听背听留白比例
  // 语速滑动条（-30% ~ +30%，播放时变速，即时生效）
  int _speedPct = 0;
  bool _generating = false;
  double? _generateProgress; // 分块合成进度 0~1
  bool _playing = false;
  String _status = '';
  String _progress = '';
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  Timer? _sleepTimer;
  Timer? _tickTimer; // 剩余时间每秒刷新
  int _completedCount = 0;
  bool _keepLooping = false;

  // 听背听：逐块播放状态
  List<String> _chunks = const [];
  int _chunkIndex = 0;
  bool _inGap = false;
  Timer? _gapTimer;

  @override
  void initState() {
    super.initState();
    _text = widget.text;
    _chunks = _text.audioChunks ?? const [];
    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });
    _player.durationStream.listen((d) {
      if (mounted && d != null) setState(() => _duration = d);
    });
    _player.processingStateStream.listen((state) {
      if (!mounted) return;
      if (state == ProcessingState.completed) _onTrackCompleted();
    });
    _player.playerStateStream.listen((ps) {
      if (mounted) {
        setState(() => _playing = ps.playing);
        _updateProgress();
      }
    });
    _status = !_hasAudio ? '还没有语音，先点「生成语音」' : '就绪';
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _tickTimer?.cancel();
    _gapTimer?.cancel();
    // 全局播放器不在此销毁：离开页面时播放继续，交给媒体通知/锁屏控制
    super.dispose();
  }

  bool get _hasAudio {
    if (_chunks.isNotEmpty) {
      return _chunks.every((p) => File(p).existsSync());
    }
    return _text.audioPath != null && File(_text.audioPath!).existsSync();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _absoluteLabel {
    if (_timerStyle != TimerStyle.absolute || _targetTime == null) return '';
    final t = _targetTime!;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  DateTime? _targetTime;

  String get _timeLeftText {
    if (_targetTime == null) return '';
    final remain = _targetTime!.difference(DateTime.now());
    if (remain.isNegative) return '';
    final min = remain.inMinutes;
    if (min <= 0) return '距 $_absoluteLabel 不到 1 分钟';
    return '距 $_absoluteLabel 还有 $min 分钟';
  }

  void _updateProgress() {
    if (_mode == PlayMode.loopCount) {
      _progress =
          '${_fmt(_position)} / ${_fmt(_duration)} · 第 $_completedCount/$_loopCount 遍';
    } else if (_mode == PlayMode.timer) {
      _progress = _timerStyle == TimerStyle.absolute
          ? '${_fmt(_position)} / ${_fmt(_duration)} · $_timeLeftText'
          : '${_fmt(_position)} / ${_fmt(_duration)} · 定时 $_timerMinutes 分钟';
    } else {
      _progress = _inGap
          ? '听-背-听 · 留白中（背一遍…）'
          : '${_fmt(_position)} / ${_fmt(_duration)} · 听-背-听 第 $_completedCount/$_loopCount 遍';
    }
  }

  double _speedFromPct(int pct) => 1.0 + pct / 100.0;

  void _onSpeedChanged(int pct) {
    setState(() => _speedPct = pct);
    _player.setSpeed(_speedFromPct(pct)); // 播放中即时变速
  }

  void _stepSpeed(int delta) {
    _onSpeedChanged((_speedPct + delta).clamp(kSpeedMinPct, kSpeedMaxPct));
  }

  // ---- 生成（单文件或分块） ----
  Future<void> _ensureAudioAndPlay() async {
    FocusScope.of(context).unfocus();
    // 已有有效音频 → 直接播放
    if (_hasAudio) {
      setState(() => _status = '开始播放');
      await _startPlayback();
      return;
    }
    setState(() {
      _generating = true;
      _generateProgress = null;
      _status = '正在生成语音（${_text.voiceName}）…';
    });
    // 长文本（>1 句）走分块合成：天然断点续传（已存在的块自动跳过）
    if (splitTextForTts(_text.content).length > 1) {
      final chunks = await synthesizeChunks(
        _text.content,
        _text.voice,
        _text.rate,
        onProgress: (done, total, status) {
          if (!mounted) return;
          setState(() {
            _generateProgress = done / total;
            if (status != null) _status = status;
          });
        },
      );
      if (chunks == null || chunks.isEmpty) {
        if (mounted) {
          setState(() {
            _generating = false;
            _generateProgress = null;
            _status = '生成失败：网络异常或语音服务繁忙，请稍后再试';
          });
        }
        return;
      }
      _text.audioPath = null;
      _text.audioChunks = chunks;
      AppStore.inst.updateText(_text);
      _chunks = chunks;
      if (mounted) {
        setState(() {
          _generating = false;
          _generateProgress = null;
          _status = '已生成 ${chunks.length} 段，开始播放';
        });
        await _startPlayback();
      }
      return;
    }
    // 短文本 → 单文件
    final outPath = await audioPathFor(_text.content, _text.voice, _text.rate);
    final ok = await synthesize(_text.content, _text.voice, _text.rate, outPath,
        onStatus: (s) {
      if (mounted) setState(() => _status = s);
    });
    if (!ok) {
      if (mounted) {
        setState(() {
          _generating = false;
          _generateProgress = null;
          _status = '生成失败：网络异常或语音服务繁忙，请稍后再试';
        });
      }
      return;
    }
    _text.audioPath = outPath;
    _text.audioChunks = null;
    _chunks = const [];
    AppStore.inst.updateText(_text);
    if (mounted) {
      setState(() {
        _generating = false;
        _generateProgress = null;
        _status = '已生成，开始播放';
      });
      await _startPlayback();
    }
  }

  // ---- 播放 ----
  Future<void> _startPlayback() async {
    _stopTimers();
    _gapTimer?.cancel();
    if (mounted) setState(() => _status = '开始播放');
    await _player.stop();
    await _player.setVolume(1.0);
    await _player.setSpeed(_speedFromPct(_speedPct));
    _keepLooping = true;
    _completedCount = 0;
    if (_mode == PlayMode.timer) {
      if (_timerStyle == TimerStyle.absolute) {
        _startAbsoluteTimer();
      } else {
        _startCountdownTimer(_timerMinutes);
      }
    }
    final paths = _chunks.isNotEmpty ? _chunks : [_text.audioPath!];
    if (_mode == PlayMode.listenRepeat) {
      if (paths.length < 2) {
        // 短文本无分块：退化为普通循环（提示一句）
        _mode = PlayMode.loopCount;
      } else {
        _chunkIndex = 0;
        await _playChunk(0);
        return;
      }
    }
    await _setSource(paths);
    await _player.play();
  }

  Future<void> _setSource(List<String> paths) async {
    final tag = MediaItem(
      id: _text.id,
      title: _text.title,
      artist: '${_text.voiceName} · ${_text.rate}',
    );
    try {
      if (paths.length == 1) {
        await _player.setAudioSource(AudioSource.uri(Uri.file(paths.first), tag: tag));
      } else {
        // 分块无缝连播（新版 just_audio 推荐 setAudioSources）
        await _player.setAudioSources(
          paths.map((p) => AudioSource.uri(Uri.file(p), tag: tag)).toList(),
        );
      }
    } catch (e) {
      setState(() => _status = '播放失败：$e');
    }
  }

  // 听背听：逐块播放 + 留白
  Future<void> _playChunk(int i) async {
    if (i >= _chunks.length) return;
    _chunkIndex = i;
    await _setSource([_chunks[i]]);
    await _player.play();
  }

  void _onTrackCompleted() {
    if (!_keepLooping) return;
    if (_mode == PlayMode.listenRepeat) {
      // 当前块播完 → 留白 → 下一块 / 整篇结束
      final gap = Duration(
          milliseconds: (_duration.inMilliseconds * _gapPercent / 100).round());
      if (_chunkIndex < _chunks.length - 1) {
        setState(() {
          _inGap = true;
          _status = '留白 ${gap.inSeconds + 1} 秒，自己背一遍…';
        });
        _gapTimer?.cancel();
        _gapTimer = Timer(gap, () async {
          if (!mounted || !_keepLooping) return;
          setState(() {
            _inGap = false;
            _status = '开始播放';
          });
          await _playChunk(_chunkIndex + 1);
        });
      } else {
        _completedCount += 1;
        if (_completedCount >= _loopCount) {
          _keepLooping = false;
          _player.pause();
          setState(() {
            _status = '听背听完成，已循环 $_loopCount 遍';
            _updateProgress();
          });
          return;
        }
        setState(() => _inGap = true);
        _gapTimer?.cancel();
        _gapTimer = Timer(gap, () async {
          if (!mounted || !_keepLooping) return;
          setState(() => _inGap = false);
          await _playChunk(0);
        });
      }
      setState(_updateProgress);
      return;
    }
    // 普通 / 连播模式
    if (_mode == PlayMode.loopCount) {
      _completedCount += 1;
      if (_completedCount >= _loopCount) {
        _keepLooping = false;
        _player.pause();
        setState(() {
          _status = '已循环 $_loopCount 遍，播放结束';
          _updateProgress();
        });
        return;
      }
    }
    setState(_updateProgress);
    _player.seek(Duration.zero);
    _player.play();
  }

  // ---- 定时 ----
  void _startCountdownTimer(int minutes) {
    final totalSec = minutes * 60;
    const fadeSec = 30;
    _sleepTimer = Timer(Duration(seconds: totalSec - fadeSec), _fadeOutAndStop);
  }

  void _startAbsoluteTimer() {
    // 选择目标时已确保 _targetTime 是未来时间
    final remain = _targetTime!.difference(DateTime.now());
    final remainSec = remain.inSeconds;
    _startTick();
    if (remainSec <= 30) {
      _sleepTimer = Timer(Duration.zero, _fadeOutAndStop);
      return;
    }
    _sleepTimer = Timer(Duration(seconds: remainSec - 30), _fadeOutAndStop);
  }

  void _startTick() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_updateProgress);
    });
  }

  void _selectAbsoluteTarget(int minutesOfDay) {
    var target = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      minutesOfDay ~/ 60,
      minutesOfDay % 60,
    );
    if (!target.isAfter(DateTime.now())) {
      target = target.add(const Duration(days: 1));
    }
    setState(() => _targetTime = target);
    // 保存当前选择供 UI 高亮
    _selectedAbsolute = minutesOfDay;
  }

  int? _selectedAbsolute;

  Future<void> _fadeOutAndStop() async {
    _tickTimer?.cancel();
    for (double v = 1.0; v > 0.0; v -= 0.08) {
      if (!mounted) return;
      await _player.setVolume(v.clamp(0.0, 1.0));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    _keepLooping = false;
    await _player.pause();
    await _player.setVolume(1.0);
    if (mounted) {
      setState(() {
        _status = _timerStyle == TimerStyle.absolute
            ? '$_absoluteLabel 已到，已渐弱停止'
            : '定时 $_timerMinutes 分钟到，已渐弱停止';
        _updateProgress();
      });
    }
  }

  void _stopTimers() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;
  }

  // ---- 控制 ----
  Future<void> _togglePlayPause() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    // 听背听：留白等待中点继续 → 跳过剩余留白直接播下一块
    if (_mode == PlayMode.listenRepeat && _inGap) {
      _gapTimer?.cancel();
      setState(() => _inGap = false);
      await _playChunk(_chunkIndex + 1 < _chunks.length ? _chunkIndex + 1 : 0);
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      _completedCount = 0;
      _keepLooping = true;
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  Future<void> _stop() async {
    _stopTimers();
    _gapTimer?.cancel();
    _keepLooping = false;
    _inGap = false;
    await _player.stop();
    await _player.setVolume(1.0);
    if (mounted) {
      setState(() {
        _completedCount = 0;
        _progress = '';
        _status = '已停止';
      });
    }
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_text.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 音色 / 语速信息
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.record_voice_over, size: 20, color: Color(0xFF2DD4BF)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_text.voiceName} · ${_text.rate}',
                        style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // 播放模式
              SegmentedButton<PlayMode>(
                segments: const [
                  ButtonSegment(
                    value: PlayMode.loopCount,
                    label: Text('循环 N 遍'),
                    icon: Icon(Icons.repeat),
                  ),
                  ButtonSegment(
                    value: PlayMode.timer,
                    label: Text('定时停止'),
                    icon: Icon(Icons.timer_outlined),
                  ),
                  ButtonSegment(
                    value: PlayMode.listenRepeat,
                    label: Text('听背听'),
                    icon: Icon(Icons.hearing),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (s) {
                  setState(() => _mode = s.first);
                  if (_mode == PlayMode.listenRepeat && !_hasAudio) {
                    // 无音频时切听背听，引导先生成
                    _status = '还没有语音，先点「生成语音」';
                  }
                },
              ),
              const SizedBox(height: 12),
              // 模式取值
              ..._buildModeOptions(),
              const SizedBox(height: 12),
              // 语速：播放时变速，即时生效；±10% 步进
              Row(
                children: [
                  const Icon(Icons.speed, size: 20, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 6),
                  const Text('语速', style: TextStyle(fontSize: 14, color: Color(0xFFCBD5E1))),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _speedPct > kSpeedMinPct ? () => _stepSpeed(-10) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: '减 10%',
                  ),
                  Expanded(
                    child: Slider(
                      value: _speedPct.toDouble(),
                      min: kSpeedMinPct.toDouble(),
                      max: kSpeedMaxPct.toDouble(),
                      divisions: 12,
                      label: '$_speedPct%',
                      onChanged: (v) => _onSpeedChanged(v.round()),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _speedPct < kSpeedMaxPct ? () => _stepSpeed(10) : null,
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
              const SizedBox(height: 20),
              // 生成并播放
              FilledButton.icon(
                onPressed: _generating ? null : _ensureAudioAndPlay,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _generating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 28),
                label: Text(
                  _generating
                      ? (_chunks.isNotEmpty && _generateProgress != null
                          ? '生成中… ${(_generateProgress! * 100).round()}%'
                          : '生成中…')
                      : (_hasAudio ? '播放' : '生成并播放'),
                ),
              ),
              // 合成进度条（细长，生成时显示）
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _generating
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _generateProgress,
                            minHeight: 4,
                            backgroundColor: const Color(0xFF334155),
                            color: const Color(0xFF2DD4BF),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 16),
              // 播放控制条
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
                          onPressed: _playing ? _togglePlayPause : null,
                          iconSize: 40,
                          icon: const Icon(Icons.pause_circle_filled),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          onPressed: _playing ? null : _togglePlayPause,
                          iconSize: 40,
                          icon: const Icon(Icons.play_circle_filled),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          onPressed: _stop,
                          iconSize: 40,
                          icon: const Icon(Icons.stop_circle_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _progress,
                      style: const TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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

  List<Widget> _buildModeOptions() {
    if (_mode == PlayMode.loopCount) {
      return [
        Wrap(
          spacing: 8,
          children: [1, 2, 3, 5]
              .map((n) => ChoiceChip(
                    label: Text('$n 遍'),
                    selected: _loopCount == n,
                    onSelected: (_) => setState(() => _loopCount = n),
                  ))
              .toList(),
        ),
      ];
    }
    if (_mode == PlayMode.timer) {
      return [
        // 倒计时 / 准时结束 切换
        SegmentedButton<TimerStyle>(
          style: const ButtonStyle(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          segments: const [
            ButtonSegment(value: TimerStyle.countdown, label: Text('倒计时')),
            ButtonSegment(value: TimerStyle.absolute, label: Text('准时结束')),
          ],
          selected: {_timerStyle},
          onSelectionChanged: (s) => setState(() => _timerStyle = s.first),
        ),
        const SizedBox(height: 8),
        if (_timerStyle == TimerStyle.countdown)
          Wrap(
            spacing: 8,
            children: [15, 30, 45, 60]
                .map((m) => ChoiceChip(
                      label: Text('$m 分钟'),
                      selected: _timerMinutes == m,
                      onSelected: (_) => setState(() => _timerMinutes = m),
                    ))
                .toList(),
          )
        else ...[
          Wrap(
            spacing: 8,
            children: kAbsoluteTargets
                .map((d) {
                  final minutesOfDay = d.inHours * 60 + d.inMinutes % 60;
                  final label =
                      '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
                  return ChoiceChip(
                    label: Text(label),
                    selected: _selectedAbsolute == minutesOfDay,
                    onSelected: (_) => _selectAbsoluteTarget(minutesOfDay),
                  );
                })
                .toList(),
          ),
          const SizedBox(height: 6),
          Text(
            _targetTime == null
                ? '选择结束时间，到点自动渐弱停止'
                : _timeLeftText,
            style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
          ),
        ],
      ];
    }
    // 听背听
    return [
      Wrap(
        spacing: 8,
        children: kGapPercents
            .map((p) => ChoiceChip(
                  label: Text('留白 ${p == 100 ? '=朗读' : '$p%'}'),
                  selected: _gapPercent == p,
                  onSelected: (_) => setState(() => _gapPercent = p),
                ))
            .toList(),
      ),
      const SizedBox(height: 6),
      Text(
        '逐句朗读后留白，让孩子在留白里背出来（推荐 60%）',
        style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
      ),
    ];
  }
}
