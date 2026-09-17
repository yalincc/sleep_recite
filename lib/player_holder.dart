// 全局唯一播放器：just_audio_background 要求单一 AudioPlayer 实例，
// 由它提供前台服务、媒体通知、锁屏/耳机控制，支撑息屏播放。
import 'package:just_audio/just_audio.dart';

class PlayerHolder {
  PlayerHolder._();
  static final AudioPlayer player = AudioPlayer();
}
