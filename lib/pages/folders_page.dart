// 课文（文件夹）页：文件夹列表 + 未分类课文
import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import 'text_edit_page.dart';
import 'text_list_page.dart';

class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});

  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  Future<void> _newFolder() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '如：语文、英语、古诗'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      AppStore.inst.addFolder(name);
    }
  }

  void _renameFolder(Folder f) {
    final ctrl = TextEditingController(text: f.name);
    showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    ).then((name) {
      if (name != null && name.isNotEmpty) AppStore.inst.renameFolder(f.id, name);
    });
  }

  void _confirmDeleteFolder(Folder f) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除文件夹「${f.name}」？'),
        content: const Text('文件夹内的课文和书单不会被删除，会移到未分类。'),
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
      if (ok == true) AppStore.inst.deleteFolder(f.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppStore.inst,
      builder: (context, _) {
        final store = AppStore.inst;
        final uncategorized = store.data.texts.where((t) => t.folderId == null).toList();
        return Scaffold(
          appBar: AppBar(
            title: const Text('我的课文'),
            centerTitle: true,
            backgroundColor: Colors.transparent,
            actions: [
              IconButton(
                onPressed: _newFolder,
                tooltip: '新建文件夹',
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TextEditPage()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('新建课文'),
          ),
          body: store.data.folders.isEmpty && uncategorized.isEmpty
              ? const _EmptyHint()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    if (store.data.folders.isNotEmpty) ...[
                      const _SectionTitle('文件夹'),
                      ...store.data.folders.map((f) => _FolderTile(
                            folder: f,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TextListPage(folder: f),
                              ),
                            ),
                            onRename: () => _renameFolder(f),
                            onDelete: () => _confirmDeleteFolder(f),
                          )),
                      const SizedBox(height: 16),
                    ],
                    if (uncategorized.isNotEmpty) ...[
                      const _SectionTitle('未分类课文'),
                      ...uncategorized.map(
                        (t) => _TextTile(
                          text: t,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TextListPage(
                                folder: null,
                                texts: [t],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_outlined,
              size: 72, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 16),
          const Text('还没有课文',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            '点右下角「新建课文」\n粘贴豆包识别出的文字，生成语音',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.55)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _FolderTile extends StatelessWidget {
  final Folder folder;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _FolderTile({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final store = AppStore.inst;
    final count = store.data.texts.where((t) => t.folderId == folder.id).length;
    final plCount = store.data.playlists.where((p) => p.folderId == folder.id).length;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF2DD4BF).withValues(alpha: 0.15),
          child: const Icon(Icons.folder, color: Color(0xFF2DD4BF)),
        ),
        title: Text(folder.name, style: const TextStyle(fontSize: 16)),
        subtitle: Text(
          '课文 $count 篇${plCount > 0 ? ' · 书单 $plCount 个' : ''}',
          style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'rename') onRename();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('重命名')),
            PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }
}

/// 课文行（未分类区使用；点开即进入该课文播放页）
class _TextTile extends StatelessWidget {
  final ReciteText text;
  final VoidCallback onTap;

  const _TextTile({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          text.audioPath == null ? Icons.schedule : Icons.volume_up,
          color: text.audioPath == null ? const Color(0xFFF59E0B) : const Color(0xFF2DD4BF),
        ),
        title: Text(text.title, style: const TextStyle(fontSize: 15)),
        subtitle: Text(
          '${text.voiceName} · ${text.rate}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
        ),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF475569)),
      ),
    );
  }
}
