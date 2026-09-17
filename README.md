# 睡背 APP（sleep_recite）

给初中孩子睡前听背诵课本的安卓应用：**豆包拍照复制课文 → 粘贴进 APP → 选音色 → 生成语音 → 循环 N 遍 / 定时停止 / 准时结束 → 息屏播放**。

> 核心场景：孩子睡前闭眼听，家长不介入操作。语音合成走免费在线方案（微软 edge_tts 神经音色），音频按内容哈希本地缓存，同段文字只生成一次。

## 功能

### 已完成 ✅
- **内容管理**：文件夹 → 课文两层结构；新建课文（粘贴文字 / 选音色 / 自动取标题）
- **播放**：循环 1/2/3/5 遍 · 倒计时 15/30/45/60 分钟 · **准时结束（22:30/23:00/23:30）** · 结束前 30 秒渐弱
- **语速**：播放时变速滑动条 -30% ~ +30%，±10% 步进按钮，即时生效、无需重新生成
- **听背听**：逐句朗读 + 留白（50/60/80/100%，默认 60%），孩子在留白里背出来，整篇循环 N 遍
- **长文本分块合成**：按句末标点切块（每块 ≤400 字）逐块生成、断点续传（已生成的块自动跳过）、无缝连播
- **息屏播放**：前台服务 + 媒体通知 + 锁屏控制；设置页含小米/红米 3 步保活引导
- **书单**：独立播放列表，顺序连播，可放文件夹分类
- **备份恢复**：导出 JSON（分享到手机/微信/网盘）· 导入恢复（缺失音频播放时自动重新生成）
- **缓存治理**：编辑/删除课文后自动清理孤儿音频文件

### 规划中 ⏳
- 批量生成入口（多选课文批量合成 + 断点续传 + 进度显示）
- 复习 1/3/7/14 天（App 内横幅 + 红点提醒）
- 缓存清理、真机打磨
- OCR（明确推迟：先用豆包拍照复制文字）

## 技术栈

| 层 | 选型 |
| --- | --- |
| 框架 | Flutter 3.47.4 / Dart 3.13（Android 优先，红米 K80 目标机） |
| 语音合成 | edge_tts（免费在线，5 次退避重试）→ 兜底方案：Cloudflare Worker / 豆包 API |
| 播放 | just_audio + just_audio_background（前台服务 / 媒体通知 / 锁屏控制） |
| 存储 | 本地 JSON（应用文档目录）+ 音频文件按 `sha256(文本+音色+语速)前20` 内容寻址缓存 |
| 系统集成 | android_intent_plus（跳转系统设置页保活引导）、share_plus / file_picker（备份） |

## 目录结构

```
lib/
  main.dart              入口 + 底部三 tab（课文 / 书单 / 设置）
  models.dart            Folder / ReciteText / Playlist 数据模型（含 audioChunks 分块）
  store.dart             AppStore 全局状态 + JSON 持久化 + 孤儿音频清理
  tts.dart               语音合成：缓存寻址 / 5 次重试 / 分块切分与合成
  player_holder.dart     全局唯一 AudioPlayer 单例
  pages/
    folders_page.dart    课文 tab（文件夹列表）
    text_list_page.dart  文件夹内课文列表
    text_edit_page.dart  新建 / 编辑课文
    player_page.dart     单篇播放页（三模式 / 语速 / 生成进度 / 分块连播 / 听背听）
    playlists_page.dart  书单管理与顺序连播
    settings_page.dart   设置（保活引导 / 备份恢复）
界面预览/               开发过程截图（交付记录）
试听音频/               3 个音色试听
scripts/                host 端 edge-tts 试听脚本
tool/                   Dart 测试工具
```

## 开发环境（本机已就绪）

| 项 | 位置 |
| --- | --- |
| Flutter | `D:\dev\flutter\flutter`（3.47.4 stable） |
| JDK | `D:\dev\jdk17` |
| Android SDK | `D:\dev\AndroidSdk` |
| Gradle / pub 缓存 | `D:\dev\.gradle` / `D:\dev\pub-cache` |
| 模拟器 | AVD `sleep`（Pixel 7 / Android 15） |

> 工具链一律装在 D 盘（用户硬性要求：C 盘空间紧张）。构建需设置 `ANDROID_HOME` / `JAVA_HOME` / `PUB_CACHE` / `GRADLE_USER_HOME` 环境变量。

### 构建

```powershell
# 调试包（模拟器，4 ABI）
flutter build apk --debug

# 真机 release（红米 K80，单 arm64，约 19MB）
flutter build apk --release --target-platform android-arm64
```

## 测试与验证

- `flutter analyze` 保持 0 issue
- `flutter test` 冒烟测试
- 模拟器全链路截图记录见 `界面预览/`
- 已知限制：模拟器音频无声 / 模拟器网络可能连不上 TTS 服务（宿主机正常），真机不受影响

## 协作说明（给后续 AI / 开发者）

接手前请完整阅读：
- **`睡背APP-交接文档.md`** — 产品决策 / 技术框架 / 模块职责 / 开发计划进度 / 踩坑记录（新对话第一入口）
- **`睡背APP-技术方案.md`** — 原始方案与技术选型

核心设计约束：
1. 播放器是全局单例（`PlayerHolder.player`），严禁再 `new AudioPlayer()`
2. 语速是播放时变速（`setSpeed`），**不参与音频生成参数**（生成固定 0%）
3. 音频内容寻址缓存：`sha256(文本+音色+语速)前20`，分块为 `hash_c{i}.mp3`
4. 已有音频优先直接播放，缺失才联网生成
5. 每完成一个阶段先给用户看效果确认再继续；讨论/方案类问题先给方案不直接实现

## License

Private project（个人项目，暂未开源许可）。
