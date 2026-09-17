// 验证 edge_tts Dart 包：晓晓音色 + 限流重试（与 APP 同一代码路径）
import 'dart:io';

import 'package:edge_tts/edge_tts.dart';

Future<void> main() async {
  const text =
      '盼望着，盼望着，东风来了，春天的脚步近了。一切都像刚睡醒的样子，欣欣然张开了眼。山朗润起来了，水涨起来了，太阳的脸红起来了。小草偷偷地从土里钻出来，嫩嫩的，绿绿的。';
  const out = r'D:\dev\tts_dart_test.mp3';
  for (var i = 1; i <= 6; i++) {
    try {
      final c = Communicate(
        text: text,
        voice: 'zh-CN-XiaoxiaoNeural',
        rate: '-10%',
      );
      await c.save(out);
      final f = File(out);
      final len = f.existsSync() ? f.lengthSync() : 0;
      if (len > 2000) {
        stdout.writeln('OK voice=zh-CN-XiaoxiaoNeural size=$len');
        return;
      }
      stdout.writeln('EMPTY attempt=$i size=$len');
    } catch (e) {
      stdout.writeln('RETRY attempt=$i err=$e');
    }
    await Future<void>.delayed(Duration(seconds: 5 * i));
  }
  exitCode = 1;
  stdout.writeln('FAILED after retries');
}
