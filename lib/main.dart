import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'pages/folders_page.dart';
import 'pages/playlists_page.dart';
import 'pages/settings_page.dart';
import 'store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.sleep_recite.channel.audio',
    androidNotificationChannelName: '睡背 · 播放',
    androidNotificationOngoing: true,
  );
  await AppStore.inst.load();
  runApp(const SleepReciteApp());
}

class SleepReciteApp extends StatelessWidget {
  const SleepReciteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '睡背',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2DD4BF),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomeShell(),
    );
  }
}

/// 底部导航：文件夹 / 书单 / 设置
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [FoldersPage(), PlaylistsPage(), SettingsPage()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '课文',
          ),
          NavigationDestination(
            icon: Icon(Icons.playlist_play_outlined),
            selectedIcon: Icon(Icons.playlist_play),
            label: '书单',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
