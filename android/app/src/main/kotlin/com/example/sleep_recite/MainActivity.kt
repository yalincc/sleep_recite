package com.example.sleep_recite

// 继承 AudioServiceActivity（audio_service 提供，继承自 FlutterActivity）：
// 使应用在息屏/后台时保持前台服务运行，支持媒体通知与锁屏控制。
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
