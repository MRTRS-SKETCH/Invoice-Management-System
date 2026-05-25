import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'expense_flow_page.dart';
import 'invoice_manager_page.dart';
import 'dashboard_page.dart';
import 'package:flutter/foundation.dart';

// 1. 全局持有后端二进制文件的进程句柄
Process? _backendProcess;

void main() async {
  // 必须确保 Flutter 绑定初始化，才能与原生系统通信
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 window_manager
  await windowManager.ensureInitialized();

  // 🚨 2. 开局自动清场：强杀后台可能残留的旧 main.exe，防止端口冲突
  await _cleanGhostProcess();

  // 🚀 3. 伴随启动：拉起我们刚刚用 Nuitka 编译出来的独立免安装引擎
  await _startBackendEngine();

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

  // 🕵️‍♂️ 4. 注册窗口监听器：当用户点击右上角 [X] 关闭软件时，自动杀死后端
  windowManager.addListener(_WindowCloseListener());

  runApp(const InvoiceSystemApp());
}

// 核心函数：未来你要修改启动路径，只需要改这里！
Future<void> _startBackendEngine() async {
  String exePath;
  List<String> processArgs;

  // 智能判断：当前是否处于 Debug 开发模式？
  if (kDebugMode) {
    // 【开发模式】：使用你原来的 Conda/venv 环境直接跑 main.py
    debugPrint('【Sidecar】🐛 开发模式：正在使用本地 Python 环境热启动...');
    exePath = r'E:\flutter\Invoice-Management-System\core_api\venv\Scripts\python.exe';
    processArgs = [r'E:\flutter\Invoice-Management-System\core_api\main.py'];
  } else {
    // 【生产模式】：当你执行 flutter build windows 打包正式版时，会自动走到这里
    debugPrint('【Sidecar】🚀 生产模式：正在拉起 Nuitka 独立免安装引擎...');
    String currentDir = p.dirname(Platform.resolvedExecutable);
    exePath = p.join(currentDir, 'api_server', 'main.exe');
    processArgs = [];
  }

  try {
    _backendProcess = await Process.start(exePath, processArgs);
    
    // 管道监听：把后端的输出重定向到 Flutter 控制台
    _backendProcess!.stdout.transform(utf8.decoder).listen((data) {
      debugPrint('【后端】: $data');
    });
    _backendProcess!.stderr.transform(utf8.decoder).listen((data) {
      debugPrint('【后端错误】: $data');
    });
  } catch (e) {
    debugPrint('❌ 后端引擎启动严重失败: $e');
  }
}

// 开局清道夫：强杀本地可能残留的同名进程
Future<void> _cleanGhostProcess() async {
  try {
    debugPrint('【清道夫】正在检查并清理残留的后端进程...');
    // 强杀所有叫 main.exe 的进程树
    await Process.run('taskkill', ['/F', '/IM', 'main.exe', '/T']);
  } catch (e) {
    // 如果没有残留，taskkill 会报错，这里直接无视即可
  }
}

// 终极宿主绑定：窗口关闭时，不留任何后患
class _WindowCloseListener extends WindowListener {
  @override
  void onWindowClose() async {
    debugPrint('【宿主销毁】检测到 Flutter 窗口关闭，正在释放本地服务...');
    
    if (_backendProcess != null) {
      bool isKilled = _backendProcess!.kill();
      debugPrint('【Sidecar】免安装后端引擎 (PID: ${_backendProcess!.pid}) 销毁状态: $isKilled');
    }
    
    // 确保释放完毕后再完全撤销窗口
    await windowManager.destroy();
  }
}

// ================== UI ==================

class InvoiceSystemApp extends StatelessWidget {
  const InvoiceSystemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Invoice System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _selectedIndex = 0;

  final List<Widget> pages = const [
    DashboardPage(),
    ExpenseFlowPage(),
    InvoiceManagerPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
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
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: pages[_selectedIndex],
            ),
          ),
        ],
      ),
    );
  }
}