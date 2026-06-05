import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'pages/dashboard/unified_dashboard_page.dart';
import 'package:flutter/foundation.dart';
import 'logger.dart';
import 'config.dart';
import 'widgets/custom_title_bar.dart';

// 1. 全局持有后端二进制文件的进程句柄
Process? _backendProcess;

/// 后端就绪信号 — Dashboard 等待此信号后再发起 API 请求
Completer<void> _backendReadyCompleter = Completer<void>();

/// 供 Dashboard 在 initState 中 await，确保后端 HTTP 服务已可接受连接
Future<void> get backendReady => _backendReadyCompleter.future;

/// 测试可见：强制完成 backendReady 信号（模拟后端已就绪）
@visibleForTesting
void forceBackendReady() {
  if (!_backendReadyCompleter.isCompleted) {
    _backendReadyCompleter.complete();
  }
}

/// 获取 api_server/ 工作目录
String get _backendDir {
  if (kDebugMode) {
    return p.normalize(p.join(Directory.current.path, '..', 'core_api'));
  }
  return p.join(p.dirname(Platform.resolvedExecutable), 'api_server');
}

/// 全局重启回调：settings_dialog 保存路径后调用，触发 Sidecar 重启
Future<bool> restartBackend() async {
  AppLogger.info('【Sidecar】收到重启请求，准备重新拉起后端引擎...');

  // 重置就绪信号
  if (_backendReadyCompleter.isCompleted) {
    _backendReadyCompleter = Completer<void>();
  }

  // 1. 杀死旧进程
  if (_backendProcess != null) {
    _backendProcess!.kill();
    AppLogger.info('【Sidecar】已杀死旧后端进程 PID=${_backendProcess!.pid}');
    _backendProcess = null;
  }

  // 2. 短暂等待端口释放
  await Future.delayed(const Duration(milliseconds: 800));

  // 3. 重新启动（内部会完成 _backendReadyCompleter）
  await _startBackendEngine();

  // 4. 兜底确认
  return await _waitForBackendReady();
}

/// 健康检查轮询：每 500ms 请求一次，最多等 15 秒
Future<bool> _waitForBackendReady() async {
  final sw = Stopwatch()..start();
  while (sw.elapsedMilliseconds < 15000) {
    try {
      final resp = await http
          .get(Uri.parse('${AppConfig.baseUrl}/api/dashboard/summary'))
          .timeout(const Duration(seconds: 2));
      if (resp.statusCode == 200) {
        AppLogger.info('【Sidecar】后端就绪，耗时=${sw.elapsedMilliseconds}ms');
        return true;
      }
    } catch (_) {
      // 后端尚未就绪，继续等待
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }
  AppLogger.error('【Sidecar】等待后端就绪超时 (15s)');
  return false;
}

void main() async {
  // 必须确保 Flutter 绑定初始化，才能与原生系统通信
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化日志系统（缓冲队列自动启动，批量上报到后端统一日志）
  AppLogger.info('Flutter 客户端启动');

  // 初始化 window_manager
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1024, 768),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: '发票管理系统',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 注册窗口关闭监听器
  windowManager.addListener(_WindowCloseListener());

  // 先启动 UI
  runApp(const InvoiceSystemApp());

  // 🚨 清场 + 🚀 拉起后端
  await _cleanGhostProcess();
  await _startBackendEngine();
}

// ── 启动后端引擎 ──
Future<void> _startBackendEngine() async {
  String exePath;
  List<String> processArgs;
  String? workingDir;

  if (kDebugMode) {
    AppLogger.info('【Sidecar】开发模式：正在使用本地 Python 环境热启动...');
    exePath = r'C:/Users/ninpa/miniconda3/envs/Invoice-Management-System/python.exe';
    final currentDir = Directory.current.path;
    processArgs = [
      '-X', 'utf8',
      '-u',
      p.normalize(p.join(currentDir, '..', 'core_api', 'main.py')),
    ];
    workingDir = p.normalize(p.join(currentDir, '..', 'core_api'));
  } else {
    AppLogger.info('【Sidecar】生产模式：正在拉起 Nuitka 独立免安装引擎...');
    String currentDir = p.dirname(Platform.resolvedExecutable);
    exePath = p.join(currentDir, 'api_server', 'main.exe');
    processArgs = [];
    workingDir = p.join(currentDir, 'api_server');
  }

  try {
    _backendProcess = await Process.start(
      exePath,
      processArgs,
      workingDirectory: workingDir,
      environment: {
        'PYTHONIOENCODING': 'utf-8',
        'PYTHONUTF8': '1',
      },
    );

    _backendProcess!.stdout.listen((bytes) {
      if (kDebugMode) {
        final text = utf8.decode(bytes, allowMalformed: true).trim();
        if (text.isNotEmpty) debugPrint('【后端stdout】$text');
      }
    });
    _backendProcess!.stderr.listen((bytes) {
      if (kDebugMode) {
        final text = utf8.decode(bytes, allowMalformed: true).trim();
        if (text.isNotEmpty) debugPrint('【后端stderr】$text');
      }
    });
  } catch (e) {
    AppLogger.error('后端引擎启动严重失败', e);
    return;
  }

  // 等待 port.txt 出现（后端写入后说明已绑定端口）
  await _waitForPortFile();

  // 等待 HTTP 服务完全就绪（port.txt 写入 ≠ 可接受连接）
  final ready = await _waitForBackendReady();

  // 通知 Dashboard：后端已就绪，可以发起 API 请求
  if (!_backendReadyCompleter.isCompleted) {
    if (ready) {
      _backendReadyCompleter.complete();
      AppLogger.info('【Sidecar】后端就绪信号已发出');
    } else {
      _backendReadyCompleter.completeError('后端启动超时');
    }
  }
}

/// 等待后端写入 port.txt，读取端口并更新 AppConfig
Future<void> _waitForPortFile() async {
  final portFile = File(p.join(_backendDir, 'config', 'port.txt'));

  for (int i = 0; i < 30; i++) {
    await Future.delayed(const Duration(milliseconds: 200));
    if (await portFile.exists()) {
      try {
        final portStr = (await portFile.readAsString()).trim();
        final port = int.parse(portStr);
        AppConfig.updatePort(port);
        AppLogger.info('【Sidecar】读取到后端端口: $port');
        return;
      } catch (e) {
        AppLogger.warning('【Sidecar】port.txt 解析失败: $e');
      }
    }
  }
  AppLogger.warning('【Sidecar】等待 port.txt 超时 (6s)，使用默认端口');
}

// ── 清场：基于 PID 文件精准杀除 ──
Future<void> _cleanGhostProcess() async {
  final pidFile = File(p.join(_backendDir, 'config', 'backend.pid'));
  final portFile = File(p.join(_backendDir, 'config', 'port.txt'));

  // ── 方案 A：读 PID 文件精准杀 ──
  if (await pidFile.exists()) {
    try {
      final pidStr = (await pidFile.readAsString()).trim();
      final pid = int.parse(pidStr);
      AppLogger.info('【清道夫】发现残留 PID 文件 PID=$pid，验证进程是否存在...');

      // 验证该 PID 的进程是否仍在运行
      final result = await Process.run('tasklist', [
        '/FI', 'PID eq $pid', '/FO', 'CSV', '/NH',
      ]);
      final output = (result.stdout as String).trim();
      if (output.contains('$pid')) {
        AppLogger.info('【清道夫】PID=$pid 进程存活，正在杀死...');
        await Process.run('taskkill', ['/F', '/PID', '$pid', '/T']);
        AppLogger.info('【清道夫】已杀死残留进程 PID=$pid');
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        AppLogger.info('【清道夫】PID=$pid 进程已不存在，清理 PID 文件');
      }
    } catch (e) {
      AppLogger.warning('【清道夫】PID 方式清场失败: $e');
    }
    // 无论如何删除 PID 文件
    try { await pidFile.delete(); } catch (_) {}
  } else {
    // ── 方案 B：回退 — 用端口反查（兼容旧版未写 PID 的残留）──
    AppLogger.info('【清道夫】无 PID 文件，尝试端口反查...');
    final port = '18090';
    // 如果 port.txt 存在（非正常退出遗留下来的），读取它
    String targetPort = port;
    if (await portFile.exists()) {
      try {
        targetPort = (await portFile.readAsString()).trim();
      } catch (_) {}
    }
    try {
      final netstat = await Process.run('cmd', [
        '/c', 'netstat -ano | findstr :$targetPort | findstr LISTENING'
      ]);
      final output = (netstat.stdout as String).trim();
      if (output.isNotEmpty) {
        final lines = output.split('\n');
        for (final line in lines) {
          final parts = line.trim().split(RegExp(r'\s+'));
          if (parts.length >= 5) {
            final pid = parts.last;
            await Process.run('taskkill', ['/F', '/PID', pid, '/T']);
            AppLogger.info('【清道夫】(回退) 已杀死占用端口 $targetPort 的进程 PID=$pid');
          }
        }
      }
    } catch (_) {}
  }
}

// ── 窗口关闭时销毁 ──
class _WindowCloseListener extends WindowListener {
  @override
  void onWindowClose() async {
    AppLogger.info('【宿主销毁】检测到 Flutter 窗口关闭，正在释放本地服务...');

    if (_backendProcess != null) {
      bool isKilled = _backendProcess!.kill();
      AppLogger.info('【Sidecar】免安装后端引擎 (PID: ${_backendProcess!.pid}) 销毁状态: $isKilled');
    }

    // 删除 PID 文件（确保下次启动不会被误清）
    try {
      final pidFile = File(p.join(_backendDir, 'config', 'backend.pid'));
      if (await pidFile.exists()) {
        await pidFile.delete();
        AppLogger.info('【宿主销毁】已清理 backend.pid');
      }
    } catch (_) {}

    // 重置后端就绪信号（Completer 已完成状态下无法再次 complete）
    if (!_backendReadyCompleter.isCompleted) {
      _backendReadyCompleter.completeError('窗口已关闭');
    }

    await windowManager.destroy();
  }
}

// ================== UI ==================

class InvoiceSystemApp extends StatelessWidget {
  const InvoiceSystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '发票管理系统',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
        fontFamily: 'Microsoft YaHei',
        scrollbarTheme: ScrollbarThemeData(
          thickness: WidgetStateProperty.all(8),
          thumbColor: WidgetStateProperty.all(Colors.blueGrey.withValues(alpha: 0.4)),
          radius: const Radius.circular(4),
        ),
      ),
      home: const MainLayout(),
    );
  }
}

/// 单页驾驶舱布局 — 标题栏 + 全屏融合页面
class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          CustomTitleBar(),
          Expanded(child: UnifiedDashboardPage()),
        ],
      ),
    );
  }
}
