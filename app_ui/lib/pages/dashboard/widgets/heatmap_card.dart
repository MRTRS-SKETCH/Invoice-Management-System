import 'package:flutter/material.dart';
import '../../../widgets/glass_card.dart';

/// 开销频次热力图卡片 — 横向滚动 + 自适应行数 + 默认展示最新日期
///
/// 按日聚合的开销记录数映射为五级色阶。
/// 根据可用高度动态调整行数，默认滚动到最新日期列。
class HeatmapCard extends StatefulWidget {
  final List<dynamic> heatmap;

  const HeatmapCard({super.key, required this.heatmap});

  @override
  State<HeatmapCard> createState() => _HeatmapCardState();
}

class _HeatmapCardState extends State<HeatmapCard> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _didInitialScroll = false;

  @override
  void didUpdateWidget(covariant HeatmapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heatmap != widget.heatmap) {
      _didInitialScroll = false;
    }
  }

  /// 仅在布局稳定后执行一次滚动，避免干扰 GridView 子项布局
  void _tryScrollToLatest() {
    if (_didInitialScroll || !_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return; // 内容尚未撑开，等下一帧
    _didInitialScroll = true;
    // endOfFrame 确保所有子项布局完成后再跳转
    WidgetsBinding.instance.endOfFrame.then((_) {
      if (_scrollCtrl.hasClients && mounted) {
        _scrollCtrl.jumpTo(max);
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '业务发生频次',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: widget.heatmap.isEmpty
                ? const Center(
                    child: Text('暂无数据',
                        style: TextStyle(color: Colors.black38)))
                : LayoutBuilder(
                    builder: (ctx, constraints) {
                      // 固定 3 行
                      const rows = 3;
                      // 在布局完成后滚动到最新日期（右侧）
                      WidgetsBinding.instance
                          .addPostFrameCallback((_) => _tryScrollToLatest());
                      return RepaintBoundary(
                        child: GridView.builder(
                          controller: _scrollCtrl,
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: rows,
                            childAspectRatio: 1,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                          itemCount: widget.heatmap.length,
                          itemBuilder: (ctx, i) {
                            final count =
                                (widget.heatmap[i]['count'] as int?) ?? 0;
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
                              tooltip:
                                  '${widget.heatmap[i]['date']}: $count 笔',
                              color: bg,
                            );
                          },
                        ),
                      );
                    },
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
