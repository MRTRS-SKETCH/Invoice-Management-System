import 'dart:io';
import 'package:flutter/foundation.dart';

/// 应用级文件日志工具 — 与 Python 后端共用日志目录，按月命名，同步写入，持久留痕。
///
/// 日志文件路径：`core_api/user_data/flutter_YYYY-MM.log`（与 Python 后端同目录）
///
/// 调用方式：
/// ```dart
/// AppLogger.info('后端引擎启动成功');
/// AppLogger.error('网络请求失败', error);
/// AppLogger.warning('残留进程已清理');
/// ```
class AppLogger {
  static String? _logDirPath;
  static String? _currentLogPath;

  /// 获取当前日志文件的完整路径（方便用户定位）
  static String get logFilePath {
    _ensureLogDirSync();
    return _currentLogPath!;
  }

  /// 初始化日志目录（同步，首次调用时自动创建）
  static void _ensureLogDirSync() {
    if (_logDirPath != null) return;

    // 与 Python 后端共用日志目录：{项目根}/core_api/user_data/
    final currentDir = Directory.current.path;
    final logDir = Directory('$currentDir\\..\\core_api\\user_data');
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    _logDirPath = logDir.absolute.path;

    // Flutter 日志以 flutter_ 前缀区分，与 Python 的 YYYY-MM.log 放在同一目录
    final now = DateTime.now();
    final monthStr = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _currentLogPath = '${logDir.absolute.path}\\flutter_$monthStr.log';
  }

  /// 写入一条日志（同步，确保立即落盘）
  static void _write(String level, String message, [Object? error]) {
    try {
      _ensureLogDirSync();

      final now = DateTime.now();
      final timestamp =
          '${now.year}-${_pad(now.month)}-${_pad(now.day)} '
          '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}'
          '.${now.millisecond.toString().padLeft(3, '0')}';

      // 清洗消息中的换行符，避免日志出现莫名空行
      final cleaned = message.replaceAll('\r\n', ' ').replaceAll('\n', ' ').trim();
      var line = '$timestamp [$level] - $cleaned';
      if (error != null) {
        line += ' | ${error.toString().replaceAll('\n', ' ')}';
      }

      // 1. 同步写入本地日志文件（持久留痕，立即落盘）
      final logFile = File(_currentLogPath!);
      logFile.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);

      // 2. 开发模式下同步输出到控制台
      if (kDebugMode) {
        debugPrint('[$level] $message');
      }
    } catch (_) {
      // 日志写入失败不应阻断业务逻辑
      if (kDebugMode) {
        debugPrint('⚠️ 日志写入失败: $message');
      }
    }
  }

  /// 普通信息日志
  static void info(String message) => _write('INFO', message);

  /// 错误日志（自动附带异常信息）
  static void error(String message, [Object? error, StackTrace? stack]) {
    final sb = StringBuffer(message);
    if (error != null) {
      sb.write(' | 异常: $error');
    }
    if (stack != null) {
      sb.write(' | 堆栈: $stack');
    }
    _write('ERROR', sb.toString());
  }

  /// 警告日志
  static void warning(String message) => _write('WARNING', message);

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
