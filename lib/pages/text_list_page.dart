// 文件夹内课文列表（含未分类场景）
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'player_page.dart';
import 'text_edit_page.dart';

class TextListPage extends StatelessWidget {
  final Folder? folder; // null = 未分类
  final List<ReciteText>? texts; // 未分类时传入

  const TextListPage({super.key, this.folder, this.texts});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.inst,
      builder: (context, _) {
        final store = AppStore.inst;
        final list = texts ??
            store.data.texts
                .where((t) => t.folderId == folder?.id)
                .toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(folder?.name ?? '未分类课文'),
            centerTitle: true,
            backgroundColor: Colors.transparent,
          ),
          floatingActionButton: folder == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TextEditPage(initialFolderId: folder!.id),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('新建课文'),
                ),
          body: list.isEmpty
              ? Center(
                  child: Text(
                    folder == null ? '暂无课文' : '这个文件夹还是空的',
                    style: const TextStyle(color: Color(0xFF94A3B8)),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    for (final t in list) _TextItem(text: t, folder: folder),
                  ],
                ),
        );
      },
    );
  }
}

class _TextItem extends StatelessWidget {
  final ReciteText text;
  final Folder? folder;

  const _TextItem({required this.text, this.folder});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlayerPage(text: text),
          ),
        ),
        leading: Icon(
          text.audioPath == null ? Icons.schedule : Icons.volume_up,
          color: text.audioPath == null ? const Color(0xFFF59E0B) : const Color(0xFF2DD4BF),
        ),
        title: Text(text.title, style: const TextStyle(fontSize: 15)),
        subtitle: Text(
          '${text.voiceName} · ${text.rate}${text.audioPath == null ? ' · 待生成' : ''}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'delete') {
              showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text('删除「${text.title}」？'),
                  content: const Text('删除后不可恢复。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('删除'),
                    ),
                  ],
                ),
              ).then((ok) {
                if (ok == true) AppStore.inst.deleteText(text.id);
              });
            }
            if (v == 'edit') {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => TextEditPage(edit: text)),
              );
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('编辑')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}
