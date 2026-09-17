# 睡背 APP・AI 交接文档（v0.7）

> **本文件是新接手 AI 的第一入口。**
> 接手前请完整阅读本文档 + 《睡背 APP - 技术方案.md》（v0.3）。
> 先跑 `flutter analyze` 确认环境，再按「9. 开发计划进度」继续下一阶段。
>
> 最近更新：2026-09-17 ③ 批量前置完成：语速±按钮/百分比、生成进度条、准时结束、长文本分块无缝连播、听背听逐句留白、孤儿音频清理、备份导出/导入，全部模拟器实测通过。

---

## 1. 项目一句话

给初中女儿晚上睡前听背诵课本内容的安卓 APP（红米 K80）：豆包拍照复制文字 → 粘贴进 APP → 选音色 → 生成语音（免费在线合成）→ 选循环 N 遍 / 定时停止 → 手机息屏播放（前台服务保活 + 锁屏控制）。

## 2. 已确认的产品决策（勿再推翻）

| 决策 | 内容 |
| --- | --- |
| 音色 | 一期 3 个：晓晓（默认）/ 晓伊 / 云希，已试听确认。音色是合成参数，切换需重新生成一次（有缓存，同参数只生成一次） |
| **语速（方案 A）** | **播放时变速**：滑动条 -30%~+30% + 两侧 ±10% 步进按钮，右侧显示具体百分比（0%/-10%/+30%），拖动即时生效、**无需重新生成**。生成统一用正常语速 0% |
| 循环 / 定时 | 都做且可改；循环 1/2/3/5 遍、倒计时 15/30/45/60 分钟、**准时结束 22:30/23:00/23:30（已过顺延明天，UI 显示"距 23:00 还有 X 分钟"）**，结束前 30 秒渐弱 |
| **听背听** | ✅ 已实现：逐句（分块）朗读 + 留白（50/60/80/100%，默认 60%），整篇循环 N 遍；留白中显示"留白 X 秒，自己背一遍…" |
| 内容结构 | 两层：**文件夹 → 课文**；**书单**是独立播放列表（可放文件夹），按顺序连播 |
| 复习 | 1/3/7/14 天；**App 内横幅 + 红点提醒（明确不要系统通知）**；今日待复习 + 完成比例 —— 未实现（第⑤阶段） |
| 息屏播放 | ✅ 已实现：前台服务 + 媒体通知 + 锁屏控制；小米需按设置页 3 步授权后台运行 |
| 长文本 | ✅ 分块合成：按句末标点切块（每块 ≤400 字），逐块生成（已存在的块自动跳过=断点续传），播放时无缝连播；单文件模式兼容 |
| 备份 | ✅ 设置页"导出备份"（share_plus 分享 JSON，可存手机/微信/网盘）+ "恢复备份"（file_picker 选文件覆盖导入）；缺失音频播放时自动重生成 |
| OCR | **明确推迟**：豆包拍照复制文字已够用，粘贴入口。后续再研究 flutter_paddle_ocr_v5 |
| 砍掉 | 显示原文、系统通知（复习用 App 内横幅）、科目分类 |
| TTS 路线 | edge_tts（免费直连，间歇限流已做 5 次退避重试）→ 兜底：Cloudflare Worker（代码待写）→ 豆包 API |
| 架构 | 生成端与播放端解耦；音频按 `sha256(文本+音色+语速)前20` 命名缓存；**语速不参与缓存（播放时变速）** |
| APK | debug 包（4 ABI，模拟器/调试用）；**release 单 arm64 19.2MB（红米 K80 用）** |
| 用户 | 家长不介入日常操作；孩子流程 3~4 步 |
| 技术栈 | Flutter 3.47.4 / Dart 3.13，Android 优先（小米/红米） |

## 3. 技术框架（架构总览）

```
┌─────────────────────────────────────────────────────┐
│  UI 层（lib/pages/*）                                │
│  课文tab(文件夹→课文列表) · 书单tab · 设置tab(保活引导) │
│  新建课文表单 · 单篇播放页 · 书单连播页                 │
├─────────────────────────────────────────────────────┤
│  状态层  AppStore（ChangeNotifier 单例，lib/store.dart）│
│         所有页面 ListenableBuilder 监听，改动即时刷新   │
├─────────────────────────────────────────────────────┤
│  存储层  应用文档目录/sleep_recite_data.json（JSON）    │
│          模型：Folder / ReciteText / Playlist          │
├─────────────────────────────────────────────────────┤
│  TTS 层  edge_tts 免费在线合成（lib/tts.dart）          │
│          5 次指数退避重试 · sha256 内容寻址缓存          │
├─────────────────────────────────────────────────────┤
│  播放层  PlayerHolder.player 全局唯一 AudioPlayer      │
│          just_audio_background → 前台服务+通知+锁屏控制 │
│          语速变速 setSpeed · 循环/定时 · 渐弱            │
└─────────────────────────────────────────────────────┘
```

**关键设计约束（接手前必读）**
1. **播放器单例**：所有页面共用 `PlayerHolder.player`，**严禁再 new AudioPlayer()**（just_audio_background 依赖单实例）；页面 dispose 不销毁播放器（离开页面播放继续，靠媒体通知控制）
2. **语速不走生成**：生成固定 `kDefaultRate = '0%'`；语速 = 播放器 `setSpeed(1 + pct/100)`，`kSpeedMinPct=-30 / kSpeedMaxPct=30`
3. **已有音频优先**：播放页点按钮先查 `text.audioPath`（单文件）或 `text.audioChunks`（分块，全部存在即有效）→ 直接播；否则才联网生成
4. **缓存寻址**：`audioPathFor(text, voice, rate)` 用 sha256 前 20 位；分块为 `hash_c{i}.mp3`；同参数不重复生成
5. **分块播放**：多块用 `_player.setAudioSources(List<AudioSource.uri>)`（新版 API，**勿用已废弃的 ConcatenatingAudioSource 的 tag 参数**）；听背听模式手动逐块 `_playChunk(i)` + 留白 Timer
6. **孤儿音频清理**：updateText/deleteText 后旧音频若不再被任何课文引用则删除（store._cleanupOrphanedAudio）

## 4. 模块划分（lib/ 各文件职责）

| 文件 | 职责 | 关键内容 |
| --- | --- | --- |
| `main.dart` | 入口 + 底部三 tab 壳 | `JustAudioBackground.init`（通知渠道"睡背 · 播放"）；`AppStore.load()` |
| `models.dart` | 数据模型 | Folder / ReciteText（含 voice/rate/audioPath/**audioChunks**）/ Playlist / AppData，JSON 序列化 |
| `store.dart` | 全局状态 + 持久化 | AppStore 单例（ChangeNotifier）；load/save 写 sleep_recite_data.json；文件夹/课文/书单全套 CRUD；**updateText/deleteText 自动清理孤儿音频（无其他课文引用才删）** |
| `tts.dart` | 语音合成 | kVoices（3 音色）/ kSpeedMinPct/MaxPct / kDefaultRate='0%'；audioPathFor 缓存路径；synthesize 5 次退避重试；**splitTextForTts 按句切块(≤400字) / synthesizeChunks 分块合成（已存在块自动跳过）/ chunkPathFor** |
| `player_holder.dart` | 全局播放器 | `PlayerHolder.player` 单一 AudioPlayer 实例 |
| `pages/folders_page.dart` | 课文 tab | 文件夹列表（重命名/删除）+ 未分类课文 + 新建入口 |
| `pages/text_list_page.dart` | 文件夹内课文列表 | 点击进播放页；编辑/删除课文 |
| `pages/text_edit_page.dart` | 新建/编辑课文 | 标题（可空取内容前16字）+ 内容粘贴 + 文件夹 + 音色选择；保存并生成（长文本自动分块） |
| `pages/player_page.dart` | 单篇播放 | 三模式（循环/定时[倒计时+准时]/听背听）、语速滑块±10%、生成进度条、分块无缝连播、逐句留白、渐弱；媒体通知 MediaItem |
| `pages/playlists_page.dart` | 书单 | 列表/新建/详情（添加移除课文）/ 顺序连播（分块兼容 + 语速滑块±10%） |
| `pages/settings_page.dart` | 设置 | 息屏说明 + 小米 3 步保活引导 + **导出/恢复备份（share_plus/file_picker）** |

## 5. 开发环境（本机已装好，勿重装）

| 项 | 路径 / 说明 |
| --- | --- |
| Flutter | `D:\dev\flutter\flutter\bin\flutter.bat`（3.47.4 stable） |
| JDK | `D:\dev\jdk17\jdk-17.0.20.1+1`（JAVA_HOME 已写 User 环境变量） |
| Android SDK | `D:\dev\AndroidSdk`（ANDROID_HOME 已写；platforms 34/35/36、NDK 28.2、licenses 已手写） |
| Gradle 缓存 | `D:\dev\.gradle`（GRADLE_USER_HOME 已写） |
| pub 缓存 | `D:\dev\pub-cache`（PUB_CACHE 已写） |
| Python venv | `E:\WorkSpace\SleepAPP\.venv`（edge-tts 试听脚本用；**pip --user 被禁用**） |
| 镜像 | 阿里云 maven、腾讯 gradle、pub.flutter-io.cn、storage.flutter-io.cn |
| 模拟器 | AVD `sleep`（Pixel7/Android15，x86_64）：`emulator -avd sleep -gpu swiftshader_indirect`；调试 `flutter run -d emulator-5554` |

**PowerShell 构建模板**（新进程不继承 User 变量，每次都要带）：

```
$env:ANDROID_HOME='D:\dev\AndroidSdk'; $env:JAVA_HOME='D:\dev\jdk17\jdk-17.0.20.1+1'
$env:PUB_HOSTED_URL='https://pub.flutter-io.cn'; $env:FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn'
$env:PUB_CACHE='D:\dev\pub-cache'; $env:GRADLE_USER_HOME='D:\dev\.gradle'
$env:Path="D:\dev\flutter\flutter\bin;$env:Path"
Set-Location E:\WorkSpace\SleepAPP
flutter pub get / flutter analyze / flutter test / flutter build apk --debug
flutter build apk --release --target-platform android-arm64   # 红米K80 安装包
```

## 6. 已核实的技术事实（避免重复踩坑）

* **模拟器是 x86_64**：只能装含 x86 的 debug 包；**release 单 arm64 包（18.6MB）只能装真机（红米 K80）**，装模拟器会崩（libflutter.so ABI 不匹配）
* edge-tts 间歇限流（NoAudioReceived），5 次退避重试一般可成功；**宿主机 Python edge-tts 可作连通性基准**（`.venv\Scripts\edge-tts`）
* **模拟器网络可能连不上 speech.platform.bing.com（宿主机正常）**：出现"生成失败：网络异常"时，先跑宿主机 edge-tts 确认服务端状态；模拟器网络问题不影响真机
* **Kotlin 增量缓存 bug（Windows）**：新增 Kotlin 插件（share_plus 等）后 `compileDebugKotlin` 报 "Could not close incremental caches ... Storage is already registered" → 已解决：`android/gradle.properties` 加了 `kotlin.incremental=false` + `kotlin.compiler.execution.strategy=in-process`（增量编译绕开，代价是编译略慢，勿删）
* `auto_start_flutter 1.4.0` 用 jcenter() 编译失败 → 弃用；改用 android_intent_plus（6.x 参数是 `componentName`、`canResolveActivity`）
* 工具链全 D 盘，**C 盘不增长**（用户明确要求）；新装工具一律放空间充足的盘
* PowerShell 5.1 中文陷阱：带中文的文件修改用 Write 工具（内联编码会乱码）；脚本保持 ASCII；**内联 JSON 含数组时用 python 生成（PowerShell 转义易炸）**
* 注入模拟器测试数据：`adb root` + push JSON 到 `/data/data/com.example.sleep_recite/app_flutter/sleep_recite_data.json`，chmod 666；音频放 `.../sleep_recite_audio/`；注入后用 `python -c` 写 JSON 最稳

## 7. 用户协作规则（务必遵守）

1. **讨论/方案类问题只给分析和方案，不直接实现**；确认后才动手（含 git 操作）
2. **每完成一个阶段先给用户看效果确认，再继续下一步**（用户曾因"没看到界面就做完"不满）
3. 工具/缓存装空间充足的盘，**不占 C 盘**
4. 网页类开发必须手机+PC 双适配（本项目原生 APP 不适用）
5. 用户偏好：记录题目不带答案（另一项目习惯）
6. **用户会开新对话让 AI 接手**——所有阶段状态必须同步到本文档

## 8. 已完成的阶段

### ✅ 第①阶段：内容管理 + 书单（2026-09-17）
文件夹→课文两层 + 新建课文（标题/内容/文件夹/3音色 + 保存并生成）+ 播放页（循环/定时/渐弱）+ 书单（CRUD/添加课文/顺序连播）+ JSON 持久化。验证：analyze 0 问题、冒烟测试、模拟器逐页截图、真实联网生成并循环 3 遍。

### ✅ 第②阶段：息屏播放验证（2026-09-17）
just_audio_background 前台服务 + 媒体通知 + 锁屏控制 + 设置页小米 3 步保活引导。验证：锁屏 25 秒后解锁显示"已循环 3 遍，播放结束"（未被杀）；快捷面板出现"静夜思"媒体控件。**真机（红米 K80）需按设置页授权后复测。**

### ✅ 第③阶段前奏：语速方案 A（2026-09-17）
语速从"生成参数"改为"播放时变速"：滑动条 -30%~+30%（divisions 12）、拖动即时 setSpeed、**无需重新生成**；生成统一 0%；播放页与书单连播页均有滑块；已有音频直接播放（按钮"播放"而非"重新生成"）。验证：滑块拖到 30% 后 1 秒音频 1.3x 循环完成。

### ✅ 第③阶段前置批量（2026-09-17）
1. **滑块 ±10% 按钮**：两侧 −/+ 步进按钮，右侧显示具体百分比（0%/-10%/+30%），播放页+连播页都改
2. **生成反馈**：大按钮"生成中…"+转圈 + 按钮下方细长进度条（分块合成显示百分比）
3. **准时结束**：定时 → 倒计时/准时结束切换；22:30/23:00/23:30（已过顺延明天）；每秒刷新"距 23:00 还有 X 分钟"；到点前 30 秒渐弱
4. **长文本分块合成**：splitTextForTts 按句切块(≤400字) → synthesizeChunks 逐块生成（已存在块跳过）→ audioChunks 存 JSON → setAudioSources 无缝连播；听背听逐块播放基础
5. **听背听模式（第④阶段前置原型）**：逐句朗读 + 留白（50/60/80/100% 默认60）→ 整篇循环 N 遍；留白中显示"留白 X 秒，自己背一遍…"
6. **孤儿音频清理**：updateText/deleteText 后旧音频无引用即删
7. **备份导出/导入**：设置页导出分享 JSON + 选择文件导入覆盖（缺失音频播放时自动重生成）
验证：模拟器全部实测——±按钮步进、准时结束倒计时显示、听背听逐句→留白→循环3遍自动停、分块连播第2/3遍、导出分享面板弹窗显示备份文件。**分块联网合成未在模拟器验证（模拟器网络不通），已用宿主生成音频注入验证播放链路；真机待验。**

## 9. 开发计划进度

| 阶段 | 内容 | 状态 | 验证方式 |
| --- | --- | --- | --- |
| ① 内容管理+书单 | 文件夹/课文/书单/持久化 | ✅ 完成 | 模拟器全链路 |
| ② 息屏播放 | 前台服务+通知+锁屏+保活引导 | ✅ 完成 | 锁屏 25s 存活实测 |
| ③-a 语速滑动条 | 方案 A 播放变速 | ✅ 完成 | 滑块 30% 实测 |
| ③-b 批量前置 | ±10%按钮/百分比/进度条/准时结束/分块缓存/听背听原型/孤儿清理/备份 | ✅ 完成 | 模拟器实测（分块联网合成待真机） |
| ③ 批量生成入口 | 多选课文批量合成（串行+失败重试+界面"已完成12/20，失败3，待生成5"）；**edge-tts Cloudflare Worker 兜底代码写好放仓库（不部署）** | ⏳ 下一个 | — |
| ④ 听背听打磨 | 逐句留白已原型；实测调留白比例；可加"点击下一句"交互 | ⏳ 部分完成 | — |
| ⑤ 复习 1/3/7/14 | App 内横幅+红点；今日待复习列表；一键播放；完成比例 | ⏳ | — |
| ⑥ 设置完善+缓存清理 | 缓存清理（必需品，见点评）；打磨 | ⏳ | — |
| 真机适配 | 红米 K80 安装 release 包 + 3 步授权复测息屏+联网生成 | ⏳ 待用户 | 真机实测 |

## 10. 待办 / 已知问题

* **模拟器 TTS 网络不通**（宿主机正常）：模拟器连 speech.platform.bing.com 失败，已用宿主机生成音频注入验证播放链路；真机不受影响。可尝试重启模拟器或换网络后复测
* **批量生成入口未做**：课文列表多选触发批量、进度展示页面形态未定（下一阶段）
* **Cloudflare Worker 兜底代码未写**（计划在 ③ 阶段顺手完成）
* 听背听留白比例 60% 是拍脑袋值，需真机给孩子实测后调
* **模拟器无声（遗留）**：播放正常但宿主听不到（音频设备后端问题），已试多种方案无效；用户同意"模拟器看界面、真机听声音"
* 真机实测反馈清单（待收集）
