import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 沉浸式自定义标题栏 — 替代 Windows 原生标题栏，支持拖拽移动 + 最小化/最大化/关闭
///
/// [DragToMoveArea] 仅包裹左侧标题区域，右侧窗口控制按钮脱离拖拽区，
/// 彻底消除手势竞技（Gesture Arena Conflict）带来的点击延迟。
///
/// 通过 [WindowListener] 监听窗口状态，最大化时自动将按钮切换为还原图标。
class CustomTitleBar extends StatefulWidget {
  const CustomTitleBar({super.key});

  @override
  State<CustomTitleBar> createState() => _CustomTitleBarState();
}

class _CustomTitleBarState extends State<CustomTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    // 启动时同步当前窗口状态
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // ── WindowListener 回调 ──
  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  void onWindowRestore() {
    // 从最小化恢复时也可能是最大化状态
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _isMaximized = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.5),
      ),
      child: Row(
        children: [
          // 左侧：可拖拽区域（标题 + 空白），Expanded 撑满剩余空间
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '财务与发票管理系统',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 右侧：窗口控制按钮 — 完全脱离拖拽区，点击零延迟
          _WinBtn(Icons.minimize, () => windowManager.minimize()),
          // 最大化/还原按钮：根据窗口状态切换图标与行为
          _WinBtn(
            _isMaximized ? Icons.filter_none : Icons.crop_square,
            () => _isMaximized ? windowManager.unmaximize() : windowManager.maximize(),
          ),
          _WinBtn(Icons.close, () => windowManager.close(), isClose: true),
        ],
      ),
    );
  }
}

/// 窗口控制按钮 — 使用 [InkWell] 实现原生 hover 效果，无 setState 闪烁
class _WinBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  const _WinBtn(this.icon, this.onTap, {this.isClose = false});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final iconColor = isClose ? Colors.redAccent : onSurface;

    return SizedBox(
      width: 46,
      height: double.infinity,
      child: Tooltip(
        message: isClose ? '关闭' : (icon == Icons.minimize ? '最小化' : '最大化/还原'),
        child: InkWell(
          onTap: onTap,
          hoverColor:
              isClose ? Colors.red : Colors.white.withValues(alpha: 0.12),
          splashColor:
              isClose ? Colors.red.shade300 : Colors.white.withValues(alpha: 0.2),
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}
