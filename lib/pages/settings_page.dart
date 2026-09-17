// 设置页：息屏播放保活引导（小米三项）+ 备份恢复 + 功能说明
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../store.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 电池优化豁免：系统弹窗让用户选择「允许」
  Future<void> _openBatteryOptimization() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
        data: 'package:com.example.sleep_recite',
      );
      await intent.launch();
    } catch (_) {
      // 部分 ROM 不支持该 action，回退到应用信息页
      await _openAppInfo();
    }
    _toast('请在系统页选择「允许」或「无限制」');
  }

  /// 小米/红米 自启动授权页
  Future<void> _openAutoStart() async {
    const miui = AndroidIntent(
      package: 'com.miui.securitycenter',
      componentName: 'com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity',
    );
    try {
      if (await miui.canResolveActivity() == true) {
        await miui.launch();
        return;
      }
    } catch (_) {}
    await _openAppInfo();
  }

  /// 应用信息页（后台运行 / 锁屏清理保护）
  Future<void> _openAppInfo() async {
    try {
      const intent = AndroidIntent(
        action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
        data: 'package:com.example.sleep_recite',
      );
      await intent.launch();
    } catch (_) {
      _toast('无法打开系统设置页，请手动进入 设置→应用管理→睡背');
    }
  }

  /// 导出备份：把数据 JSON 分享出去（保存到手机/微信/网盘）
  Future<void> _exportBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final src = File(await AppStore.dataFilePath());
      if (!await src.exists()) {
        _toast('还没有数据可备份');
        return;
      }
      final tmpDir = await getTemporaryDirectory();
      final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '-');
      final out = File('${tmpDir.path}/睡背备份-$stamp.json');
      await out.writeAsString(await src.readAsString(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(out.path, mimeType: 'application/json')],
          subject: '睡背 APP 备份',
          text: '睡背 APP 数据备份（导入：设置 → 恢复备份）',
        ),
      );
      _toast('备份已导出');
    } catch (e) {
      _toast('导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 导入恢复：选择备份 JSON，覆盖当前数据
  Future<void> _importBackup() async {
    if (_busy) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: '选择睡背备份文件',
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final raw = await File(path).readAsString();
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (!j.containsKey('texts') || !j.containsKey('folders') || !j.containsKey('playlists')) {
        _toast('不是有效的睡背备份文件');
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('恢复备份？'),
          content: const Text('将用备份覆盖当前的课文/书单数据（本地音频不删除）。\n'
              '备份中缺失的音频会在播放时自动重新生成。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('恢复')),
          ],
        ),
      );
      if (confirmed != true) return;
      setState(() => _busy = true);
      final store = AppStore.inst;
      // 先清理旧音频引用，避免孤儿文件堆积
      final old = store.data;
      for (final t in old.texts) {
        store.deleteText(t.id);
      }
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/sleep_recite_data.json');
      await out.writeAsString(const JsonEncoder.withIndent('  ').convert(j), flush: true);
      await store.load();
      _toast('恢复成功，共 ${store.data.texts.length} 篇课文');
    } catch (e) {
      _toast('导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 息屏播放说明
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.nightlight_round, color: Color(0xFF2DD4BF)),
                      SizedBox(width: 8),
                      Text('息屏播放',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '播放时锁屏/息屏会继续，通知栏有播放控制（暂停/停止）。\n'
                    '小米/红米手机需要在系统设置里允许「睡背」后台运行，否则会被省电策略杀掉。\n'
                    '首次使用建议按下面 3 步设置一次。',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8), height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _SectionTitle('后台保活设置（小米）'),
          _SettingTile(
            icon: Icons.battery_saver,
            title: '1. 电池优化 → 无限制',
            subtitle: '系统弹窗选「允许」；这是息屏不被杀的关键',
            onTap: _openBatteryOptimization,
          ),
          _SettingTile(
            icon: Icons.autorenew,
            title: '2. 自启动权限',
            subtitle: 'MIUI 授权管理 → 自启动，打开「睡背」',
            onTap: _openAutoStart,
          ),
          _SettingTile(
            icon: Icons.info_outline,
            title: '3. 后台运行 / 锁屏保护',
            subtitle: '应用信息 → 省电策略：无限制；锁屏清理：不清理',
            onTap: _openAppInfo,
          ),
          const SizedBox(height: 16),
          const _SectionTitle('备份与恢复'),
          _SettingTile(
            icon: Icons.upload_file,
            title: '导出备份',
            subtitle: _busy ? '处理中…' : '把课文/书单数据导出分享（可存手机/微信/网盘）',
            onTap: _exportBackup,
          ),
          _SettingTile(
            icon: Icons.download_done,
            title: '恢复备份',
            subtitle: '选择之前导出的备份文件，恢复课文和书单',
            onTap: _importBackup,
          ),
          const SizedBox(height: 16),
          const _SectionTitle('其他说明'),
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('复习提醒', '在 App 内显示横幅 + 红点，不打扰系统通知'),
                  const Divider(height: 20, color: Color(0xFF334155)),
                  _infoRow('语音生成', '免费在线合成（微软神经音色），同一段文字只生成一次'),
                  const Divider(height: 20, color: Color(0xFF334155)),
                  _infoRow('数据存储', '课文/书单保存在手机本地，导出备份后可防止丢失'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(label,
              style: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1))),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
        ),
      ],
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

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF2DD4BF).withValues(alpha: 0.15),
          child: Icon(icon, color: const Color(0xFF2DD4BF), size: 20),
        ),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        trailing: const Icon(Icons.chevron_right, color: Color(0xFF475569)),
      ),
    );
  }
}
