import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'expense_flow_page.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey), // 偏商务的蓝灰色调
        useMaterial3: true,
      ),
      home: const MainLayout(),
    );
  }
}

// ---------------------------------------------------------
// 主应用骨架 (Main Layout) 包含侧边栏与进程管理
// ---------------------------------------------------------
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

// 混入 WindowListener 以监听原生窗口事件
class _MainLayoutState extends State<MainLayout> with WindowListener {
  // 侧边栏状态
  int _selectedIndex = 0;

  // Python 进程状态
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
      // 保持你之前成功配置的 Conda 绝对路径
      final pythonExecutable = "C:/Users/ninpa/miniconda3/envs/Invoice-Management-System/python.exe";
      final currentDir = Directory.current.path;
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

      // 监听 Python 进程的标准输出，强制 UTF-8 解码避免乱码
      _pythonProcess?.stdout.listen((event) {
        debugPrint('【Python Sidecar 日志】: ${utf8.decode(event, allowMalformed: true)}');
      });

      _pythonProcess?.stderr.listen((event) {
        debugPrint('【Python Sidecar 错误】: ${utf8.decode(event, allowMalformed: true)}');
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
    // 动态构建右侧页面，以便将后端的连接状态传递给仪表盘显示
    final List<Widget> pages = [
      // 页面 0: 全局看板
      Center(
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
            const SizedBox(height: 48),
            const Text('全局看板 (Dashboard) - 待开发', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      // 页面 1: 业务流水
      const ExpenseFlowPage(),
      // 页面 2: 发票管理
      const Center(
        child: Text('发票与 PDF 管理 (Invoice Manager) - 待开发', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      ),
    ];

    return Scaffold(
      body: Row(
        children: [
          // 1. 左侧导航侧边栏
          NavigationRail(
            extended: true,
            minExtendedWidth: 200,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('全局看板'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: Text('业务流水'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.picture_as_pdf_outlined),
                selectedIcon: Icon(Icons.picture_as_pdf),
                label: Text('发票管理'),
              ),
            ],
          ),
          
          // 侧边栏与内容区之间的垂直分割线
          const VerticalDivider(thickness: 1, width: 1),
          
          // 2. 右侧动态内容区
          Expanded(
            child: Container(
              // 给背景加一点极浅的灰色，区分导航栏和内容区
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
              child: pages[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }
}