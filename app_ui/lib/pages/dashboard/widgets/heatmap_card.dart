import 'package:flutter/material.dart';
import '../../../widgets/glass_card.dart';

/// 开销频次热力图卡片 — 横向滚动 + 固定 3 行 + hover 放大动画
///
/// 按日聚合的开销记录数映射为五级色阶，鼠标悬浮时方块放大至 1.3 倍并浮起阴影。
class HeatmapCard extends StatelessWidget {
  final List<dynamic> heatmap;

  const HeatmapCard({super.key, required this.heatmap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '业务发生频次 (近3个月)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: heatmap.isEmpty
                ? const Center(
                    child: Text('暂无数据',
                        style: TextStyle(color: Colors.black38)))
                : RepaintBoundary(
                    child: GridView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        childAspectRatio: 1,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: heatmap.length,
                      itemBuilder: (ctx, i) {
                        final count = (heatmap[i]['count'] as int?) ?? 0;
                        final Color bg;
                        if (count == 0) {
                          bg = const Color(0xFFE2E8F0);
                        } else if (count <= 1) {
                          bg = const Color(0xFFC7D2FE);
                        } else if (count <= 3) {
                          bg = const Color(0xFF818CF8);
                        } else if (count <= 6) {
                          bg = const Color(0xFF4F46E5);
                        } else {
                          bg = const Color(0xFF312E81);
                        }
                        return _HeatmapCell(
                          tooltip: '${heatmap[i]['date']}: $count 笔',
                          color: bg,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
/// 热力图单元格 — 轻量 hover 样式（无 AnimatedContainer，无 transform，避免 layout 抖动）
// ═══════════════════════════════════════════════════════════════════════════════
class _HeatmapCell extends StatefulWidget {
  final Color color;
  final String tooltip;
  const _HeatmapCell({required this.color, required this.tooltip});

  @override
  State<_HeatmapCell> createState() => _HeatmapCellState();
}

class _HeatmapCellState extends State<_HeatmapCell> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(_isHovered ? 4 : 2),
            border: _isHovered
                ? Border.all(color: Colors.white, width: 2)
                : null,
            boxShadow: _isHovered
                ? [const BoxShadow(
                    color: Colors.black26, blurRadius: 4, spreadRadius: 1)]
                : [],
          ),
        ),
      ),
    );
  }
}
