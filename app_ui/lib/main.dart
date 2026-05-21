import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  // 必须确保 Flutter 绑定初始化，才能与原生窗口通信
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化 window_manager
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1024, 768),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
    title: '财务与发票管理系统',
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const InvoiceSystemApp());
}

class InvoiceSystemApp extends StatelessWidget {
  const InvoiceSystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Invoice System',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MainDashboard(),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

// 混入 WindowListener 以监听原生窗口事件
class _MainDashboardState extends State<MainDashboard> with WindowListener {
  Process? _pythonProcess;
  bool _isBackendReady = false;
  String _backendStatus = "正在启动后端服务...";

  @override
  void initState() {
    super.initState();
    // 注册窗口事件监听器
    windowManager.addListener(this);
    // 启动 Python 侧车进程
    _startPythonSidecar();
  }

  @override
  void dispose() {
    // 移除监听器
    windowManager.removeListener(this);
    super.dispose();
  }

  /// 核心逻辑：拉起 Python 进程
  Future<void> _startPythonSidecar() async {
    try {
      // 获取当前工作目录 (app_ui) 并回退到上一级找到 core_api
      final currentDir = Directory.current.path;

      final pythonExecutable = "C:/Users/ninpa/miniconda3/envs/Invoice-Management-System/python.exe";
      final mainPyScript = p.normalize(p.join(currentDir, '..', 'core_api', 'main.py'));

      debugPrint("尝试启动 Python 进程: $pythonExecutable $mainPyScript");

      // 启动进程
      _pythonProcess = await Process.start(
        pythonExecutable,
        [mainPyScript],
        environment: {'PYTHONIOENCODING': 'utf-8'},
        runInShell: false, 
      );

      setState(() {
        _isBackendReady = true;
        _backendStatus = "后端服务已成功启动 (PID: ${_pythonProcess?.pid})";
      });

      // 监听 Python 进程的标准输出（便于在 Flutter 控制台看 FastAPI 的日志）
      _pythonProcess?.stdout.listen((event) {
        debugPrint('【Python Sidecar 错误】: ${utf8.decode(event, allowMalformed: true)}');
      });

      _pythonProcess?.stderr.listen((event) {
        debugPrint('【Python Sidecar 错误】: ${String.fromCharCodes(event)}');
      });

    } catch (e) {
      setState(() {
        _isBackendReady = false;
        _backendStatus = "启动后端服务失败: $e";
      });
      debugPrint("进程启动异常: $e");
    }
  }

  /// 核心逻辑：拦截窗口关闭事件并清理孤儿进程
  @override
  void onWindowClose() async {
    debugPrint("捕获到窗口关闭事件，准备清理环境...");
    
    if (_pythonProcess != null) {
      // 强制杀死 Python 进程
      bool killed = _pythonProcess!.kill(ProcessSignal.sigterm);
      debugPrint("Python 进程 (PID: ${_pythonProcess!.pid}) 是否被成功终止: $killed");
    }
    
    // 销毁窗口并退出应用
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("仪表盘"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isBackendReady ? Icons.check_circle : Icons.warning,
              color: _isBackendReady ? Colors.green : Colors.orange,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              _backendStatus,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            const Text("如果看到 FastAPI 的启动日志，说明 Flutter 与 Python 已成功建联！"),
          ],
        ),
      ),
    );
  }
}