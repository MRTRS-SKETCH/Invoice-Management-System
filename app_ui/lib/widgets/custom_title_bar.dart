import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// 沉浸式自定义标题栏 — 替代 Windows 原生标题栏，支持拖拽移动 + 最小化/最大化/关闭
class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    final surfaceColor = Theme.of(context).colorScheme.surface;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return DragToMoveArea(
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: surfaceColor.withValues(alpha: 0.5),
        ),
        child: Row(
          children: [
            const SizedBox(width: 16),
            Text(
              '财务与发票管理系统',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: onSurface,
              ),
            ),
            const Spacer(),
            _WinBtn(Icons.minimize, () => windowManager.minimize()),
            _WinBtn(Icons.crop_square, () => windowManager.maximize()),
            _WinBtn(Icons.close, () => windowManager.close(), isClose: true),
          ],
        ),
      ),
    );
  }
}

class _WinBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isClose;
  const _WinBtn(this.icon, this.onTap, {this.isClose = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 46,
        height: 40,
        child: Icon(
          icon,
          size: 16,
          color: isClose
              ? Colors.redAccent
              : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
