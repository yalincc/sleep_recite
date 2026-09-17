// 新建 / 编辑课文：标题 + 内容 + 文件夹 + 音色 + 语速 + 生成保存
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../tts.dart';

class TextEditPage extends StatefulWidget {
  final ReciteText? edit; // 非空 = 编辑模式
  final String? initialFolderId;

  const TextEditPage({super.key, this.edit, this.initialFolderId});

  @override
  State<TextEditPage> createState() => _TextEditPageState();
}

class _TextEditPageState extends State<TextEditPage> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late String? _folderId;
  late VoiceOption _voice;

  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final e = widget.edit;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _contentCtrl = TextEditingController(text: e?.content ?? '');
    _folderId = widget.initialFolderId ?? e?.folderId;
    _voice = e == null
        ? kDefaultVoice
        : (kVoices.where((v) => v.code == e.voice).firstOrNull ?? kDefaultVoice);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (content.isEmpty) {
      _toast('请粘贴或输入背诵内容');
      return;
    }
    final effectiveTitle = title.isEmpty
        ? (content.length > 16 ? content.substring(0, 16) : content)
        : title;

    setState(() {
      _busy = true;
      _status = '正在生成语音（${_voice.name}）…';
    });

    // 生成：长文本（多句）分块合成（天然断点续传）；短文本单文件
    String? audioPath;
    List<String>? audioChunks;
    if (splitTextForTts(content).length > 1) {
      final chunks = await synthesizeChunks(
        content,
        _voice.code,
        kDefaultRate,
        onProgress: (done, total, status) {
          if (!mounted) return;
          setState(() {
            _status = status ??
                '正在生成语音（${_voice.name}）… 第 $done/$total 段';
          });
        },
      );
      if (chunks != null && chunks.isNotEmpty) audioChunks = chunks;
    } else {
      final outPath = await audioPathFor(content, _voice.code, kDefaultRate);
      final ok = await synthesize(content, _voice.code, kDefaultRate, outPath,
          onStatus: (s) {
        if (mounted) setState(() => _status = s);
      });
      if (ok) audioPath = outPath;
    }

    if (!mounted) return;
    final store = AppStore.inst;
    if (widget.edit != null) {
      final t = widget.edit!;
      t.title = effectiveTitle;
      t.content = content;
      t.folderId = _folderId;
      t.voice = _voice.code;
      t.voiceName = _voice.name;
      t.rate = kDefaultRate;
      t.audioPath = audioPath;
      t.audioChunks = audioChunks;
      store.updateText(t);
    } else {
      store.addText(ReciteText(
        id: 't-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        folderId: _folderId,
        title: effectiveTitle,
        content: content,
        voice: _voice.code,
        voiceName: _voice.name,
        rate: kDefaultRate,
        audioPath: audioPath,
        audioChunks: audioChunks,
        createdAt: DateTime.now(),
      ));
    }

    final generated = (audioPath != null) || (audioChunks != null);
    if (generated) {
      _toast('已保存并生成语音');
    } else {
      _toast('课文已保存，但语音生成失败（网络/限流），稍后可重新生成');
    }
    Navigator.pop(context);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final store = AppStore.inst;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.edit == null ? '新建课文' : '编辑课文'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: ListenableBuilder(
        listenable: AppStore.inst,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                maxLines: 1,
                style: const TextStyle(fontSize: 16),
                decoration: _decoration('标题（可留空，自动取内容前 16 字）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentCtrl,
                maxLines: 8,
                minLines: 5,
                style: const TextStyle(fontSize: 16, height: 1.6),
                decoration: _decoration('粘贴豆包识别出的课文内容'),
              ),
              const SizedBox(height: 12),
              // 文件夹
              DropdownButtonFormField<String?>(
                initialValue: _folderId,
                decoration: _decoration('放进文件夹（可选）'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('未分类')),
                  ...store.data.folders.map(
                    (f) => DropdownMenuItem<String?>(value: f.id, child: Text(f.name)),
                  ),
                ],
                onChanged: (v) => setState(() => _folderId = v),
              ),
              const SizedBox(height: 16),
              // 音色
              const _Label('音色'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kVoices
                    .map((v) => ChoiceChip(
                          label: Text(v.name),
                          selected: _voice.code == v.code,
                          onSelected: (_) => setState(() => _voice = v),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 16),
              Text(
                '语速在播放页随时调节（±30%），无需重新生成语音。',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_busy ? '生成中…' : '保存并生成语音'),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                '保存时会自动联网生成语音（约几秒~十几秒）。生成失败可稍后重试，课文会先保存。',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.45)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
    );
  }
}
