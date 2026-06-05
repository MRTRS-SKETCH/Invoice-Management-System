import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 本地 JSON 持久化 — 替代 shared_preferences
///
/// 存储文件位于 `config/preferences.json`：
///   - Debug 模式：`app_ui/config/preferences.json`
///   - Release 模式：`{exe目录}/config/preferences.json`
///
/// 写入使用异步 + 100ms 防抖，避免 UI 线程阻塞。
class ConfigStorage {
  static ConfigStorage? _instance;

  final String _filePath;
  Map<String, dynamic> _cache = {};
  Timer? _saveTimer;
  bool _dirty = false;

  ConfigStorage._(this._filePath) {
    _load();
  }

  /// 获取单例，自动解析配置文件路径
  static ConfigStorage get instance {
    if (_instance != null) return _instance!;
    _instance = ConfigStorage._(_resolvePath());
    return _instance!;
  }

  static String _resolvePath() {
    final baseDir = kDebugMode
        ? Directory.current.path
        : p.dirname(Platform.resolvedExecutable);
    final configDir = Directory(p.join(baseDir, 'config'));
    if (!configDir.existsSync()) {
      configDir.createSync(recursive: true);
    }
    return p.join(configDir.path, 'preferences.json');
  }

  /// 读取 JSON 文件到内存
  void _load() {
    final file = File(_filePath);
    if (!file.existsSync()) return;
    try {
      _cache = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      _cache = {};
    }
  }

  /// 延迟异步写回磁盘（100ms 防抖），避免频繁同步 I/O 阻塞 UI
  void _save() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 100), _flush);
  }

  /// 实际异步写入
  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;
    final file = File(_filePath);
    try {
      await file.writeAsString(json.encode(_cache));
    } catch (_) {
      // 写入失败静默忽略
    }
  }

  /// 读取字符串值
  String? getString(String key) {
    return _cache[key] as String?;
  }

  /// 写入字符串值
  void setString(String key, String value) {
    _cache[key] = value;
    _save();
  }

  /// 读取任意 JSON 值
  dynamic get(String key) {
    return _cache[key];
  }

  /// 写入任意 JSON 值
  void set(String key, dynamic value) {
    _cache[key] = value;
    _save();
  }

  /// 清除指定 key
  void remove(String key) {
    _cache.remove(key);
    _save();
  }

  /// 测试可见：重置单例（每个测试用独立文件）
  @visibleForTesting
  static void reset([String? filePath]) {
    _instance = ConfigStorage._(filePath ?? _resolvePath());
  }
}
