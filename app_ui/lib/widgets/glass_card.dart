import 'dart:ui';
import 'package:flutter/material.dart';

/// 毛玻璃质感卡片 — 独立 StatelessWidget
///
/// 提供统一的高级亚克力（Glassmorphism）风格容器，
/// 用于整个财务驾驶舱系统中所有需要毛玻璃效果的卡片区域。
class GlassCard extends StatelessWidget {
  /// 卡片内部内容（必填）
  final Widget child;

  /// 内边距，默认 [EdgeInsets.all(16)]
  final EdgeInsetsGeometry padding;

  /// 圆角半径，默认 [BorderRadius.circular(12)]
  final BorderRadiusGeometry borderRadius;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        // sigma 从 16 降至 4 — 视觉效果几乎不变，但 saveLayer 开销大幅降低
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: RepaintBoundary(
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.80),
              borderRadius: borderRadius,
              border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
