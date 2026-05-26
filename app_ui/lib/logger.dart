import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

/// 前端日志单例 — 内存缓冲 + 批量上报，不阻塞 UI 线程。
///
/// - 日志先入内存队列，达到 50 条或每 2 秒自动批量 POST 到后端
/// - 发送为 fire-and-forget，后端不可达时静默丢弃，绝不抛异常或红屏
///
/// 用法：
/// ```dart
/// AppLogger.info('后端引擎启动成功');
/// AppLogger.error('网络请求失败', error);
/// AppLogger.warning('残留进程已清理');
/// ```
class AppLogger {
  AppLogger._();

  static final List<Map<String, String>> _buffer = [];
  static Timer? _timer;
  static bool _flushing = false;

  /// 初始化定时器（首次调用 info/warning/error 时自动触发）
  static void _ensureTimer() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _flush());
  }

  // ── 公开便捷方法 ──

  static void info(String message) => _enqueue('INFO', message);

  static void warning(String message) => _enqueue('WARNING', message);

  static void error(String message, [Object? error, StackTrace? stack]) {
    final sb = StringBuffer(message);
    if (error != null) {
      sb.write(' | 异常: $error');
    }
    if (stack != null) {
      sb.write(' | 堆栈: $stack');
    }
    _enqueue('ERROR', sb.toString());
  }

  // ── 内部逻辑 ──

  /// 入队一条日志
  static void _enqueue(String level, String message) {
    _ensureTimer();
    _buffer.add({'level': level, 'message': message});

    // 开发模式下同步输出到控制台（方便调试）
    if (kDebugMode) {
      debugPrint('[$level] $message');
    }

    // 缓冲达到阈值 → 立即触发发送
    if (_buffer.length >= 50) {
      _flush();
    }
  }

  /// 批量上报（fire-and-forget，不阻塞，不抛异常）
  static void _flush() {
    if (_buffer.isEmpty || _flushing) return;
    _flushing = true;

    // 取出当前缓冲并清空（后续日志进入新批次）
    final batch = List<Map<String, String>>.from(_buffer);
    _buffer.clear();

    http
        .post(
          Uri.parse('${AppConfig.baseUrl}/api/client-logs/batch'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode(batch),
        )
        .then((_) {
          // 发送成功 — 日志已安全抵达后端
        })
        .catchError((_) {
          // 后端不可达 — 静默丢弃（需求规定不可抛异常/红屏）
        })
        .whenComplete(() {
          _flushing = false;
        });
  }
}
